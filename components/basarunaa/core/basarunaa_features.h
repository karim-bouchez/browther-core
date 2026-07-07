// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_FEATURES_H_
#define BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_FEATURES_H_

#include "base/feature_list.h"

namespace basarunaa {

// [Browther/Basarunaa] Gate du pipeline vidéo decode-ahead (tap natif +
// analyse ML + overlay). ON PAR DÉFAUT depuis 2026-07-07 (décision Karim :
// ship le flou vidéo ; un user qui n'en veut pas désactive l'extension). Le
// coût (tap + latency-hint 2 s + warmup des modèles) est protégé par la pref
// kBasarunaaEnabled : rien n'est injecté/chargé si l'extension est OFF (cf.
// brave_content_browser_client.cc gate pref, basarunaa_service_factory warmup
// gate). Donc feature ON = « disponible » ; pref = « utilisé ».
// Pour désactiver globalement en debug : --disable-features=BasarunaaVideoDecodeAhead.
//
// Extrait de brave_content_browser_client.cc (où il était en anon-namespace)
// pour être visible par la factory (eager-create + warmup) et le RFO.
BASE_DECLARE_FEATURE(kBasarunaaVideoDecodeAhead);

// [Browther/Basarunaa] L'outillage de debug (overlays boxes/debug, capture des
// analyses vers ~/Downloads, toggle "floutage actif") ne doit JAMAIS être
// exposé ni actif pour l'utilisateur final. Débloqué si :
//   - build NON-officiel (Component dev) : toujours dispo, ou
//   - switch --basarunaa-debug-ui présent (permet de tester sur le DMG prod).
// Gate à DEUX niveaux : (1) l'UI (section Debug du panel) n'apparaît que si
// true ; (2) le RENDU (basarunaa_image_analyzer) force debug_mode="none" /
// capture=false / blur_enabled=true quand false — sinon un pref stocké
// (« boxes » resté d'un test) fuirait chez l'utilisateur final.
bool IsBasarunaaDebugUiEnabled();

}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_FEATURES_H_
