/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "brave/browser/ui/webui/welcome_page/browther_intro_installed_browsers.h"

namespace browther_intro {

// Ni macOS ni Windows (Linux) : la liste d'import n'est pas filtrée.
std::optional<std::vector<std::string>> GetInstalledBrowsers() {
  return std::nullopt;
}

}  // namespace browther_intro
