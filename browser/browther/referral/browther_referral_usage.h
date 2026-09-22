// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_USAGE_H_
#define BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_USAGE_H_

#include <optional>
#include <string>

#include "base/functional/callback_forward.h"
#include "base/time/time.h"
#include "base/values.h"

class PrefService;

// Les faits d'usage du parrainage — seul le navigateur les voit, l'app web les
// lit (`browther.referral.usage`).
//
// ## Deux faits, un même jour local (`PARRAINAGE.md` § 9, ligne Browther)
//
// La validation du filleul = **3 journées distinctes où Browther, navigateur par
// défaut, a chargé une vraie page**. Un jour compte donc quand tombent LE MÊME
// JOUR LOCAL :
//  - une **vraie page chargée** (cadre principal, `http(s)`, profil normal — la
//    même unité que l'iOS et que les surfaces communes) ;
//  - une **preuve du défaut** : `shell_integration::GetDefaultBrowser()` a
//    répondu `IS_DEFAULT` ce jour-là. ⭐ Sur desktop la réponse est EXACTE
//    (§ 9 : « macOS · Windows : exact »), contrairement à l'iOS où l'API est
//    rationnée — ⛔ jamais un « probablement ».
//
// Le même registre sert au moment de mérite (§ 3.1, « au N-ième onglet du
// jour » : N vraies pages aujourd'hui) et à la musique retirée aujourd'hui (le
// cumul `browther.stats.music_seconds_total` moins son repère de début de
// journée : il n'existe qu'un cumul).
namespace browther_referral {

// Le jour LOCAL (`YYYY-MM-DD`) — ⚠️ pas l'UTC : « une fois par jour » se vit
// dans le fuseau de la personne.
std::string LocalDayKey(base::Time time);

// Une vraie page a fini de charger : +1 page aujourd'hui, jour de navigation
// noté. Déclenche au besoin la vérification du défaut (au plus toutes les
// 30 min tant que le jour n'est pas prouvé).
void RecordRealPageLoad(PrefService* local_state);

// Interroge l'OS (fil bloquant) : Browther est-il le navigateur par défaut ?
// Si oui, la preuve du jour est notée. `done` reçoit la réponse (`nullopt` =
// inconnue). Appelé aussi juste après « Régler par défaut ».
void CheckDefaultBrowser(PrefService* local_state,
                         base::OnceCallback<void(std::optional<bool>)> done);

// 🧪 Recette : un build de dev qu'on ne met pas par défaut (le Browther
// quotidien l'est) doit pouvoir poser la preuve du jour (§ 12.29).
void RecordDefaultProofForTesting(PrefService* local_state);
void SetPagesTodayForTesting(PrefService* local_state, int pages);
void ResetUsageForTesting(PrefService* local_state);

// La photo que lit l'app web : `{day, pagesToday, musicSecondsToday,
// browsingDays[], proofDays[], isDefault?}`.
base::DictValue UsageSnapshot(PrefService* local_state);

}  // namespace browther_referral

#endif  // BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_USAGE_H_
