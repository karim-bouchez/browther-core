// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/browther_analytics/browther_analytics_service.h"

#include "base/check.h"
#include "base/no_destructor.h"
#include "brave/components/browther_analytics/distinct_id_provider.h"
#include "brave/components/browther_analytics/posthog_client.h"
#include "brave/components/p3a/pref_names.h"
#include "components/prefs/pref_service.h"
#include "services/network/public/cpp/shared_url_loader_factory.h"

namespace browther_analytics {

namespace {

BrowtherAnalyticsService* g_instance = nullptr;

}  // namespace

// static
BrowtherAnalyticsService* BrowtherAnalyticsService::GetInstance() {
  return g_instance;
}

// static
void BrowtherAnalyticsService::Initialize(
    PrefService* local_state,
    scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory) {
  CHECK(!g_instance) << "BrowtherAnalyticsService already initialized";
  g_instance = new BrowtherAnalyticsService(local_state,
                                            std::move(url_loader_factory));
}

BrowtherAnalyticsService::BrowtherAnalyticsService(
    PrefService* local_state,
    scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory)
    : local_state_(local_state),
      distinct_id_provider_(std::make_unique<DistinctIdProvider>(local_state)) {
  if (PostHogClient::IsConfigured()) {
    posthog_client_ = std::make_unique<PostHogClient>(
        std::move(url_loader_factory), distinct_id_provider_->GetOrCreate());
  }
}

BrowtherAnalyticsService::~BrowtherAnalyticsService() = default;

bool BrowtherAnalyticsService::IsPostHogEnabled() const {
  if (!posthog_client_ || !local_state_) {
    return false;
  }
  // Aligné avec l'onboarding desktop : kP3AEnabled est le toggle PostHog.
  return local_state_->GetBoolean(p3a::kP3AEnabled);
}

void BrowtherAnalyticsService::Track(const std::string& event_name,
                                     base::DictValue properties) {
  if (!IsPostHogEnabled()) {
    return;
  }
  posthog_client_->Enqueue(event_name, std::move(properties));
}

void BrowtherAnalyticsService::Track(const std::string& event_name) {
  Track(event_name, base::DictValue());
}

}  // namespace browther_analytics
