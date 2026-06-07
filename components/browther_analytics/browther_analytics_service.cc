// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/browther_analytics/browther_analytics_service.h"

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "brave/components/browther_analytics/distinct_id_provider.h"
#include "brave/components/browther_analytics/posthog_client.h"
#include "brave/components/browther_analytics/pref_names.h"
#include "brave/components/browther_analytics/stats_client.h"
#include "brave/components/p3a/pref_names.h"
#include "components/metrics/metrics_pref_names.h"
#include "components/prefs/pref_service.h"
#include "services/network/public/cpp/shared_url_loader_factory.h"

namespace browther_analytics {

namespace {

BrowtherAnalyticsService* g_instance = nullptr;

// Incrémente une pref Uint64 en saturant à uint64_max pour éviter le wrap.
// Utilisé pour les compteurs cumulatifs NTP (kStats*Total).
void IncrementUint64Pref(PrefService* prefs,
                         const std::string& path,
                         int delta) {
  if (delta <= 0 || !prefs) {
    return;
  }
  const uint64_t current = prefs->GetUint64(path);
  const uint64_t increment = static_cast<uint64_t>(delta);
  prefs->SetUint64(path, current > UINT64_MAX - increment
                             ? UINT64_MAX
                             : current + increment);
}

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
  const std::string distinct_id = distinct_id_provider_->GetOrCreate();
  if (PostHogClient::IsConfigured()) {
    posthog_client_ =
        std::make_unique<PostHogClient>(url_loader_factory, distinct_id);
  }
  if (StatsClient::IsConfigured()) {
    stats_client_ = std::make_unique<StatsClient>(
        std::move(url_loader_factory), local_state_, distinct_id);
  }

  // Observe les prefs de consentement pour tracker consent_changed.
  // Note : si l'user vient de désactiver PostHog (kP3AEnabled false), le track
  // est déjà no-op (IsPostHogEnabled vérifie la valeur courante). Donc on émet
  // au max un dernier "consent_changed → posthog=true" quand l'user enable, et
  // les transitions vers false sont swallowed (par design — respect du choix).
  pref_change_registrar_.Init(local_state_);
  pref_change_registrar_.Add(
      p3a::kP3AEnabled,
      base::BindRepeating(&BrowtherAnalyticsService::OnConsentPrefChanged,
                          base::Unretained(this), "posthog"));
  pref_change_registrar_.Add(
      metrics::prefs::kMetricsReportingEnabled,
      base::BindRepeating(&BrowtherAnalyticsService::OnConsentPrefChanged,
                          base::Unretained(this), "sentry"));
}

void BrowtherAnalyticsService::OnConsentPrefChanged(
    const std::string& consent_name) {
  bool new_value = false;
  if (consent_name == "posthog") {
    new_value = local_state_->GetBoolean(p3a::kP3AEnabled);
  } else if (consent_name == "sentry") {
    new_value = local_state_->GetBoolean(metrics::prefs::kMetricsReportingEnabled);
  }
  base::DictValue props;
  props.Set("consent", consent_name);
  props.Set("enabled", new_value);
  Track("consent_changed", std::move(props));
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

bool BrowtherAnalyticsService::IsStatsEnabled() const {
  if (!stats_client_ || !local_state_) {
    return false;
  }
  // Même gate que PostHog : si l'user a refusé "product insights" pendant
  // l'onboarding, on n'envoie rien.
  return local_state_->GetBoolean(p3a::kP3AEnabled);
}

void BrowtherAnalyticsService::IncrementMusicSeconds(int delta) {
  // Compteur cumulatif local pour la NTP : pas de gate analytics, c'est une
  // stat utilisateur visible localement et n'envoie rien sur le réseau.
  IncrementUint64Pref(local_state_, prefs::kStatsMusicSecondsTotal, delta);
  if (!IsStatsEnabled()) {
    return;
  }
  stats_client_->IncrementMusicSeconds(delta);
}

void BrowtherAnalyticsService::IncrementPersonsBlurred(int delta) {
  // Idem (cf. IncrementMusicSeconds).
  IncrementUint64Pref(local_state_, prefs::kStatsPersonsBlurredTotal, delta);
  if (!IsStatsEnabled()) {
    return;
  }
  stats_client_->IncrementPersonsBlurred(delta);
}

void BrowtherAnalyticsService::IncrementAdsBlocked(int delta) {
  if (!IsStatsEnabled()) {
    return;
  }
  stats_client_->IncrementAdsBlocked(delta);
}

void BrowtherAnalyticsService::FlushStatsNow() {
  if (!stats_client_) {
    return;
  }
  stats_client_->FlushNow();
}

}  // namespace browther_analytics
