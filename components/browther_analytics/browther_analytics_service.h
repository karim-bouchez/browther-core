// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BROWTHER_ANALYTICS_BROWTHER_ANALYTICS_SERVICE_H_
#define BRAVE_COMPONENTS_BROWTHER_ANALYTICS_BROWTHER_ANALYTICS_SERVICE_H_

#include <memory>
#include <string>

#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/values.h"
#include "components/prefs/pref_change_registrar.h"

class PrefService;

namespace network {
class SharedURLLoaderFactory;
}

namespace browther_analytics {

class DistinctIdProvider;
class PostHogClient;

// Singleton browser-wide qui orchestre Sentry (via Crashpad URL override) et
// PostHog (custom events).
//
// Init dans BraveBrowserMainExtraParts::PreMainMessageLoopRun().
// Lit le consentement depuis local_state (kP3AEnabled pour PostHog,
// kMetricsReportingEnabled pour Sentry — aligné avec l'onboarding desktop).
class BrowtherAnalyticsService {
 public:
  static BrowtherAnalyticsService* GetInstance();
  static void Initialize(
      PrefService* local_state,
      scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory);

  // Track un event. No-op si PostHog désactivé ou non configuré.
  void Track(const std::string& event_name, base::DictValue properties);
  void Track(const std::string& event_name);

 private:
  BrowtherAnalyticsService(
      PrefService* local_state,
      scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory);
  ~BrowtherAnalyticsService();

  BrowtherAnalyticsService(const BrowtherAnalyticsService&) = delete;
  BrowtherAnalyticsService& operator=(const BrowtherAnalyticsService&) = delete;

  bool IsPostHogEnabled() const;
  void OnConsentPrefChanged(const std::string& pref_name);

  raw_ptr<PrefService> local_state_;
  std::unique_ptr<DistinctIdProvider> distinct_id_provider_;
  std::unique_ptr<PostHogClient> posthog_client_;
  PrefChangeRegistrar pref_change_registrar_;
};

}  // namespace browther_analytics

#endif  // BRAVE_COMPONENTS_BROWTHER_ANALYTICS_BROWTHER_ANALYTICS_SERVICE_H_
