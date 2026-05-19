/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "brave/components/ntp_background_images/browser/browther_backgrounds_apk_extractor.h"

#if BUILDFLAG(IS_ANDROID)

#include <array>
#include <string>
#include <string_view>

#include "base/android/apk_assets.h"
#include "base/files/file.h"
#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/files/memory_mapped_file.h"
#include "base/logging.h"
#include "base/path_service.h"
#include "chrome/common/chrome_paths.h"

namespace ntp_background_images {

namespace {

// Liste des assets bundlés sous "assets/browther_backgrounds_mobile/" dans
// l'APK. Doit rester synchronisée avec :
//   - private/assets/backgrounds/*.jpg (source de vérité, partagée avec iOS)
//   - browther_backgrounds_mobile/BUILD.gn (target android_assets)
// La sentinelle photo.json est extraite en dernier pour garantir
// l'atomicité (si le boot crashe au milieu, on re-extraira tout au
// prochain boot).
constexpr std::array<std::string_view, 11> kBundledAssets = {
    "abdou-faiz-TQipjFceOBg-unsplash.jpg",
    "agnieszka-stankiewicz-MVrgqBB-fqU-unsplash.jpg",
    "clarisse-meyer-N88l6zWEhZk-unsplash.jpg",
    "david-billings-KCEwOduK8ck-unsplash.jpg",
    "izuddin-helmi-adnan-JFirQekVo3U-unsplash.jpg",
    "john-fowler-7Ym9rpYtSdA-unsplash.jpg",
    "localize-eXwQCS2TUUE-unsplash.jpg",
    "pommelien-da-silva-cosme-nnDgdAGoeAE-unsplash.jpg",
    "yasmine-arfaoui-R6rh5ttDO-4-unsplash.jpg",
    "younes-m-zVBWVMontM4-unsplash.jpg",
    // Sentinelle d'extraction réussie — toujours en dernier.
    "photo.json",
};

constexpr char kSentinelFile[] = "photo.json";
constexpr char kAssetDir[] = "browther_backgrounds_mobile";

bool ExtractAsset(const std::string& asset_path,
                  const base::FilePath& dest_path) {
  base::MemoryMappedFile::Region region;
  int asset_fd = base::android::OpenApkAsset(
      std::string("assets/") + kAssetDir + "/" + asset_path, &region);
  if (asset_fd < 0) {
    LOG(WARNING) << "[Browther] Failed to open APK asset: " << asset_path;
    return false;
  }

  base::MemoryMappedFile mapped_file;
  if (!mapped_file.Initialize(base::File(asset_fd), region)) {
    LOG(WARNING) << "[Browther] Failed to mmap APK asset: " << asset_path;
    return false;
  }

  base::CreateDirectory(dest_path.DirName());
  if (!base::WriteFile(
          dest_path,
          std::string_view(reinterpret_cast<const char*>(mapped_file.data()),
                           mapped_file.length()))) {
    LOG(WARNING) << "[Browther] Failed to write extracted asset: "
                 << dest_path.value();
    return false;
  }
  return true;
}

}  // namespace

void EnsureBrowtherBackgroundsExtracted() {
  base::FilePath user_data;
  if (!base::PathService::Get(chrome::DIR_USER_DATA, &user_data)) {
    LOG(ERROR) << "[Browther] DIR_USER_DATA unavailable; cannot extract "
               << "bundled NTP backgrounds.";
    return;
  }

  base::FilePath dest_root = user_data.AppendASCII(kAssetDir);
  base::FilePath sentinel = dest_root.AppendASCII(kSentinelFile);

  if (base::PathExists(sentinel)) {
    // Déjà extrait au précédent boot — rien à faire.
    return;
  }

  LOG(INFO) << "[Browther] Extracting bundled NTP backgrounds from APK to "
            << dest_root.value();

  base::CreateDirectory(dest_root);

  for (const auto& asset : kBundledAssets) {
    base::FilePath dest = dest_root.AppendASCII(std::string(asset));
    if (!ExtractAsset(std::string(asset), dest)) {
      LOG(WARNING) << "[Browther] Skipping failed background asset: " << asset;
    }
  }
}

}  // namespace ntp_background_images

#endif  // BUILDFLAG(IS_ANDROID)
