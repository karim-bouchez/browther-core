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

// Dernier jour LOCAL (`AAAA-MM-JJ`) où `app_active` a été remis au client :
// au plus un par jour et par installation. Écrit seulement après un envoi
// réel (analytics coupée ⇒ rien n'est noté). Desktop ; Android tient le sien
// côté Java (`BrowtherDailyActive`).
inline constexpr char kAppActiveLastDay[] =
    "browther.analytics.app_active_last_day";

// Compteurs d'usage joints à `app_active` : le total À VIE tel qu'il est parti
// avec le dernier `app_active` remis au client. L'ajout envoyé (`blurred`,
// `music_seconds`, `pages`, `blocked`) = total actuel − cette mémoire, pour
// qu'additionner les events dans PostHog ne compte jamais deux fois le même
// appareil. Écrites au même endroit et au même moment que le jour
// (`TrackAppActive`), donc seulement si l'event est remis. -1 (le défaut) =
// jamais envoyé ⇒ l'ajout est OMIS de l'event, ⛔ pas tout l'historique d'un
// coup. Desktop ; Android et iOS tiennent les leurs.
inline constexpr char kAppActiveSentBlurred[] =
    "browther.analytics.app_active_sent.blurred";
inline constexpr char kAppActiveSentMusicSeconds[] =
    "browther.analytics.app_active_sent.music_seconds";
inline constexpr char kAppActiveSentPages[] =
    "browther.analytics.app_active_sent.pages";
// ⚠️ Celle-ci est une pref de PROFIL, pas de Local State : le total qu'elle
// mémorise (`kAdsBlocked` + `kTrackersBlocked`) est lui-même par profil. Une
// mémoire par installation, comparée tour à tour aux totaux de deux profils,
// renverrait l'historique entier de l'un à chaque changement de fenêtre.
inline constexpr char kAppActiveSentBlocked[] =
    "browther.analytics.app_active_sent.blocked";

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

// Pages ouvertes, total à vie de l'installation (Local State) : un nombre,
// ⛔ aucune adresse, aucun domaine. Incrémenté à côté du compteur du jour du
// parrainage (`browther_referral::RecordRealPageLoad`), donc la même unité :
// une page http(s) qui a fini de charger dans le cadre principal, hors
// navigation privée. Ne part que dans `app_active` (`pages_total`, `pages`) ;
// pas affiché, pas envoyé à /api/stats/ingest. Desktop seulement.
inline constexpr char kStatsPagesTotal[] = "browther.stats.pages_total";

}  // namespace browther_analytics::prefs

#endif  // BRAVE_COMPONENTS_BROWTHER_ANALYTICS_PREF_NAMES_H_
