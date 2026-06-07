// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BROWTHER_ANALYTICS_PREF_NAMES_H_
#define BRAVE_COMPONENTS_BROWTHER_ANALYTICS_PREF_NAMES_H_

namespace browther_analytics::prefs {

// UUID v4 anonyme local persistant. Stocké dans local_state.
// Régénéré à chaque réinstall (par design — pas de tracking cross-install).
inline constexpr char kBrowtherDistinctId[] = "browther.analytics.distinct_id";

// True quand l'event onboarding_completed a déjà été envoyé pour ce profil.
// Évite les doublons si l'user retourne sur browther://welcome.
inline constexpr char kOnboardingEventSent[] =
    "browther.analytics.onboarding_event_sent";

// Compteurs en attente d'envoi vers /api/stats/ingest. Persistés pour
// survivre aux relances browser (un crash ne perd pas les secondes
// accumulées). Reset à 0 après un flush HTTP réussi.
inline constexpr char kStatsMusicSecondsPending[] =
    "browther.analytics.stats.music_seconds_pending";
inline constexpr char kStatsPersonsBlurredPending[] =
    "browther.analytics.stats.persons_blurred_pending";
inline constexpr char kStatsAdsBlockedPending[] =
    "browther.analytics.stats.ads_blocked_pending";

// Curseur pour future stratégie de polling Shields (delta vs compteur upstream
// `kAdsBlocked` profile). Réservé — actuellement Shields call directement
// `IncrementAdsBlocked(1)` à chaque blocage côté observer.
inline constexpr char kStatsAdsBlockedLastSeen[] =
    "browther.analytics.stats.ads_blocked_last_seen";

// Compteurs cumulatifs locaux affichés sur la NTP ("musique retirée" et
// "personnes floutées"). Jamais reset, indépendants du consentement analytics
// (c'est une stat utilisateur, pas un envoi backend). Incrémentés en parallèle
// des compteurs `_pending` à chaque appel à `IncrementMusicSeconds` /
// `IncrementPersonsBlurred`.
inline constexpr char kStatsMusicSecondsTotal[] =
    "browther.stats.music_seconds_total";
inline constexpr char kStatsPersonsBlurredTotal[] =
    "browther.stats.persons_blurred_total";

}  // namespace browther_analytics::prefs

#endif  // BRAVE_COMPONENTS_BROWTHER_ANALYTICS_PREF_NAMES_H_
