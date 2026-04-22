/* Copyright (c) 2019 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

#include "brave/browser/extensions/brave_component_loader.h"

#include <string>
#include <utility>

#include "base/check.h"
#include "base/check_op.h"
#include "base/command_line.h"
#include "base/feature_list.h"
#include "base/functional/bind.h"
#include "base/json/json_reader.h"
#include "brave/components/brave_extension/grit/brave_extension.h"
#include "brave/components/constants/brave_switches.h"
#include "brave/components/constants/pref_names.h"
#include "brave/components/web_discovery/buildflags/buildflags.h"
#include "base/files/file_util.h"
#include "base/path_service.h"
#include "chrome/browser/extensions/extension_service.h"
#include "chrome/common/chrome_paths.h"
#include "chrome/browser/profiles/profile.h"
#include "components/prefs/pref_service.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_system.h"
#include "extensions/common/constants.h"
#include "extensions/common/mojom/manifest.mojom.h"
#include "extensions/common/switches.h"
#include "ui/base/resource/resource_bundle.h"

#if BUILDFLAG(ENABLE_WEB_DISCOVERY_NATIVE)
#include "brave/components/web_discovery/common/features.h"
#endif

namespace extensions {

BraveComponentLoader::BraveComponentLoader(Profile* profile)
    : ComponentLoader(profile),
      profile_(profile),
      profile_prefs_(profile->GetPrefs()) {
  pref_change_registrar_.Init(profile_prefs_);
  pref_change_registrar_.Add(
      kWebDiscoveryEnabled,
      base::BindRepeating(&BraveComponentLoader::UpdateBraveExtension,
                          base::Unretained(this)));
  // Browther: Sawtunaa — watch the pref to load/unload the extension
  pref_change_registrar_.Add(
      kSawtunaaEnabled,
      base::BindRepeating(&BraveComponentLoader::UpdateSawtunaaExtension,
                          base::Unretained(this)));
}

BraveComponentLoader::~BraveComponentLoader() = default;

void BraveComponentLoader::AddDefaultComponentExtensions(
    bool skip_session_components) {
  ComponentLoader::AddDefaultComponentExtensions(skip_session_components);
  UpdateBraveExtension();

  // Browther: Sawtunaa — read manifest from disk at startup (blocking allowed here)
  {
    const base::CommandLine& command_line =
        *base::CommandLine::ForCurrentProcess();
    if (command_line.HasSwitch("sawtunaa-extension-path")) {
      sawtunaa_path_ =
          command_line.GetSwitchValuePath("sawtunaa-extension-path");
    } else {
      base::FilePath exe_dir;
      base::PathService::Get(base::DIR_EXE, &exe_dir);
      sawtunaa_path_ = exe_dir.AppendASCII("sawtunaa");
    }

    base::FilePath manifest_path =
        sawtunaa_path_.AppendASCII("manifest.json");
    std::string manifest_contents;
    if (base::PathExists(manifest_path) &&
        base::ReadFileToString(manifest_path, &manifest_contents)) {
      sawtunaa_manifest_ = base::JSONReader::ReadDict(
          manifest_contents, base::JSON_PARSE_CHROMIUM_EXTENSIONS);
      if (sawtunaa_manifest_) {
        LOG(INFO) << "[Sawtunaa] Manifest loaded from: "
                  << sawtunaa_path_.value();
      } else {
        LOG(ERROR) << "[Sawtunaa] Invalid manifest JSON at: "
                   << manifest_path.value();
      }
    } else {
      LOG(WARNING) << "[Sawtunaa] Extension not found at: "
                   << sawtunaa_path_.value();
    }
  }
  UpdateSawtunaaExtension();
}

bool BraveComponentLoader::UseBraveExtensionBackgroundPage() {
  bool native_enabled = false;
#if BUILDFLAG(ENABLE_WEB_DISCOVERY_NATIVE)
  native_enabled = base::FeatureList::IsEnabled(
      web_discovery::features::kBraveWebDiscoveryNative);
#endif
  return !native_enabled && profile_prefs_->GetBoolean(kWebDiscoveryEnabled);
}

void BraveComponentLoader::UpdateBraveExtension() {
  const base::CommandLine& command_line =
      *base::CommandLine::ForCurrentProcess();
  if (command_line.HasSwitch(::switches::kDisableBraveExtension)) {
    return;
  }

  base::FilePath brave_extension_path(FILE_PATH_LITERAL(""));
  brave_extension_path =
      brave_extension_path.Append(FILE_PATH_LITERAL("brave_extension"));
  auto& resource_bundle = ui::ResourceBundle::GetSharedInstance();
  std::optional<base::DictValue> manifest = base::JSONReader::ReadDict(
      resource_bundle.LoadDataResourceString(IDR_BRAVE_EXTENSION),
      base::JSON_PARSE_CHROMIUM_EXTENSIONS);
  CHECK(manifest) << "invalid Brave Extension manifest";

  // The background page is a conditional. Replace MAYBE_background in the
  // manifest to "background" or remove it.
  auto background_value = manifest->Extract("MAYBE_background");
  if (UseBraveExtensionBackgroundPage() && background_value) {
    manifest->Set("background", std::move(*background_value));
  }

  extensions::ExtensionRegistry* registry =
      extensions::ExtensionRegistry::Get(profile_);
  const Extension* current_extension =
      registry->GetInstalledExtension(brave_extension_id);

  if (current_extension) {
    const auto* current_manifest = current_extension->manifest();
    if (current_manifest && *current_manifest->value() == *manifest) {
      return;  // Skip reload, nothing is actually changed.
    }
    Remove(brave_extension_id);
  }

  const auto id = Add(std::move(*manifest), brave_extension_path);
  CHECK_EQ(id, brave_extension_id);
}

// Browther: Load/unload the Sawtunaa extension based on kSawtunaaEnabled pref.
// Manifest is pre-loaded at startup in AddDefaultComponentExtensions().
// This method only does Add/Remove (no file I/O), safe to call on UI thread.
void BraveComponentLoader::UpdateSawtunaaExtension() {
  const bool enabled = profile_prefs_->GetBoolean(kSawtunaaEnabled);

  // If disabled and currently loaded, remove it
  if (!enabled) {
    if (!sawtunaa_extension_id_.empty()) {
      Remove(sawtunaa_extension_id_);
      sawtunaa_extension_id_.clear();
      LOG(INFO) << "[Sawtunaa] Extension unloaded";
    }
    return;
  }

  // Already loaded
  if (!sawtunaa_extension_id_.empty()) {
    return;
  }

  // No manifest available (not found at startup)
  if (!sawtunaa_manifest_) {
    LOG(WARNING) << "[Sawtunaa] No manifest cached, cannot load";
    return;
  }

  // Clone the manifest (Add takes ownership)
  sawtunaa_extension_id_ = Add(sawtunaa_manifest_->Clone(), sawtunaa_path_);
  LOG(INFO) << "[Sawtunaa] Extension loaded, id: " << sawtunaa_extension_id_;

  // Allow Sawtunaa to use tabCapture without activeTab user gesture.
  base::CommandLine::ForCurrentProcess()->AppendSwitchASCII(
      extensions::switches::kAllowlistedExtensionID, sawtunaa_extension_id_);
}

}  // namespace extensions
