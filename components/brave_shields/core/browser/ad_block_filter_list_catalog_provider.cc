// Copyright (c) 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/brave_shields/core/browser/ad_block_filter_list_catalog_provider.h"

#include <string>
#include <utility>

#include "base/files/file_path.h"
#include "base/path_service.h"
#include "base/task/thread_pool.h"
#include "base/trace_event/trace_event.h"
#include "brave/components/brave_shields/core/browser/ad_block_component_installer.h"
#include "build/build_config.h"
#if !BUILDFLAG(IS_IOS)
// Browther: chrome/common/chrome_paths.h inclut transitivement
// widevine/cdm/buildflags.h qui n'est pas buildé sur iOS. On utilise
// base::DIR_ASSETS directement sur iOS.
#include "chrome/common/chrome_paths.h"
#endif

constexpr char kListCatalogFile[] = "list_catalog.json";

namespace brave_shields {

namespace {

// Browther: résout le path de notre bundle local de filter lists. Voir
// private/docs/SHIELDS_BUNDLE.md.
// - Mac/Win/Linux : <chrome::DIR_RESOURCES>/adblock_lists/ — copié au
//   build via bundle_data (Mac) ou copy() GN target (Win/Linux).
// - Android : <chrome::DIR_USER_DATA>/adblock_lists/ — extrait au premier
//   boot depuis APK assets via shields_bundled_apk_extractor.cc.
//   chrome::DIR_RESOURCES retourne false sur Android (pas de filesystem).
base::FilePath GetBrowtherBundledShieldsPath() {
  base::FilePath base_dir;
#if BUILDFLAG(IS_ANDROID)
  if (!base::PathService::Get(chrome::DIR_USER_DATA, &base_dir)) {
    return base::FilePath();
  }
#elif BUILDFLAG(IS_IOS)
  // Sur iOS, le framework bundle est flat (pas de subdir "resources/" —
  // codesign rejette ce format). Les fichiers bundlés vivent au root du
  // framework, donc on lit base::DIR_ASSETS = FrameworkBundlePath()
  // (= BraveCore.framework) directement.
  if (!base::PathService::Get(base::DIR_ASSETS, &base_dir)) {
    return base::FilePath();
  }
#else
  if (!base::PathService::Get(chrome::DIR_RESOURCES, &base_dir)) {
    return base::FilePath();
  }
#endif
  return base_dir.AppendASCII("adblock_lists");
}

}  // namespace

AdBlockFilterListCatalogProvider::AdBlockFilterListCatalogProvider(
    component_updater::ComponentUpdateService* cus) {
  TRACE_EVENT("brave.adblock", "RegisterAdBlockFilterListCatalogComponent",
              perfetto::Flow::FromPointer(this));
  // Can be nullptr in unit tests
  if (cus) {
    RegisterAdBlockFilterListCatalogComponent(
        cus,
        base::BindRepeating(&AdBlockFilterListCatalogProvider::OnComponentReady,
                            weak_factory_.GetWeakPtr()));
  }

  // Browther: charge immédiatement le catalog bundlé depuis l'app sans
  // attendre le component updater (qui ne fonctionne pas dans Browther — voir
  // private/docs/SHIELDS_BUNDLE.md). Si jamais le component updater finit par
  // fonctionner, OnComponentReady() sera ré-appelé avec le path à jour.
  base::FilePath bundled = GetBrowtherBundledShieldsPath();
  if (!bundled.empty()) {
    OnComponentReady(bundled);
  }
}

AdBlockFilterListCatalogProvider::~AdBlockFilterListCatalogProvider() = default;

void AdBlockFilterListCatalogProvider::AddObserver(
    AdBlockFilterListCatalogProvider::Observer* observer) {
  observers_.AddObserver(observer);
}

void AdBlockFilterListCatalogProvider::RemoveObserver(
    AdBlockFilterListCatalogProvider::Observer* observer) {
  observers_.RemoveObserver(observer);
}

void AdBlockFilterListCatalogProvider::OnFilterListCatalogLoaded(
    const std::string& catalog_json) {
  TRACE_EVENT("brave.adblock",
              "AdBlockFilterListCatalogProvider::OnFilterListCatalogLoaded",
              perfetto::TerminatingFlow::FromPointer(this), "catalog_json_size",
              catalog_json.size());
  for (auto& observer : observers_) {
    observer.OnFilterListCatalogLoaded(catalog_json);
  }
}

void AdBlockFilterListCatalogProvider::OnComponentReady(
    const base::FilePath& path) {
  TRACE_EVENT("brave.adblock",
              "AdBlockFilterListCatalogProvider::OnComponentReady",
              perfetto::Flow::FromPointer(this), "path", path.value());
  component_path_ = path;

  // Load the filter list catalog (as a string)
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock()},
      base::BindOnce(&brave_component_updater::GetDATFileAsString,
                     component_path_.AppendASCII(kListCatalogFile)),
      base::BindOnce(
          &AdBlockFilterListCatalogProvider::OnFilterListCatalogLoaded,
          weak_factory_.GetWeakPtr()));
}

void AdBlockFilterListCatalogProvider::LoadFilterListCatalog(
    base::OnceCallback<void(const std::string& catalog_json)> cb) {
  if (component_path_.empty()) {
    // If the path is not ready yet, don't run the callback. An update should be
    // pushed soon.
    return;
  }

  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock()},
      base::BindOnce(&brave_component_updater::GetDATFileAsString,
                     component_path_.AppendASCII(kListCatalogFile)),
      std::move(cb));
}

}  // namespace brave_shields
