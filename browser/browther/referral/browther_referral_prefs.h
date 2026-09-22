// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_PREFS_H_
#define BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_PREFS_H_

class PrefRegistrySimple;

// Tout vit dans le LOCAL STATE, pas dans le profil : le parrainage suit
// l'APPAREIL (§ 7.1) — deux profils du même Browther sont le même sujet, sinon
// la garde « même appareil » du service tomberait d'elle-même. Et une annonce se
// voit une fois par installation (§ 12.11).
namespace browther_referral::prefs {

// L'identité d'appareil : un UUID tiré au premier besoin. ⚠️ Ce n'est PAS
// `browther.analytics.distinct_id` (analytique) : un sujet qui changerait
// perdrait ses mois et son code. Le service n'en stocke qu'un hachage.
inline constexpr char kDeviceId[] = "browther.referral.device_id";

// Ce que l'app web du parrainage retient entre deux affichages (JSON opaque par
// clé : état de sollicitation, dernier statut connu, démo de la jauge,
// paiement en attente…). ⛔ Le C++ n'y lit rien : les règles vivent dans l'app
// (`private/webui/referral/src/core/`).
inline constexpr char kStore[] = "browther.referral.store";

// Les faits d'usage, écrits par le navigateur (le seul à les voir) :
// jour local courant, pages chargées aujourd'hui, repère des secondes de
// musique retirée en début de journée, jours de navigation, jours où le défaut
// a été PROUVÉ (`shell_integration`).
inline constexpr char kUsage[] = "browther.referral.usage";

// Ce que l'app a déduit du dernier statut, pour les gardes natives (Sawtunaa) :
// `{known, lifetime, beforeTrial, unlocked, until, subscriptionActive}`.
inline constexpr char kAccess[] = "browther.referral.access";

// Le verrou du jour (§ 3.4) : `{day, owner}` — une seule sollicitation par jour,
// même avec deux fenêtres ouvertes sur deux Nouveaux Onglets.
inline constexpr char kDayLock[] = "browther.referral.day_lock";

// Le compte dev&din facultatif (§ 7.1) : `{userId, email, name, token}` — le
// jeton de session est CHIFFRÉ (OSCrypt) et ⛔ ne sort jamais vers le
// JavaScript.
inline constexpr char kAccount[] = "browther.referral.account";

void RegisterLocalStatePrefs(PrefRegistrySimple* registry);

}  // namespace browther_referral::prefs

#endif  // BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_PREFS_H_
