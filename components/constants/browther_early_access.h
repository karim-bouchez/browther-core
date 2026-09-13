/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_COMPONENTS_CONSTANTS_BROWTHER_EARLY_ACCESS_H_
#define BRAVE_COMPONENTS_CONSTANTS_BROWTHER_EARLY_ACCESS_H_

// Accès anticipé de Basarunaa et Sawtunaa : UN interrupteur pour le desktop.
//
// Vrai tant que les deux moteurs sont livrés éteints par défaut :
// - le badge de la barre d'outils passe à l'ambre dès qu'ils sont allumés
//   (`basarunaa_action_view.cc`, `sawtunaa_action_view.cc`) ;
// - dans l'introduction (`brave_welcome_ui`), « Continuer » sur Basarunaa et
//   Sawtunaa ouvre la feuille « Ça arrive bientôt » au lieu d'allumer le
//   moteur.
//
// ⚠️ Doit basculer EN MÊME TEMPS que `BrowtherEarlyAccess.isActive` (iOS),
// `BrowtherEarlyAccess.ENABLED` (Android) et l'encadré des panels WebUI
// (`setUIEarlyAccess` dans `basarunaa_panel.ts` / `sawtunaa_panel.ts`).
// Cf. `private/docs/ONBOARDING-SPEC.md` § 1.
inline constexpr bool kBrowtherEarlyAccess = true;

#endif  // BRAVE_COMPONENTS_CONSTANTS_BROWTHER_EARLY_ACCESS_H_
