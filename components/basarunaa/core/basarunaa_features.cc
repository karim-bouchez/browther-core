// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/basarunaa/core/basarunaa_features.h"

#include "base/command_line.h"
#include "build/build_config.h"

namespace basarunaa {

BASE_FEATURE(kBasarunaaVideoDecodeAhead,
             "BasarunaaVideoDecodeAhead",
             base::FEATURE_ENABLED_BY_DEFAULT);

bool IsBasarunaaDebugUiEnabled() {
#if defined(OFFICIAL_BUILD)
  // Prod : verrouillé sauf si l'utilisateur (Karim) lance explicitement avec
  // --basarunaa-debug-ui. L'utilisateur final n'a jamais le switch → jamais
  // d'overlays/capture.
  return base::CommandLine::ForCurrentProcess()->HasSwitch(
      "basarunaa-debug-ui");
#else
  // Component/dev : toujours disponible (confort de dev).
  return true;
#endif
}

}  // namespace basarunaa
