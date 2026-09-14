/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "brave/browser/ui/webui/welcome_page/browther_intro_installed_browsers.h"

#import <AppKit/AppKit.h>

#include <array>
#include <string_view>

#include "base/strings/sys_string_conversions.h"
#include "brave/common/importer/importer_constants.h"

namespace browther_intro {

namespace {

struct KnownBrowser {
  std::string_view name;
  // Toutes les éditions d'un même nom d'import : Firefox Developer Edition
  // s'importe comme Firefox.
  std::array<std::string_view, 3> bundle_ids;
};

constexpr auto kKnownBrowsers = std::to_array<KnownBrowser>({
    {kGoogleChromeBrowser, {"com.google.Chrome"}},
    {kGoogleChromeBrowserBeta, {"com.google.Chrome.beta"}},
    {kGoogleChromeBrowserDev, {"com.google.Chrome.dev"}},
    {kGoogleChromeBrowserCanary, {"com.google.Chrome.canary"}},
    {kChromiumBrowser, {"org.chromium.Chromium"}},
    {kMicrosoftEdgeBrowser,
     {"com.microsoft.edgemac", "com.microsoft.edgemac.Beta",
      "com.microsoft.edgemac.Dev"}},
    {kVivaldiBrowser, {"com.vivaldi.Vivaldi"}},
    {kOperaBrowser, {"com.operasoftware.Opera"}},
    {kYandexBrowser, {"ru.yandex.desktop.yandex-browser"}},
    {kWhaleBrowser, {"com.naver.Whale"}},
    {kBraveBrowser,
     {"com.brave.Browser", "com.brave.Browser.beta",
      "com.brave.Browser.nightly"}},
    {"Safari", {"com.apple.Safari"}},
    {"Firefox",
     {"org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
      "org.mozilla.nightly"}},
});

}  // namespace

std::optional<std::vector<std::string>> GetInstalledBrowsers() {
  std::vector<std::string> installed;
  @autoreleasepool {
    NSWorkspace* workspace = [NSWorkspace sharedWorkspace];
    for (const KnownBrowser& browser : kKnownBrowsers) {
      for (std::string_view bundle_id : browser.bundle_ids) {
        if (bundle_id.empty()) {
          continue;
        }
        if ([workspace URLForApplicationWithBundleIdentifier:
                           base::SysUTF8ToNSString(bundle_id)]) {
          installed.emplace_back(browser.name);
          break;
        }
      }
    }
  }
  return installed;
}

}  // namespace browther_intro
