/* Copyright (c) 2019 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_BROWSER_EXTENSIONS_BRAVE_COMPONENT_LOADER_H_
#define BRAVE_BROWSER_EXTENSIONS_BRAVE_COMPONENT_LOADER_H_

#include "base/memory/raw_ptr.h"
#include <optional>

#include "base/values.h"
#include "chrome/browser/extensions/component_loader.h"
#include "components/prefs/pref_change_registrar.h"

class PrefService;
class Profile;

namespace extensions {

// For registering, loading, and unloading component extensions.
class BraveComponentLoader : public ComponentLoader {
 public:
  explicit BraveComponentLoader(Profile* browser_context);
  BraveComponentLoader(const BraveComponentLoader&) = delete;
  BraveComponentLoader& operator=(const BraveComponentLoader&) = delete;
  ~BraveComponentLoader() override;

  // Adds the default component extensions. If |skip_session_components|
  // the loader will skip loading component extensions that weren't supposed to
  // be loaded unless we are in signed user session (ChromeOS). For all other
  // platforms this |skip_session_components| is expected to be unset.
  void AddDefaultComponentExtensions(bool skip_session_components) override;

 private:
  void UpdateBraveExtension();
  void UpdateSawtunaaExtension();   // Browther: Sawtunaa
  void UpdateBasarunaaExtension();  // Browther: Basarunaa

  bool UseBraveExtensionBackgroundPage();

  raw_ptr<Profile> profile_ = nullptr;
  raw_ptr<PrefService> profile_prefs_ = nullptr;
  std::string sawtunaa_extension_id_;       // Browther: Sawtunaa
  base::FilePath sawtunaa_path_;            // Browther: cached path
  std::optional<base::DictValue> sawtunaa_manifest_;  // Browther: cached manifest
  std::string basarunaa_extension_id_;       // Browther: Basarunaa
  base::FilePath basarunaa_path_;            // Browther: cached path
  std::optional<base::DictValue> basarunaa_manifest_;  // Browther: cached manifest

  PrefChangeRegistrar pref_change_registrar_;
};

}  // namespace extensions

#endif  // BRAVE_BROWSER_EXTENSIONS_BRAVE_COMPONENT_LOADER_H_
