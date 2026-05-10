// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/browther_analytics/stats_client.h"

#include <algorithm>
#include <limits>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/json/json_writer.h"
#include "base/logging.h"
#include "base/time/time.h"
#include "base/values.h"
#include "brave/components/browther_analytics/analytics_config.h"
#include "brave/components/browther_analytics/pref_names.h"
#include "components/prefs/pref_registry_simple.h"
#include "components/prefs/pref_service.h"
#include "net/base/load_flags.h"
#include "net/http/http_response_headers.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/shared_url_loader_factory.h"
#include "services/network/public/cpp/simple_url_loader.h"
#include "services/network/public/mojom/url_response_head.mojom.h"
#include "url/gurl.h"

namespace browther_analytics {

namespace {

// 60 s : compromis entre fraîcheur et bruit réseau. À cet intervalle, la
// fenêtre de perte (compteur en mémoire jamais flushé) est ≤ 60 s par
// session ; allonger à plusieurs minutes voudrait dire perdre les sessions
// courtes. Si le bruit devient un problème, augmenter à 120-300 s plutôt
// que 30 min.
constexpr base::TimeDelta kFlushInterval = base::Seconds(60);

constexpr net::NetworkTrafficAnnotationTag kTrafficAnnotation =
    net::DefineNetworkTrafficAnnotation("browther_stats_ingest", R"ANNOT(
        semantics {
          sender: "Browther Stats"
          description:
            "Sends anonymous cumulative counters (seconds of music removed, "
            "people blurred, ads blocked) to the Browther backend, used to "
            "display public 'since launch' metrics on browther.devndin.com. "
            "No URLs visited, no page content, no PII."
          trigger:
            "Periodic flush every 60 seconds when counters are non-zero, plus "
            "an opportunistic flush at browser shutdown."
          data:
            "Anonymous UUID (random v4), platform name, and three integer "
            "deltas since the previous flush."
          destination: OTHER
          destination_other: "browther-api.devndin.com (self-hosted on OVH)"
        }
        policy {
          cookies_allowed: NO
          setting:
            "Users can disable in Settings > Privacy > Send anonymous "
            "product insights, or during the welcome onboarding flow."
          policy_exception_justification:
            "Not implemented, consumer-facing browser."
        })ANNOT");

}  // namespace

StatsClient::StatsClient(
    scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory,
    PrefService* local_state,
    std::string anon_uuid)
    : url_loader_factory_(std::move(url_loader_factory)),
      local_state_(local_state),
      anon_uuid_(std::move(anon_uuid)) {
  CHECK(local_state_);
  if (IsConfigured()) {
    flush_timer_.Start(
        FROM_HERE, kFlushInterval,
        base::BindRepeating(&StatsClient::FlushNow, base::Unretained(this)));
  }
}

StatsClient::~StatsClient() = default;

// static
bool StatsClient::IsConfigured() {
  std::string_view url(kBrowtherApiUrl);
  return !url.empty();
}

// static
void StatsClient::RegisterLocalStatePrefs(PrefRegistrySimple* registry) {
  registry->RegisterIntegerPref(prefs::kStatsMusicSecondsPending, 0);
  registry->RegisterIntegerPref(prefs::kStatsPersonsBlurredPending, 0);
  registry->RegisterIntegerPref(prefs::kStatsAdsBlockedPending, 0);
  registry->RegisterIntegerPref(prefs::kStatsAdsBlockedLastSeen, 0);
}

void StatsClient::IncrementPref(const char* pref_name, int delta) {
  if (delta <= 0) {
    return;
  }
  const int current = local_state_->GetInteger(pref_name);
  // Saturate at INT_MAX/2 to keep room before overflow on flush serialization.
  constexpr int kCap = std::numeric_limits<int>::max() / 2;
  if (current >= kCap) {
    return;
  }
  local_state_->SetInteger(pref_name, std::min(kCap, current + delta));
}

void StatsClient::IncrementMusicSeconds(int delta) {
  IncrementPref(prefs::kStatsMusicSecondsPending, delta);
}

void StatsClient::IncrementPersonsBlurred(int delta) {
  IncrementPref(prefs::kStatsPersonsBlurredPending, delta);
}

void StatsClient::IncrementAdsBlocked(int delta) {
  IncrementPref(prefs::kStatsAdsBlockedPending, delta);
}

void StatsClient::FlushNow() {
  if (!IsConfigured() || flush_in_flight_) {
    return;
  }

  const int music = local_state_->GetInteger(prefs::kStatsMusicSecondsPending);
  const int persons =
      local_state_->GetInteger(prefs::kStatsPersonsBlurredPending);
  const int ads = local_state_->GetInteger(prefs::kStatsAdsBlockedPending);

  if (music == 0 && persons == 0 && ads == 0) {
    return;
  }

  base::DictValue payload;
  payload.Set("anonUuid", anon_uuid_);
  payload.Set("platform", "desktop");
  payload.Set("musicSecondsDelta", music);
  payload.Set("personsBlurredDelta", persons);
  payload.Set("adsBlockedDelta", ads);

  std::string body;
  if (!base::JSONWriter::Write(payload, &body)) {
    LOG(WARNING) << "[BrowtherStats] failed to serialize ingest payload";
    return;
  }

  auto request = std::make_unique<network::ResourceRequest>();
  request->url = GURL(std::string(kBrowtherApiUrl) + "/api/stats/ingest");
  request->method = "POST";
  request->credentials_mode = network::mojom::CredentialsMode::kOmit;
  request->load_flags = net::LOAD_DO_NOT_SAVE_COOKIES;

  auto loader =
      network::SimpleURLLoader::Create(std::move(request), kTrafficAnnotation);
  loader->AttachStringForUpload(body, "application/json");

  flush_in_flight_ = true;
  auto* loader_ptr = loader.get();
  loader_ptr->DownloadToString(
      url_loader_factory_.get(),
      base::BindOnce(&StatsClient::OnFlushComplete, weak_factory_.GetWeakPtr(),
                     std::move(loader), music, persons, ads),
      /*max_body_size=*/4 * 1024);
}

void StatsClient::OnFlushComplete(
    std::unique_ptr<network::SimpleURLLoader> loader,
    int sent_music,
    int sent_persons,
    int sent_ads,
    std::optional<std::string> response_body) {
  flush_in_flight_ = false;
  const int net_error = loader->NetError();
  const int response_code =
      loader->ResponseInfo() && loader->ResponseInfo()->headers
          ? loader->ResponseInfo()->headers->response_code()
          : 0;

  if (net_error != net::OK || response_code < 200 || response_code >= 300) {
    LOG(WARNING) << "[BrowtherStats] ingest failed: net_error=" << net_error
                 << " http=" << response_code
                 << " (counters preserved for retry)";
    return;
  }

  // Soustraire ce qu'on vient d'envoyer plutôt que de remettre à 0 — entre la
  // capture des valeurs (FlushNow) et ce callback, des Increment ont pu
  // arriver et les pref auraient grossi : reset = perte de données.
  auto subtract = [this](const char* pref, int sent) {
    if (sent <= 0) {
      return;
    }
    const int current = local_state_->GetInteger(pref);
    local_state_->SetInteger(pref, std::max(0, current - sent));
  };
  subtract(prefs::kStatsMusicSecondsPending, sent_music);
  subtract(prefs::kStatsPersonsBlurredPending, sent_persons);
  subtract(prefs::kStatsAdsBlockedPending, sent_ads);

  VLOG(1) << "[BrowtherStats] ingest OK (music=" << sent_music
          << " persons=" << sent_persons << " ads=" << sent_ads << ")";
}

}  // namespace browther_analytics
