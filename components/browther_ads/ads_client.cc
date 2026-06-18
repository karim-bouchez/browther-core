// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/browther_ads/ads_client.h"

#include <algorithm>
#include <string_view>
#include <utility>

#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/logging.h"
#include "base/strings/strcat.h"
#include "base/strings/string_number_conversions.h"
#include "base/time/time.h"
#include "base/uuid.h"
#include "base/values.h"
#include "brave/components/browther_ads/ads_config.h"
#include "build/build_config.h"
#include "crypto/hmac.h"
#include "net/base/load_flags.h"
#include "net/http/http_request_headers.h"
#include "net/http/http_response_headers.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/shared_url_loader_factory.h"
#include "services/network/public/cpp/simple_url_loader.h"
#include "services/network/public/mojom/url_response_head.mojom.h"
#include "url/gurl.h"

namespace browther_ads {

namespace {

// Délai de batch des impressions : on accumule les tokens des pubs réellement
// vues puis on flush par paquet. 10 s = compromis entre fraîcheur et bruit
// réseau (cf. INTEGRATION.md § 4). Les tokens expirent en 30 min côté serveur.
constexpr base::TimeDelta kImpressionFlushDelay = base::Seconds(10);

// Cap serveur : 50 tokens par POST /v1/track/impressions.
constexpr size_t kMaxImpressionBatch = 50;

// Plateforme envoyée au serve (alimente le breakdown dashboard). Le même code
// C++ build pour macOS, Windows desktop et Android ; on reporte la vraie
// plateforme.
constexpr char kPlatform[] =
#if BUILDFLAG(IS_ANDROID)
    "android";
#elif BUILDFLAG(IS_MAC)
    "macos";
#elif BUILDFLAG(IS_WIN)
    "windows";
#elif BUILDFLAG(IS_LINUX)
    "linux";
#else
    "desktop";
#endif

constexpr net::NetworkTrafficAnnotationTag kServeTrafficAnnotation =
    net::DefineNetworkTrafficAnnotation("browther_ads_serve", R"ANNOT(
        semantics {
          sender: "Browther Ads"
          description:
            "Fetches house/community banner ads from the dev&din ad network "
            "to display in a banner below the favorites on the Browther new "
            "tab page. Sends only the placement name, platform and requested "
            "count. No URLs visited, no page content, no PII."
          trigger:
            "Opening a new tab page."
          data:
            "Placement identifier, platform name, requested ad count, and an "
            "HMAC signature computed from the embedded publisher key."
          destination: OTHER
          destination_other: "ads-api.devndin.com (self-hosted on OVH)"
        }
        policy {
          cookies_allowed: NO
          setting:
            "There is no dedicated setting; the banner is only shown when ads "
            "are eligible. Disabling background images does not affect it."
          policy_exception_justification:
            "Not implemented, consumer-facing browser."
        })ANNOT");

constexpr net::NetworkTrafficAnnotationTag kTrackTrafficAnnotation =
    net::DefineNetworkTrafficAnnotation("browther_ads_track", R"ANNOT(
        semantics {
          sender: "Browther Ads"
          description:
            "Reports that a Browther new tab page banner ad was actually "
            "displayed to the user, so the ad network can count impressions. "
            "Sends only opaque single-use impression tokens previously "
            "returned by the serve endpoint. No PII."
          trigger:
            "A served banner ad scrolled into view on the new tab page."
          data:
            "A batch of opaque impression tokens."
          destination: OTHER
          destination_other: "ads-api.devndin.com (self-hosted on OVH)"
        }
        policy {
          cookies_allowed: NO
          setting:
            "There is no dedicated setting; impressions are only sent for ads "
            "that were actually shown."
          policy_exception_justification:
            "Not implemented, consumer-facing browser."
        })ANNOT");

// epoch UNIX en secondes (fenêtre serveur ±5 min).
std::string UnixTimestampSeconds() {
  return base::NumberToString(
      (base::Time::Now() - base::Time::UnixEpoch()).InSeconds());
}

// hex(HMAC-SHA256(secret, "{timestamp}.{nonce}.{rawBody}")) — lowercase.
std::string SignBody(std::string_view timestamp,
                     std::string_view nonce,
                     std::string_view raw_body) {
  const std::string message =
      base::StrCat({timestamp, ".", nonce, ".", raw_body});
  const std::array<uint8_t, 32> signature = crypto::hmac::SignSha256(
      base::as_byte_span(std::string_view(kAdsPublisherSecret)),
      base::as_byte_span(message));
  return base::HexEncodeLower(signature);
}

}  // namespace

ServedAd::ServedAd() = default;
ServedAd::ServedAd(const ServedAd&) = default;
ServedAd& ServedAd::operator=(const ServedAd&) = default;
ServedAd::ServedAd(ServedAd&&) noexcept = default;
ServedAd& ServedAd::operator=(ServedAd&&) noexcept = default;
ServedAd::~ServedAd() = default;

AdsClient::AdsClient(
    scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory)
    : url_loader_factory_(std::move(url_loader_factory)) {}

AdsClient::~AdsClient() {
  // Best effort : flush les impressions restantes au teardown de l'onglet.
  FlushImpressions();
}

// static
bool AdsClient::IsConfigured() {
  return !std::string_view(kAdsApiUrl).empty() &&
         !std::string_view(kAdsPublisherId).empty() &&
         !std::string_view(kAdsPublisherSecret).empty();
}

void AdsClient::Serve(const std::string& placement,
                      int count,
                      ServeCallback callback) {
  if (!IsConfigured() || !url_loader_factory_) {
    std::move(callback).Run({});
    return;
  }

  base::DictValue payload;
  payload.Set("placement", placement);
  payload.Set("platform", kPlatform);
  payload.Set("count", count);

  std::string body;
  if (!base::JSONWriter::Write(payload, &body)) {
    std::move(callback).Run({});
    return;
  }

  const std::string timestamp = UnixTimestampSeconds();
  const std::string nonce =
      base::Uuid::GenerateRandomV4().AsLowercaseString();
  const std::string signature = SignBody(timestamp, nonce, body);

  auto request = std::make_unique<network::ResourceRequest>();
  request->url = GURL(base::StrCat({kAdsApiUrl, "/v1/serve"}));
  request->method = "POST";
  request->credentials_mode = network::mojom::CredentialsMode::kOmit;
  request->load_flags = net::LOAD_DO_NOT_SAVE_COOKIES;
  request->headers.SetHeader("X-Publisher-Id", kAdsPublisherId);
  request->headers.SetHeader("X-Timestamp", timestamp);
  request->headers.SetHeader("X-Nonce", nonce);
  request->headers.SetHeader("X-Signature", signature);

  auto loader = network::SimpleURLLoader::Create(std::move(request),
                                                 kServeTrafficAnnotation);
  // `body` doit être exactement les octets signés.
  loader->AttachStringForUpload(body, "application/json");

  auto* loader_ptr = loader.get();
  loader_ptr->DownloadToString(
      url_loader_factory_.get(),
      base::BindOnce(&AdsClient::OnServeComplete, weak_factory_.GetWeakPtr(),
                     std::move(callback), std::move(loader)),
      /*max_body_size=*/64 * 1024);
}

void AdsClient::OnServeComplete(
    ServeCallback callback,
    std::unique_ptr<network::SimpleURLLoader> loader,
    std::optional<std::string> response_body) {
  const int net_error = loader->NetError();
  const int response_code =
      loader->ResponseInfo() && loader->ResponseInfo()->headers
          ? loader->ResponseInfo()->headers->response_code()
          : 0;

#if BUILDFLAG(IS_ANDROID)
  // [BrowtherAds][debug Android] visibilité serve dans logcat (tag "chromium").
  LOG(INFO) << "[BrowtherAds] serve complete: net_error=" << net_error
            << " http=" << response_code
            << " body_bytes=" << (response_body ? response_body->size() : 0);
#endif

  if (net_error != net::OK || response_code < 200 || response_code >= 300 ||
      !response_body) {
    VLOG(1) << "[BrowtherAds] serve failed: net_error=" << net_error
            << " http=" << response_code;
    std::move(callback).Run({});
    return;
  }

  std::optional<base::DictValue> root =
      base::JSONReader::ReadDict(*response_body, base::JSON_PARSE_RFC);
  if (!root) {
    std::move(callback).Run({});
    return;
  }

  const base::ListValue* ads = root->FindList("ads");
  if (!ads) {
    std::move(callback).Run({});
    return;
  }

  std::vector<ServedAd> result;
  for (const base::Value& entry : *ads) {
    const base::DictValue* ad = entry.GetIfDict();
    if (!ad) {
      continue;
    }
    const std::string* id = ad->FindString("id");
    const std::string* image_url = ad->FindString("imageUrl");
    const std::string* click_url = ad->FindString("clickUrl");
    const std::string* impression_token = ad->FindString("impressionToken");
    if (!id || !image_url || id->empty() || image_url->empty()) {
      continue;
    }

    ServedAd served;
    served.id = *id;
    served.image_url = *image_url;
    served.click_url = click_url ? *click_url : std::string();
    served.impression_token =
        impression_token ? *impression_token : std::string();
    served_[served.id] = served;
    result.push_back(std::move(served));
  }

  std::move(callback).Run(std::move(result));
}

void AdsClient::MarkVisible(const std::string& id) {
  auto it = served_.find(id);
  if (it == served_.end() || it->second.impression_token.empty()) {
    return;
  }
  // Idempotent : une impression par pub servie.
  if (reported_ids_.contains(id)) {
    return;
  }
  reported_ids_[id] = true;
  pending_impressions_.push_back(it->second.impression_token);
  ScheduleImpressionFlush();
}

GURL AdsClient::GetClickURL(const std::string& id) const {
  auto it = served_.find(id);
  if (it == served_.end() || it->second.click_url.empty()) {
    return GURL();
  }
  return GURL(it->second.click_url);
}

void AdsClient::ScheduleImpressionFlush() {
  if (flush_timer_.IsRunning() || pending_impressions_.empty()) {
    return;
  }
  flush_timer_.Start(FROM_HERE, kImpressionFlushDelay,
                     base::BindOnce(&AdsClient::FlushImpressions,
                                    weak_factory_.GetWeakPtr()));
}

void AdsClient::FlushImpressions() {
  if (!IsConfigured() || !url_loader_factory_ || pending_impressions_.empty()) {
    return;
  }

  // Prend jusqu'à 50 tokens ; reschedule s'il en reste.
  const size_t take =
      std::min(pending_impressions_.size(), kMaxImpressionBatch);
  std::vector<std::string> tokens(
      pending_impressions_.begin(),
      pending_impressions_.begin() + static_cast<ptrdiff_t>(take));
  pending_impressions_.erase(
      pending_impressions_.begin(),
      pending_impressions_.begin() + static_cast<ptrdiff_t>(take));

  base::ListValue token_list;
  for (const std::string& token : tokens) {
    token_list.Append(token);
  }
  base::DictValue payload;
  payload.Set("tokens", std::move(token_list));

  std::string body;
  if (!base::JSONWriter::Write(payload, &body)) {
    return;
  }

  auto request = std::make_unique<network::ResourceRequest>();
  request->url = GURL(base::StrCat({kAdsApiUrl, "/v1/track/impressions"}));
  request->method = "POST";
  request->credentials_mode = network::mojom::CredentialsMode::kOmit;
  request->load_flags = net::LOAD_DO_NOT_SAVE_COOKIES;

  auto loader = network::SimpleURLLoader::Create(std::move(request),
                                                 kTrackTrafficAnnotation);
  loader->AttachStringForUpload(body, "application/json");

  auto* loader_ptr = loader.get();
  loader_ptr->DownloadToString(
      url_loader_factory_.get(),
      base::BindOnce(&AdsClient::OnImpressionFlushComplete,
                     weak_factory_.GetWeakPtr(), std::move(loader),
                     std::move(tokens)),
      /*max_body_size=*/4 * 1024);

  if (!pending_impressions_.empty()) {
    ScheduleImpressionFlush();
  }
}

void AdsClient::OnImpressionFlushComplete(
    std::unique_ptr<network::SimpleURLLoader> loader,
    std::vector<std::string> sent_tokens,
    std::optional<std::string> response_body) {
  const int net_error = loader->NetError();
  const int response_code =
      loader->ResponseInfo() && loader->ResponseInfo()->headers
          ? loader->ResponseInfo()->headers->response_code()
          : 0;

  if (net_error != net::OK || response_code < 200 || response_code >= 300) {
    // Réseau KO → requeue pour retry (idempotent : un token consommé 2× =
    // `duplicates` côté serveur, sans erreur).
    VLOG(1) << "[BrowtherAds] impressions flush failed: net_error=" << net_error
            << " http=" << response_code << " (requeued)";
    pending_impressions_.insert(pending_impressions_.end(),
                                std::make_move_iterator(sent_tokens.begin()),
                                std::make_move_iterator(sent_tokens.end()));
    ScheduleImpressionFlush();
    return;
  }

  VLOG(1) << "[BrowtherAds] impressions flushed (" << sent_tokens.size() << ")";
}

}  // namespace browther_ads
