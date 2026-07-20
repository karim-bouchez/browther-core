 /* Copyright (c) 2019 The Brave Authors. All rights reserved.
  * This Source Code Form is subject to the terms of the Mozilla Public
  * License, v. 2.0. If a copy of the MPL was not distributed with this file,
  * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "base/notreached.h"

 namespace base {
 class FilePath;
 }  // namespace base

namespace {
base::FilePath GetLocalizableBraveAppShortcutsSubdirName();
}

#define BRAVE_GET_CHROME_APPS_FOLDER_IMPL \
  return path.Append(GetLocalizableBraveAppShortcutsSubdirName());

#include <chrome/browser/web_applications/os_integration/mac/apps_folder_support.mm>
#undef BRAVE_GET_CHROME_APPS_FOLDER_IMPL

namespace {
// Browther: rebranding. Ces noms de dossier vivent dans ~/Applications et
// portent les app shims (.app) des PWA installées. Garder les noms Brave
// faisait écrire Browther dans le dossier de Brave : pour une PWA installée
// dans les deux navigateurs, le second arrivé se voit renommé « <App> 1.app »
// (désambiguïsation par bundle id) — dossiers distincts = noms propres et
// aucun risque de marcher sur les shims de Brave.
constexpr char kBraveBrowserDevelopmentAppDirName[] =
    "Browther Development Apps.localized";
constexpr char kBraveBrowserAppDirName[] = "Browther Apps.localized";
constexpr char kBraveBrowserBetaAppDirName[] = "Browther Beta Apps.localized";
constexpr char kBraveBrowserDevAppDirName[] = "Browther Dev Apps.localized";
constexpr char kBraveBrowserNightlyAppDirName[] =
    "Browther Nightly Apps.localized";

base::FilePath GetLocalizableBraveAppShortcutsSubdirName() {
  switch (chrome::GetChannel()) {
    case version_info::Channel::STABLE:
      return base::FilePath(kBraveBrowserAppDirName);
    case version_info::Channel::BETA:
      return base::FilePath(kBraveBrowserBetaAppDirName);
    case version_info::Channel::DEV:
      return base::FilePath(kBraveBrowserDevAppDirName);
    case version_info::Channel::CANARY:
      return base::FilePath(kBraveBrowserNightlyAppDirName);
    case version_info::Channel::UNKNOWN:
      return base::FilePath(kBraveBrowserDevelopmentAppDirName);
  }

  NOTREACHED() << "All possible channels are handled above.";
}
}  // namespace
