// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_SAWTUNAA_CORE_SAWTUNAA_FEATURES_H_
#define BRAVE_COMPONENTS_SAWTUNAA_CORE_SAWTUNAA_FEATURES_H_

#include "base/feature_list.h"

namespace sawtunaa {

// Audio tap V2 : rollout kill-switch du traitement NSNet2 natif desktop
// (jumeau de kBasarunaaVideoDecodeAhead). La feature gate la CRÉATION du
// SawtunaaAudioService ; le tap lui-même reste gaté par le switch
// --sawtunaa-audio-tap (dev spike aujourd'hui, injection pref à l'étape 4 —
// cf. private/docs/sawtunaa/AUDIO_TAP_V2.md).
BASE_DECLARE_FEATURE(kSawtunaaNativeAudio);

}  // namespace sawtunaa

#endif  // BRAVE_COMPONENTS_SAWTUNAA_CORE_SAWTUNAA_FEATURES_H_
