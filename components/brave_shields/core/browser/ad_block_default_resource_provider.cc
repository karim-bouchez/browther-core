// Copyright (c) 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/brave_shields/core/browser/ad_block_default_resource_provider.h"

#include <string>
#include <utility>

#include "base/files/file_path.h"
#include "base/path_service.h"
#include "base/task/thread_pool.h"
#include "brave/components/brave_component_updater/browser/dat_file_util.h"
#include "brave/components/brave_shields/core/browser/ad_block_component_installer.h"
#include "build/build_config.h"
#if !BUILDFLAG(IS_IOS)
// Browther: chrome/common/chrome_paths.h inclut transitivement
// widevine/cdm/buildflags.h qui n'est pas buildé sur iOS. On utilise
// base::DIR_ASSETS directement sur iOS (cf. branche dans le constructor).
#include "chrome/common/chrome_paths.h"
#endif

namespace {

constexpr char kAdBlockResourcesFilename[] = "resources.json";

}  // namespace

namespace brave_shields {

AdBlockDefaultResourceProvider::AdBlockDefaultResourceProvider(
    component_updater::ComponentUpdateService* cus) {
  // Can be nullptr in unit tests
  if (!cus) {
    return;
  }

  RegisterAdBlockDefaultResourceComponent(
      cus,
      base::BindRepeating(&AdBlockDefaultResourceProvider::OnComponentReady,
                          weak_factory_.GetWeakPtr()));

  // Browther: charge resources.json depuis le bundle local sans attendre le
  // component updater (qui ne fonctionne pas — voir SHIELDS_BUNDLE.md).
  // - Mac/Win/Linux : DIR_RESOURCES + adblock_lists/_resources/.
  // - Android : DIR_USER_DATA + adblock_lists/_resources/ (extrait depuis
  //   APK au boot via shields_bundled_apk_extractor.cc).
  // NE PAS faire de PathExists ici — le constructor tourne dans un scope
  // no-blocking (DCHECK fail). OnComponentReady fait déjà la lecture en
  // ThreadPool, qui gère naturellement les fichiers manquants.
  base::FilePath base_dir;
  bool ok =
#if BUILDFLAG(IS_ANDROID)
      base::PathService::Get(chrome::DIR_USER_DATA, &base_dir);
#elif BUILDFLAG(IS_IOS)
      // Sur iOS, le framework bundle est flat (pas de subdir "resources/" —
      // codesign rejette ce format). Les fichiers bundlés vivent au root du
      // framework, donc on lit base::DIR_ASSETS = FrameworkBundlePath()
      // (= BraveCore.framework) directement, sans intermédiaire.
      base::PathService::Get(base::DIR_ASSETS, &base_dir);
#else
      base::PathService::Get(chrome::DIR_RESOURCES, &base_dir);
#endif
  if (ok) {
    OnComponentReady(
        base_dir.AppendASCII("adblock_lists").AppendASCII("_resources"));
  }
}

AdBlockDefaultResourceProvider::~AdBlockDefaultResourceProvider() = default;

base::FilePath AdBlockDefaultResourceProvider::GetResourcesPath() {
  if (component_path_.empty()) {
    // Since we know it's empty return it as is.
    return component_path_;
  }

  return component_path_.AppendASCII(kAdBlockResourcesFilename);
}

void AdBlockDefaultResourceProvider::OnComponentReady(
    const base::FilePath& path) {
  component_path_ = path;
  base::FilePath resources_path = GetResourcesPath();

  if (resources_path.empty()) {
    // This should not happen, but if it does, we should not proceed.
    return;
  }

  // Load the resources (as ResourceStorage)
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock()},
      base::BindOnce(&brave_component_updater::GetDATFileAsString,
                     resources_path),
      base::BindOnce(
          [](base::WeakPtr<AdBlockDefaultResourceProvider> provider,
             const std::string& resources_json) {
            if (!provider) {
              return;
            }
            auto storage = adblock::new_resource_storage(resources_json);
            provider->NotifyResourcesLoaded(std::move(storage));
          },
          weak_factory_.GetWeakPtr()));
}

void AdBlockDefaultResourceProvider::LoadResources(
    base::OnceCallback<void(AdblockResourceStorageBox)> cb) {
  base::FilePath resources_path = GetResourcesPath();
  if (resources_path.empty()) {
    // If the path is not ready yet, run the callback with empty resources to
    // avoid blocking filter data loads.
    auto empty_storage = adblock::new_empty_resource_storage();
    std::move(cb).Run(std::move(empty_storage));
    return;
  }

  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock()},
      base::BindOnce(&brave_component_updater::GetDATFileAsString,
                     resources_path),
      base::BindOnce(
          [](base::OnceCallback<void(AdblockResourceStorageBox)> cb,
             const std::string& resources_json) {
            auto storage = adblock::new_resource_storage(resources_json);
            std::move(cb).Run(std::move(storage));
          },
          std::move(cb)));
}

}  // namespace brave_shields
