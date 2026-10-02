/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "brave/components/brave_shields/core/browser/shields_bundled_apk_extractor.h"

#if BUILDFLAG(IS_ANDROID)

#include <array>
#include <optional>
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

namespace brave_shields {

namespace {

// Liste des assets bundlés sous "assets/adblock_lists/" dans l'APK. Doit
// rester synchronisée avec la sortie de
// `private/scripts/fetch-shields-lists.py` — si on ajoute/retire des
// composants V1 → V2, mettre à jour cette liste.
//
// Note : on liste manuellement plutôt que d'énumérer dynamiquement via
// AAssetManager_openDir car ça ajoute une dépendance JNI runtime et la
// liste change peu en pratique. La sentinelle bundle_version.txt est
// extraite en dernier pour garantir l'atomicité (si le boot crashe au
// milieu, on re-extraira tout au prochain boot).
// ⚠️ Toute dérive avec le bundle fait échouer `fetch-shields-lists.py`
// (contrôle explicite en fin de génération) — c'est volontaire : une liste
// absente d'ici n'est jamais extraite, donc jamais chargée, sans le moindre
// message d'erreur.
constexpr std::array<std::string_view, 13> kBundledAssets = {
    "_resources/resources.json",
    "adcocjohghhfpidemphmcmlmhnfgikei/list.txt",
    "almolcgbkikkhliiibfjkohebgklegam/list.txt",
    "bfpgedeaaibpoidldhjcknekahbikncb/list.txt",
    "cdbbhgbmjhfnhnmgeddbliobbofkgdhe/list.txt",
    "cpapfkpkeaajehipopnaiihfmbfbnkdp/list.txt",
    "flnkmpokemfpaajmiimmjeiandgoodgg/list.txt",
    "iodkpdagapdfkphljnddpjlldadblomo/list.txt",
    "kihnoaefogbkmblfimmibknnmkllbhlf/list.txt",
    "lbnibkdpkdjnookgfeogjdanfenekmpe/list.txt",
    "phdmgpanpejkbmbljlhcehpadabljfbk/list.txt",
    "list_catalog.json",
    // Sentinelle d'extraction réussie — toujours en dernier.
    "bundle_version.txt",
};

// 🔴 La sentinelle porte la VERSION du bundle, pas sa simple présence. Jusqu'au
// 2026-10-02 c'était l'existence de list_catalog.json : une fois les listes
// extraites au premier lancement, aucune mise à jour de l'app ne les
// remplaçait — un utilisateur Android gardait à vie les listes de sa première
// installation. On ré-extrait donc dès que la version de l'APK diffère de celle
// déjà extraite.
constexpr char kSentinelFile[] = "bundle_version.txt";

// Browther: nos assets sont packagés dans le module de fonctionnalité
// « chrome », pas dans « base ». Le bundle Play est construit avec
// android:isolatedSplits="true" (chrome/android/java/AndroidManifest.xml,
// activé dès qu'on produit un .aab) : le contexte d'application ne voit
// alors QUE les assets de base, et un OpenApkAsset() sans nom de split
// échoue silencieusement. Dans un APK monolithique (build Component), le
// split n'existe pas et ApkAssets.open() retombe tout seul sur le contexte
// d'application. Même mécanique que Chromium pour ses propres DFM (cf.
// chrome/common/profiler/core_unwinders_android.cc). Voir
// private/docs/SHIELDS_BUNDLE.md § « Le piège du split chrome ».
constexpr char kChromeSplitName[] = "chrome";

int OpenAsset(const std::string& asset_path,
              base::MemoryMappedFile::Region* region) {
  const std::string apk_path = "assets/adblock_lists/" + asset_path;
  int asset_fd = base::android::OpenApkAsset(apk_path, kChromeSplitName, region);
  if (asset_fd < 0) {
    // Repli si les assets venaient à être rattachés au module de base.
    asset_fd = base::android::OpenApkAsset(apk_path, region);
  }
  return asset_fd;
}

// Contenu d'un petit asset (la version du bundle), ou nullopt.
std::optional<std::string> ReadAsset(const std::string& asset_path) {
  base::MemoryMappedFile::Region region;
  int asset_fd = OpenAsset(asset_path, &region);
  if (asset_fd < 0) {
    return std::nullopt;
  }
  base::MemoryMappedFile mapped_file;
  if (!mapped_file.Initialize(base::File(asset_fd), region)) {
    return std::nullopt;
  }
  return std::string(
      std::string_view(reinterpret_cast<const char*>(mapped_file.data()),
                       mapped_file.length()));
}

bool ExtractAsset(const std::string& asset_path,
                  const base::FilePath& dest_path) {
  base::MemoryMappedFile::Region region;
  int asset_fd = OpenAsset(asset_path, &region);
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

void EnsureBundledShieldsExtracted() {
  base::FilePath user_data;
  if (!base::PathService::Get(chrome::DIR_USER_DATA, &user_data)) {
    LOG(ERROR) << "[Browther] DIR_USER_DATA unavailable; cannot extract "
               << "bundled Shields lists.";
    return;
  }

  base::FilePath dest_root = user_data.AppendASCII("adblock_lists");
  base::FilePath sentinel = dest_root.AppendASCII(kSentinelFile);

  const std::optional<std::string> apk_version = ReadAsset(kSentinelFile);
  if (!apk_version &&
      base::PathExists(dest_root.AppendASCII("list_catalog.json"))) {
    // APK sans version lisible : comportement d'avant (extraire une fois), pour
    // ne pas réécrire 12 Mo à chaque lancement.
    return;
  }
  std::string extracted_version;
  if (apk_version &&
      base::ReadFileToStringWithMaxSize(sentinel, &extracted_version, 64) &&
      extracted_version == *apk_version) {
    // Déjà extrait, et c'est le bundle de cette version de l'app.
    return;
  }

  LOG(INFO) << "[Browther] Extracting bundled Shields filter lists from APK "
            << "to " << dest_root.value() << " (bundle "
            << apk_version.value_or("?") << ", extrait : "
            << (extracted_version.empty() ? "aucun" : extracted_version)
            << ")";

  // S'assurer que le dossier existe (les sous-dossiers sont créés par
  // ExtractAsset au fur et à mesure).
  base::CreateDirectory(dest_root);

  for (const auto& asset : kBundledAssets) {
    base::FilePath dest = dest_root.AppendASCII(std::string(asset));
    if (!ExtractAsset(std::string(asset), dest)) {
      // Continue malgré l'erreur — Shields se dégradera mais ne crashe pas.
      LOG(WARNING) << "[Browther] Skipping failed asset: " << asset;
    }
  }
}

}  // namespace brave_shields

#endif  // BUILDFLAG(IS_ANDROID)
