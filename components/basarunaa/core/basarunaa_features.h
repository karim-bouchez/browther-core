// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_FEATURES_H_
#define BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_FEATURES_H_

#include "base/feature_list.h"

namespace basarunaa {

// [Browther/Basarunaa] Gate de rollout du pipeline vidéo decode-ahead (tap
// natif + décodage SW forcé + eager-load des modèles ML au démarrage du
// profil). OFF par défaut : la pref kBasarunaaEnabled est ON (flou images), or
// forcer le SW decode + charger 6 modèles ONNX pour TOUS les users tant que le
// pipeline vidéo est expérimental serait une régression perf. Dev :
// --enable-features=BasarunaaVideoDecodeAhead. Quand mûr : passer ON (ou Finch).
//
// Extrait de brave_content_browser_client.cc (où il était en anon-namespace)
// pour être visible par la factory (eager-create + warmup) et le RFO.
BASE_DECLARE_FEATURE(kBasarunaaVideoDecodeAhead);

}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_FEATURES_H_
