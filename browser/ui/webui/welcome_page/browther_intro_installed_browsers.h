/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_BROWSER_UI_WEBUI_WELCOME_PAGE_BROWTHER_INTRO_INSTALLED_BROWSERS_H_
#define BRAVE_BROWSER_UI_WEBUI_WELCOME_PAGE_BROWTHER_INTRO_INSTALLED_BROWSERS_H_

#include <optional>
#include <string>
#include <vector>

namespace browther_intro {

// Les navigateurs dont l'APPLICATION est installée, sous le nom que leur donne
// l'import (`importer_constants.h` : « Google Chrome », « Chromium »…).
//
// ⚠️ La liste d'import de Brave ne regarde que les dossiers de données : un
// `~/Library/Application Support/Chromium` laissé par un outil proposait
// « Chromium » sur un Mac qui ne l'a jamais eu (recette Karim, 2026-09-14).
//
// `std::nullopt` : la plateforme ne sait pas le dire, l'écran ne filtre rien.
std::optional<std::vector<std::string>> GetInstalledBrowsers();

}  // namespace browther_intro

#endif  // BRAVE_BROWSER_UI_WEBUI_WELCOME_PAGE_BROWTHER_INTRO_INSTALLED_BROWSERS_H_
