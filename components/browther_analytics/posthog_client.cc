// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/browther_analytics/posthog_client.h"

#include <algorithm>
#include <utility>

#include "base/functional/bind.h"
#include "base/json/json_writer.h"
#include "base/logging.h"
#include "base/strings/stringprintf.h"
#include "base/time/time.h"
#include "brave/components/browther_analytics/analytics_config.h"
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

constexpr base::TimeDelta kFlushInterval = base::Seconds(30);

constexpr net::NetworkTrafficAnnotationTag kTrafficAnnotation =
    net::DefineNetworkTrafficAnnotation("browther_posthog_analytics", R"ANNOT(
        semantics {
          sender: "Browther Analytics"
          description:
            "Sends anonymous product analytics events to PostHog (EU region) "
            "for feature usage and retention metrics. No URLs visited, no "
            "page content, no PII. Toggle controlled by the kP3AEnabled "
            "preference (set during onboarding)."
          trigger:
            "App launch, feature toggles, NTP load, onboarding completion."
          data:
            "Anonymous UUID, app version, OS, locale, event name and a small "
            "set of non-PII properties."
          destination: OTHER
          destination_other: "PostHog Cloud, EU region (Frankfurt)"
        }
        policy {
          cookies_allowed: NO
          setting:
            "Users can disable in Settings > Privacy > Send anonymous "
            "product insights, or during the welcome onboarding flow."
          policy_exception_justification:
            "Not implemented, consumer-facing browser."
        })ANNOT");

std::string IsoNowUtc() {
  base::Time::Exploded e;
  base::Time::Now().UTCExplode(&e);
  return base::StringPrintf(
      "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
      e.year, e.month, e.day_of_month, e.hour, e.minute, e.second,
      e.millisecond);
}

}  // namespace

PostHogClient::PostHogClient(
    scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory,
    std::string distinct_id)
    : url_loader_factory_(std::move(url_loader_factory)),
      distinct_id_(std::move(distinct_id)) {
  if (IsConfigured()) {
    flush_timer_.Start(FROM_HERE, kFlushInterval,
                       base::BindRepeating(&PostHogClient::Flush,
                                           base::Unretained(this)));
  }
}

PostHogClient::~PostHogClient() = default;

// static
bool PostHogClient::IsConfigured() {
  std::string_view key(kPostHogApiKey);
  std::string_view endpoint(kPostHogEndpoint);
  return !key.empty() && !endpoint.empty();
}

void PostHogClient::Enqueue(const std::string& event_name,
                            base::DictValue properties) {
  if (!IsConfigured()) {
    return;
  }

  base::DictValue event;
  event.Set("event", event_name);
  event.Set("distinct_id", distinct_id_);
  event.Set("timestamp", IsoNowUtc());

  // PostHog conventions : $lib helps identify our SDK in dashboards.
  properties.Set("$lib", "browther-native");
  properties.Set("$lib_version", "1.0.0");
  event.Set("properties", std::move(properties));

  buffer_.push_back(std::move(event));

  if (buffer_.size() >= kMaxBufferSize) {
    Flush();
  }
}

void PostHogClient::Flush() {
  if (!IsConfigured() || buffer_.empty()) {
    return;
  }

  base::ListValue batch;
  for (auto& evt : buffer_) {
    batch.Append(std::move(evt));
  }
  buffer_.clear();

  base::DictValue payload;
  payload.Set("api_key", kPostHogApiKey);
  payload.Set("batch", std::move(batch));

  std::string body;
  if (!base::JSONWriter::Write(payload, &body)) {
    LOG(WARNING) << "[BrowtherAnalytics] failed to serialize batch";
    return;
  }

  auto request = std::make_unique<network::ResourceRequest>();
  request->url = GURL(std::string(kPostHogEndpoint) + "/batch/");
  request->method = "POST";
  request->credentials_mode = network::mojom::CredentialsMode::kOmit;
  request->load_flags = net::LOAD_DO_NOT_SAVE_COOKIES;

  auto loader = network::SimpleURLLoader::Create(std::move(request),
                                                 kTrafficAnnotation);
  loader->AttachStringForUpload(body, "application/json");

  auto* loader_ptr = loader.get();
  loader_ptr->DownloadToString(
      url_loader_factory_.get(),
      base::BindOnce(&PostHogClient::OnFlushComplete, base::Unretained(this),
                     std::move(loader)),
      /*max_body_size=*/64 * 1024);
}

void PostHogClient::OnFlushComplete(
    std::unique_ptr<network::SimpleURLLoader> loader,
    std::optional<std::string> response_body) {
  int net_error = loader->NetError();
  int response_code = loader->ResponseInfo() && loader->ResponseInfo()->headers
                          ? loader->ResponseInfo()->headers->response_code()
                          : 0;
  if (net_error != net::OK || response_code < 200 || response_code >= 300) {
    LOG(WARNING) << "[BrowtherAnalytics] PostHog flush failed: net_error="
                 << net_error << " http=" << response_code;
  } else {
    VLOG(1) << "[BrowtherAnalytics] PostHog batch sent (http " << response_code
            << ")";
  }
  // loader auto-destroyed at end of scope.
}

}  // namespace browther_analytics
