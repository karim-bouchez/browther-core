// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/browther_analytics/browther_analytics_service.h"

#include <algorithm>
#include <array>
#include <limits>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/strings/stringprintf.h"
#include "base/time/time.h"
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

// Incrémente une pref Integer en saturant à INT_MAX pour éviter le wrap.
// Utilisé pour les compteurs cumulatifs NTP (kStats*Total). Type Integer
// pour rester compatible avec `chrome.settingsPrivate` (cf. extensions MV3
// Sawtunaa/Basarunaa qui lisent/écrivent ces prefs).
void IncrementIntegerPref(PrefService* prefs,
                          const std::string& path,
                          int delta) {
  if (delta <= 0 || !prefs) {
    return;
  }
  const int current = prefs->GetInteger(path);
  constexpr int kCap = std::numeric_limits<int>::max();
  if (current >= kCap - delta) {
    prefs->SetInteger(path, kCap);
    return;
  }
  prefs->SetInteger(path, current + delta);
}

// Jour calendaire dans le fuseau de la personne (`AAAA-MM-JJ`).
std::string LocalDayKey(base::Time time) {
  base::Time::Exploded exploded;
  time.LocalExplode(&exploded);
  return base::StringPrintf("%04d-%02d-%02d", exploded.year, exploded.month,
                            exploded.day_of_month);
}

// Un compteur d'usage de `app_active` tenu en Local State : la pref du total à
// vie, celle de sa mémoire (total parti avec le dernier event remis) et les
// deux propriétés envoyées.
struct AppActiveCounter {
  const char* total_pref;
  const char* sent_pref;
  const char* total_key;
  const char* added_key;
};

constexpr std::array<AppActiveCounter, 3> kAppActiveCounters = {{
    {prefs::kStatsPersonsBlurredTotal, prefs::kAppActiveSentBlurred,
     "blurred_total", "blurred"},
    {prefs::kStatsMusicSecondsTotal, prefs::kAppActiveSentMusicSeconds,
     "music_seconds_total", "music_seconds"},
    {prefs::kStatsPagesTotal, prefs::kAppActiveSentPages, "pages_total",
     "pages"},
}};

// Pose le total et, s'il y a une mémoire, l'ajout depuis le dernier event.
//  - `sent` < 0 : jamais envoyé (premier event après la mise à jour) ⇒ ajout
//    OMIS — envoyer tout l'historique d'un coup fausserait la journée ;
//  - `total` < `sent` : compteur remis à zéro (données effacées) ⇒ l'ajout
//    est le total actuel ;
//  - jamais négatif.
void SetAppActiveCounter(base::DictValue& properties,
                         const char* total_key,
                         const char* added_key,
                         int total,
                         int sent) {
  properties.Set(total_key, total);
  if (sent < 0) {
    return;
  }
  properties.Set(added_key, total >= sent ? total - sent : total);
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

bool BrowtherAnalyticsService::IsAppActiveDue() const {
  return IsPostHogEnabled() &&
         local_state_->GetString(prefs::kAppActiveLastDay) !=
             LocalDayKey(base::Time::Now());
}

bool BrowtherAnalyticsService::TrackAppActive(
    base::DictValue properties,
    std::optional<int> blocked_total,
    PrefService* profile_prefs) {
  if (!IsAppActiveDue()) {
    return false;
  }
  // Les totaux sont lus UNE fois : la valeur envoyée et la valeur mémorisée
  // sont la même, sinon ce qui s'ajoute entre les deux serait perdu.
  std::array<int, kAppActiveCounters.size()> totals;
  for (size_t i = 0; i < kAppActiveCounters.size(); ++i) {
    const AppActiveCounter& counter = kAppActiveCounters[i];
    totals[i] = std::max(0, local_state_->GetInteger(counter.total_pref));
    SetAppActiveCounter(properties, counter.total_key, counter.added_key,
                        totals[i],
                        local_state_->GetInteger(counter.sent_pref));
  }
  const bool has_blocked = blocked_total.has_value() && profile_prefs;
  const int blocked = has_blocked ? std::max(0, *blocked_total) : 0;
  if (has_blocked) {
    SetAppActiveCounter(properties, "blocked_total", "blocked", blocked,
                        profile_prefs->GetInteger(prefs::kAppActiveSentBlocked));
  }

  posthog_client_->Enqueue("app_active", std::move(properties));
  // L'event est remis : le jour ET les mémoires, ensemble. Sans event (retour
  // anticipé ci-dessus), rien n'est noté et l'ajout part avec le prochain.
  local_state_->SetString(prefs::kAppActiveLastDay,
                          LocalDayKey(base::Time::Now()));
  for (size_t i = 0; i < kAppActiveCounters.size(); ++i) {
    local_state_->SetInteger(kAppActiveCounters[i].sent_pref, totals[i]);
  }
  if (has_blocked) {
    profile_prefs->SetInteger(prefs::kAppActiveSentBlocked, blocked);
  }
  return true;
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
  IncrementIntegerPref(local_state_, prefs::kStatsMusicSecondsTotal, delta);
  if (!IsStatsEnabled()) {
    return;
  }
  stats_client_->IncrementMusicSeconds(delta);
}

void BrowtherAnalyticsService::IncrementPersonsBlurred(int delta) {
  // Idem (cf. IncrementMusicSeconds).
  IncrementIntegerPref(local_state_, prefs::kStatsPersonsBlurredTotal, delta);
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

void BrowtherAnalyticsService::IncrementPagesOpened() {
  IncrementIntegerPref(local_state_, prefs::kStatsPagesTotal, 1);
}

void BrowtherAnalyticsService::FlushStatsNow() {
  if (!stats_client_) {
    return;
  }
  stats_client_->FlushNow();
}

}  // namespace browther_analytics
