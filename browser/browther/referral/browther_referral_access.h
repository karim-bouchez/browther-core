// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_ACCESS_H_
#define BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_ACCESS_H_

#include "base/values.h"

class PrefService;

// La garde native de la SEULE fonctionnalité supplémentaire de Browther : le
// retrait de la musique (Sawtunaa) — `private/docs/PARRAINAGE.md` § 3. ⛔
// Basarunaa (le floutage) ne se met JAMAIS en pause (§ 9).
//
// Les règles vivent dans l'app web (`core/access.ts`) ; elle dépose ici ce
// qu'elle a lu du dernier statut, et le navigateur n'en fait qu'une chose :
// la couverture est-elle tombée MAINTENANT ? (⚠️ recalculé à l'horloge locale :
// une couverture qui tombe pendant que Browther est ouvert doit se voir.)
//
// 🔴 Sens de la panne : OUVERT. Statut jamais reçu, avant l'annonce, à vie,
// abonné, parrainage éteint dans ce binaire, ou annonce dormante
// (`kExtrasReleased`) ⇒ rien n'est en pause (`PARRAINAGE.md` § 4, § 11.2).
namespace browther_referral {

bool IsMusicRemovalPaused(PrefService* local_state);

// Ce que l'app web a lu : `{known, lifetime, beforeTrial, unlocked, untilMs,
// subscriptionActive}`.
void SetAccessSnapshot(PrefService* local_state, base::DictValue snapshot);

}  // namespace browther_referral

#endif  // BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_ACCESS_H_
