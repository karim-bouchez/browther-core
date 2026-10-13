// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BROWTHER_ANALYTICS_BROWTHER_ANALYTICS_SERVICE_H_
#define BRAVE_COMPONENTS_BROWTHER_ANALYTICS_BROWTHER_ANALYTICS_SERVICE_H_

#include <memory>
#include <optional>
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
class StatsClient;

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

  // Le consentement est-il actif ? Sert à l'UI qui propose une action DONT LE
  // SEUL EFFET est un Track() : sans ça elle afficherait « signalé, merci »
  // alors que l'appel est un no-op — le genre de mensonge qu'on s'interdit
  // (cf. l'encadré DRM des panels). L'UI grise l'action et l'explique.
  bool IsTrackingEnabled() const { return IsPostHogEnabled(); }

  // `app_active` — « actif aujourd'hui » : au plus un par jour calendaire
  // LOCAL et par installation (pref kAppActiveLastDay). L'appelant demande
  // d'abord IsAppActiveDue() — vrai si l'analytics est active et que le jour
  // n'a pas encore été envoyé — avant de réunir des propriétés coûteuses
  // (navigateur par défaut), puis appelle TrackAppActive(), qui revérifie et
  // ne note le jour que si l'event a réellement été remis au client.
  //
  // TrackAppActive() joint les compteurs d'usage : pour chacun le total à vie
  // (`blurred_total`, `music_seconds_total`, `pages_total`, `blocked_total`,
  // toujours envoyés) et l'ajout depuis le dernier `app_active` remis
  // (`blurred`, `music_seconds`, `pages`, `blocked`), calculé contre une
  // mémoire écrite en même temps que le jour — additionner les events ne
  // compte donc jamais deux fois le même appareil (pref_names.h,
  // `kAppActiveSent*`). Les trois premiers totaux sont en Local State, le
  // service les lit lui-même. Les blocages sont par PROFIL : l'appelant donne
  // leur total et les prefs du profil où vit leur mémoire ; `nullopt` / nul
  // (profil disparu, invité) ⇒ `blocked*` omis et mémoire intacte.
  bool IsAppActiveDue() const;
  bool TrackAppActive(base::DictValue properties,
                      std::optional<int> blocked_total,
                      PrefService* profile_prefs);

  // Stats cumulatives publiées sur browther.devndin.com via /api/stats.
  // No-op si StatsClient non configuré ou consentement désactivé.
  // Callable depuis n'importe quel chemin C++ Browther.
  void IncrementMusicSeconds(int delta);
  void IncrementPersonsBlurred(int delta);
  void IncrementAdsBlocked(int delta);
  void FlushStatsNow();

  // +1 page ouverte (total à vie local, `kStatsPagesTotal`). Pas de gate
  // analytics : rien ne part sur le réseau ici, le total ne voyage que dans
  // `app_active`, qui porte son propre consentement.
  void IncrementPagesOpened();

 private:
  BrowtherAnalyticsService(
      PrefService* local_state,
      scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory);
  ~BrowtherAnalyticsService();

  BrowtherAnalyticsService(const BrowtherAnalyticsService&) = delete;
  BrowtherAnalyticsService& operator=(const BrowtherAnalyticsService&) = delete;

  bool IsPostHogEnabled() const;
  bool IsStatsEnabled() const;
  void OnConsentPrefChanged(const std::string& pref_name);

  raw_ptr<PrefService> local_state_;
  std::unique_ptr<DistinctIdProvider> distinct_id_provider_;
  std::unique_ptr<PostHogClient> posthog_client_;
  std::unique_ptr<StatsClient> stats_client_;
  PrefChangeRegistrar pref_change_registrar_;
};

}  // namespace browther_analytics

#endif  // BRAVE_COMPONENTS_BROWTHER_ANALYTICS_BROWTHER_ANALYTICS_SERVICE_H_
