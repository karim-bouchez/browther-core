/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "brave/browser/ui/webui/welcome_page/browther_intro_installed_browsers.h"

#include <windows.h>

#include <array>
#include <string_view>

#include "base/command_line.h"
#include "base/files/file_util.h"
#include "base/strings/strcat.h"
#include "base/strings/string_util.h"
#include "base/win/registry.h"
#include "brave/common/importer/importer_constants.h"

namespace browther_intro {

namespace {

// Windows y range un navigateur installé par sous-clé — celles que liste
// Paramètres → Applications par défaut.
constexpr wchar_t kStartMenuInternet[] =
    L"Software\\Clients\\StartMenuInternet";

struct KnownBrowser {
  std::string_view name;
  // Noms de sous-clé. L'installeur Chromium suffixe les installations par
  // utilisateur (« Google Chrome.ABCD1234 », `GetBrowserClientKey` dans
  // shell_util.cc) : le suffixe est retiré avant de comparer.
  std::array<std::wstring_view, 3> keys;
  // Firefox suffixe par un tiret et une empreinte de son dossier
  // (« Firefox-308046B0AF4A39CB ») ; les anciens s'appelaient « FIREFOX.EXE ».
  bool prefix = false;
};

// ⛔ Pas Internet Explorer : l'import le propose sur tout Windows (« IE always
// exists », importer_list.cc), mais Windows 10 et 11 ne l'ouvrent plus, et Edge
// a repris ses favoris à son premier lancement.
constexpr auto kKnownBrowsers = std::to_array<KnownBrowser>({
    {kGoogleChromeBrowser, {L"Google Chrome"}},
    {kGoogleChromeBrowserBeta, {L"Google Chrome Beta"}},
    {kGoogleChromeBrowserDev, {L"Google Chrome Dev"}},
    {kGoogleChromeBrowserCanary, {L"Google Chrome Canary"}},
    {kChromiumBrowser, {L"Chromium"}},
    {kMicrosoftEdgeBrowser,
     {L"Microsoft Edge", L"Microsoft Edge Beta", L"Microsoft Edge Dev"}},
    {kVivaldiBrowser, {L"Vivaldi"}},
    {kOperaBrowser, {L"OperaStable"}},
    {kYandexBrowser, {L"Yandex", L"YandexBrowser"}},
    {kWhaleBrowser, {L"Naver Whale", L"Whale"}},
    {kBraveBrowser, {L"Brave", L"Brave Beta", L"Brave Nightly"}},
    {"Firefox", {L"Firefox"}, /*prefix=*/true},
});

bool Matches(std::wstring_view key, const KnownBrowser& browser) {
  const std::wstring_view base_name = key.substr(0, key.find(L'.'));
  for (std::wstring_view candidate : browser.keys) {
    if (candidate.empty()) {
      continue;
    }
    if (browser.prefix
            ? base::StartsWith(key, candidate,
                               base::CompareCase::INSENSITIVE_ASCII)
            : base::EqualsCaseInsensitiveASCII(base_name, candidate)) {
      return true;
    }
  }
  return false;
}

// ⚠️ Une clé peut survivre au navigateur (désinstallation incomplète, version
// portable effacée) : on ne la croit que si son exécutable est encore là.
bool ExecutableExists(HKEY root, REGSAM view, std::wstring_view key) {
  base::win::RegKey command;
  if (command.Open(root,
                   base::StrCat({kStartMenuInternet, L"\\", key,
                                 L"\\shell\\open\\command"})
                       .c_str(),
                   KEY_QUERY_VALUE | view) != ERROR_SUCCESS) {
    return false;
  }
  std::wstring value;
  if (command.ReadValue(nullptr, &value) != ERROR_SUCCESS) {
    return false;
  }
  return base::PathExists(base::CommandLine::FromString(value).GetProgram());
}

}  // namespace

std::optional<std::vector<std::string>> GetInstalledBrowsers() {
  struct Hive {
    HKEY root;
    REGSAM view;
  };
  // HKCU : installations pour l'utilisateur. HKLM, dans ses deux vues : un
  // navigateur 32 bits s'y range sous WOW6432Node.
  const auto hives = std::to_array<Hive>({
      {HKEY_CURRENT_USER, 0},
      {HKEY_LOCAL_MACHINE, KEY_WOW64_64KEY},
      {HKEY_LOCAL_MACHINE, KEY_WOW64_32KEY},
  });

  std::vector<std::wstring> registered;
  for (const Hive& hive : hives) {
    for (base::win::RegistryKeyIterator it(hive.root, kStartMenuInternet,
                                           hive.view);
         it.Valid(); ++it) {
      if (ExecutableExists(hive.root, hive.view, it.Name())) {
        registered.emplace_back(it.Name());
      }
    }
  }

  std::vector<std::string> installed;
  for (const KnownBrowser& browser : kKnownBrowsers) {
    for (const std::wstring& key : registered) {
      if (Matches(key, browser)) {
        installed.emplace_back(browser.name);
        break;
      }
    }
  }
  return installed;
}

}  // namespace browther_intro
