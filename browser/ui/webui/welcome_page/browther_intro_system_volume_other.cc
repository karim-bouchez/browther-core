/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "brave/browser/ui/webui/welcome_page/browther_intro_system_volume.h"

// Ni macOS ni Windows (Linux) : l'écran Musique masque la jauge du son de
// l'ordinateur (cf. ONBOARDING-SPEC.md § 11.2).
namespace browther_intro {

std::optional<SystemVolume> GetSystemVolume() {
  return std::nullopt;
}

void SetSystemVolume(double level) {}

}  // namespace browther_intro
