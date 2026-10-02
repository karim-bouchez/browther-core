// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/browther_shields_lists/shields_lists_updater.h"

#include <algorithm>
#include <utility>

#include "base/command_line.h"
#include "base/files/file_enumerator.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/strings/strcat.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
#include "base/task/thread_pool.h"
#include "base/time/time.h"
#include "brave/components/browther_shields_lists/pref_names.h"
#include "components/prefs/pref_service.h"
#include "crypto/hash.h"
#include "net/base/load_flags.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/shared_url_loader_factory.h"
#include "services/network/public/cpp/simple_url_loader.h"
#include "url/gurl.h"

namespace browther_shields_lists {

namespace {

constexpr char kDefaultBaseUrl[] =
    "https://browther-download.devndin.com/shields/v1/";
// Pour tester contre un serveur local : --browther-shields-lists-url=http://…/
constexpr char kBaseUrlSwitch[] = "browther-shields-lists-url";
constexpr char kManifestName[] = "latest.json";
constexpr char kFilesPath[] = "files/";
// Écrit par private/scripts/fetch-shields-lists.py à la racine du bundle.
constexpr char kBundleVersionFile[] = "bundle_version.txt";
constexpr char kDownloadDir[] = ".download";
// Version d'un bundle trop ancien pour avoir un bundle_version.txt.
constexpr char kUnknownBundleVersion[] = "00000000000000";

// Pas pendant le démarrage : le moteur vient de charger ses listes.
constexpr base::TimeDelta kStartupDelay = base::Seconds(30);
// Le serveur publie toutes les 6 h (.github/workflows/shields-lists.yml).
constexpr base::TimeDelta kCheckInterval = base::Hours(6);
constexpr size_t kMaxManifestSize = 256 * 1024;

constexpr net::NetworkTrafficAnnotationTag kTrafficAnnotation =
    net::DefineNetworkTrafficAnnotation("browther_shields_lists", R"ANNOT(
        semantics {
          sender: "Browther Shields lists updater"
          description:
            "Downloads up-to-date ad and tracker blocking lists (EasyList, "
            "uBlock Origin filters and the scriptlets they use) published by "
            "dev&din, so that ad blocking keeps working between two Browther "
            "releases. Brave's own updater cannot be used: its server only "
            "answers official Brave builds."
          trigger:
            "30 seconds after startup, then every 6 hours."
          data:
            "None. Plain GET of a signed index and of the list files it "
            "references; no cookies, no identifier."
          destination: OTHER
          destination_other:
            "browther-download.devndin.com (Cloudflare R2, run by dev&din)"
        }
        policy {
          cookies_allowed: NO
          setting:
            "There is no dedicated setting; the lists are only used while "
            "Shields ad blocking is enabled."
          policy_exception_justification:
            "Not implemented, consumer-facing browser."
        })ANNOT");

std::string ReadBundledVersion(const base::FilePath& bundled_root) {
  std::string content;
  if (!base::ReadFileToStringWithMaxSize(
          bundled_root.AppendASCII(kBundleVersionFile), &content, 64)) {
    return kUnknownBundleVersion;
  }
  const std::string_view version =
      base::TrimWhitespaceASCII(content, base::TRIM_ALL);
  return IsValidVersion(version) ? std::string(version)
                                 : kUnknownBundleVersion;
}

bool FileMatches(const base::FilePath& path,
                 const std::string& sha256,
                 int64_t size) {
  if (base::GetFileSize(path) != size) {
    return false;
  }
  std::string content;
  if (!base::ReadFileToString(path, &content)) {
    return false;
  }
  return base::HexEncodeLower(crypto::hash::Sha256(content)) == sha256;
}

ShieldsListsUpdater::StartupCheck RunStartupCheck(
    const base::FilePath& root,
    const base::FilePath& bundled_root,
    const ActiveSet& active) {
  ShieldsListsUpdater::StartupCheck check;
  check.bundled_version = ReadBundledVersion(bundled_root);
  for (const auto& [path, file] : active.files) {
    if (!FileMatches(GetActiveFilePath(root, path, file.dir), file.sha256,
                     file.size)) {
      check.broken_files.insert(path);
    }
  }
  return check;
}

bool VerifyAndInstall(const base::FilePath& downloaded,
                      const std::string& sha256,
                      int64_t size,
                      const base::FilePath& destination) {
  if (!FileMatches(downloaded, sha256, size)) {
    base::DeleteFile(downloaded);
    return false;
  }
  if (!base::CreateDirectory(destination.DirName()) ||
      !base::Move(downloaded, destination)) {
    base::DeleteFile(downloaded);
    return false;
  }
  return true;
}

// Supprime, sous `root`, tout dossier de version qui n'est pas dans `keep`.
// Rien d'autre n'est jamais supprimé : `root` n'appartient qu'à nous, et le
// bundle (signé, en lecture seule) n'est jamais touché.
void DeleteUnreferenced(const base::FilePath& root,
                        const std::set<base::FilePath>& keep,
                        bool purge_downloads) {
  const base::FilePath downloads = root.AppendASCII(kDownloadDir);
  if (purge_downloads) {
    base::DeletePathRecursively(downloads);
  }
  base::CreateDirectory(downloads);

  base::FileEnumerator components(root, /*recursive=*/false,
                                  base::FileEnumerator::DIRECTORIES);
  for (base::FilePath component = components.Next(); !component.empty();
       component = components.Next()) {
    if (component == downloads) {
      continue;
    }
    base::FileEnumerator versions(component, /*recursive=*/false,
                                  base::FileEnumerator::DIRECTORIES);
    for (base::FilePath version = versions.Next(); !version.empty();
         version = versions.Next()) {
      if (!keep.contains(version)) {
        base::DeletePathRecursively(version);
      }
    }
    if (base::IsDirectoryEmpty(component)) {
      base::DeleteFile(component);
    }
  }
}

std::unique_ptr<network::SimpleURLLoader> CreateLoader(const GURL& url) {
  auto request = std::make_unique<network::ResourceRequest>();
  request->url = url;
  request->method = "GET";
  request->credentials_mode = network::mojom::CredentialsMode::kOmit;
  request->load_flags = net::LOAD_DISABLE_CACHE | net::LOAD_DO_NOT_SAVE_COOKIES;
  auto loader =
      network::SimpleURLLoader::Create(std::move(request), kTrafficAnnotation);
  loader->SetRetryOptions(
      2, network::SimpleURLLoader::RETRY_ON_NETWORK_CHANGE |
             network::SimpleURLLoader::RETRY_ON_5XX);
  return loader;
}

}  // namespace

ShieldsListsUpdater::StartupCheck::StartupCheck() = default;
ShieldsListsUpdater::StartupCheck::StartupCheck(StartupCheck&&) = default;
ShieldsListsUpdater::StartupCheck& ShieldsListsUpdater::StartupCheck::operator=(
    StartupCheck&&) = default;
ShieldsListsUpdater::StartupCheck::~StartupCheck() = default;

ShieldsListsUpdater::ShieldsListsUpdater(
    PrefService* local_state,
    const base::FilePath& bundled_root,
    URLLoaderFactoryGetter url_loader_factory_getter)
    : local_state_(local_state),
      bundled_root_(bundled_root),
      url_loader_factory_getter_(std::move(url_loader_factory_getter)),
      base_url_(kDefaultBaseUrl),
      bundled_version_(kUnknownBundleVersion),
      file_task_runner_(base::ThreadPool::CreateSequencedTaskRunner(
          {base::MayBlock(), base::TaskPriority::BEST_EFFORT,
           base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN})) {
  const auto* command_line = base::CommandLine::ForCurrentProcess();
  if (command_line->HasSwitch(kBaseUrlSwitch)) {
    base_url_ = command_line->GetSwitchValueASCII(kBaseUrlSwitch);
    if (!base_url_.ends_with('/')) {
      base_url_ += '/';
    }
  }
}

ShieldsListsUpdater::~ShieldsListsUpdater() = default;

void ShieldsListsUpdater::Start() {
  ActiveLists* lists = ActiveLists::GetInstance();
  if (lists->root().empty()) {
    LOG(ERROR) << "[Browther] Listes Shields : LoadActiveListsFromPrefs n'a "
                  "pas été appelé — mise à jour à chaud désactivée.";
    return;
  }
  file_task_runner_->PostTaskAndReplyWithResult(
      FROM_HERE,
      base::BindOnce(&RunStartupCheck, lists->root(), bundled_root_,
                     lists->active_set()),
      base::BindOnce(&ShieldsListsUpdater::OnStartupChecked,
                     weak_factory_.GetWeakPtr()));
}

void ShieldsListsUpdater::OnStartupChecked(StartupCheck check) {
  bundled_version_ = std::move(check.bundled_version);
  ActiveSet active = ActiveLists::GetInstance()->active_set();
  bool changed = false;

  if (!active.version.empty() && active.version < bundled_version_) {
    // Une mise à jour de l'app a apporté des listes plus récentes.
    LOG(INFO) << "[Browther] Listes Shields : le bundle (" << bundled_version_
              << ") est plus récent que les listes téléchargées ("
              << active.version << ") — retour au bundle.";
    active = ActiveSet();
    changed = true;
  } else {
    for (const std::string& path : check.broken_files) {
      LOG(WARNING) << "[Browther] Listes Shields : " << path
                   << " manquant ou altéré — retour au bundle pour ce fichier.";
      active.files.erase(path);
      changed = true;
      repair_needed_ = true;
    }
    if (active.files.empty()) {
      active.version.clear();
    }
  }
  if (changed) {
    PersistAndActivate(active);
  }
  CleanupUnreferenced(active, active, /*purge_downloads=*/true);

  startup_timer_.Start(FROM_HERE, kStartupDelay,
                       base::BindOnce(&ShieldsListsUpdater::CheckForUpdate,
                                      weak_factory_.GetWeakPtr()));
  periodic_timer_.Start(FROM_HERE, kCheckInterval,
                        base::BindRepeating(&ShieldsListsUpdater::CheckForUpdate,
                                            weak_factory_.GetWeakPtr()));
}

std::string ShieldsListsUpdater::CurrentVersion() const {
  const std::string& active = ActiveLists::GetInstance()->active_set().version;
  return std::max(active, bundled_version_);
}

void ShieldsListsUpdater::CheckForUpdate() {
  if (loader_ || pending_) {
    return;
  }
  scoped_refptr<network::SharedURLLoaderFactory> factory =
      url_loader_factory_getter_.Run();
  if (!factory) {
    return;
  }
  loader_ = CreateLoader(GURL(base_url_ + kManifestName));
  loader_->DownloadToString(
      factory.get(),
      base::BindOnce(&ShieldsListsUpdater::OnManifestDownloaded,
                     weak_factory_.GetWeakPtr()),
      kMaxManifestSize);
}

void ShieldsListsUpdater::OnManifestDownloaded(
    std::optional<std::string> body) {
  const int net_error = loader_->NetError();
  loader_.reset();
  if (!body) {
    VLOG(1) << "[Browther] Listes Shields : index injoignable (" << net_error
            << ").";
    return;
  }
  std::optional<Manifest> manifest = ParseSignedManifest(*body);
  if (!manifest) {
    // Soit l'index a été altéré, soit la clé de signature a changé : dans les
    // deux cas on garde ce qu'on a, rien n'est appliqué.
    LOG(WARNING) << "[Browther] Listes Shields : index refusé (signature ou "
                    "format invalide).";
    return;
  }

  const ActiveSet& active = ActiveLists::GetInstance()->active_set();
  const bool newer = manifest->version > CurrentVersion();
  const bool repair = repair_needed_ && !active.version.empty() &&
                      manifest->version >= active.version;
  if (!newer && !repair) {
    VLOG(1) << "[Browther] Listes Shields : à jour (" << CurrentVersion()
            << ").";
    return;
  }

  ActiveSet next;
  next.version = manifest->version;
  to_download_.clear();
  for (const auto& [path, file] : manifest->files) {
    auto it = active.files.find(path);
    if (it != active.files.end() && it->second.sha256 == file.sha256) {
      // Inchangé : même dossier, donc aucune recompilation côté iOS.
      next.files.emplace(path, it->second);
      continue;
    }
    next.files.emplace(path,
                       ActiveFile{file.sha256, file.size, manifest->version});
    to_download_.push_back(path);
  }
  pending_ = std::move(next);
  downloaded_count_ = 0;
  DownloadNext();
}

void ShieldsListsUpdater::DownloadNext() {
  if (to_download_.empty()) {
    Commit();
    return;
  }
  scoped_refptr<network::SharedURLLoaderFactory> factory =
      url_loader_factory_getter_.Run();
  if (!factory) {
    Abort("réseau indisponible");
    return;
  }
  const ActiveFile& file = pending_->files.at(to_download_.back());
  loader_ = CreateLoader(GURL(base::StrCat({base_url_, kFilesPath, file.sha256})));
  loader_->DownloadToFile(
      factory.get(),
      base::BindOnce(&ShieldsListsUpdater::OnFileDownloaded,
                     weak_factory_.GetWeakPtr()),
      ActiveLists::GetInstance()
          ->root()
          .AppendASCII(kDownloadDir)
          .AppendASCII(file.sha256 + ".part"),
      file.size);
}

void ShieldsListsUpdater::OnFileDownloaded(base::FilePath downloaded) {
  const int net_error = loader_->NetError();
  loader_.reset();
  const std::string& path = to_download_.back();
  if (downloaded.empty()) {
    Abort(base::StrCat({"téléchargement de ", path, " échoué (",
                        base::NumberToString(net_error), ")"}));
    return;
  }
  const ActiveFile& file = pending_->files.at(path);
  file_task_runner_->PostTaskAndReplyWithResult(
      FROM_HERE,
      base::BindOnce(&VerifyAndInstall, downloaded, file.sha256, file.size,
                     GetActiveFilePath(ActiveLists::GetInstance()->root(),
                                       path, file.dir)),
      base::BindOnce(&ShieldsListsUpdater::OnFileInstalled,
                     weak_factory_.GetWeakPtr()));
}

void ShieldsListsUpdater::OnFileInstalled(bool ok) {
  if (!ok) {
    Abort(base::StrCat({"empreinte invalide pour ", to_download_.back()}));
    return;
  }
  to_download_.pop_back();
  ++downloaded_count_;
  DownloadNext();
}

void ShieldsListsUpdater::Commit() {
  ActiveSet previous = ActiveLists::GetInstance()->active_set();
  ActiveSet next = std::move(*pending_);
  pending_.reset();
  repair_needed_ = false;
  LOG(INFO) << "[Browther] Listes Shields mises à jour : version "
            << next.version << " (" << downloaded_count_
            << " fichier(s) téléchargé(s)).";
  PersistAndActivate(next);
  // On garde aussi l'ensemble précédent jusqu'au prochain démarrage : WebKit
  // (iOS) peut encore relire un ancien fichier pendant sa recompilation.
  CleanupUnreferenced(next, previous, /*purge_downloads=*/false);
}

void ShieldsListsUpdater::Abort(const std::string& reason) {
  // Les fichiers déjà installés pour cette tentative ne sont référencés par
  // rien : le ménage du prochain démarrage les retire.
  LOG(WARNING) << "[Browther] Listes Shields : mise à jour abandonnée — "
               << reason << ".";
  loader_.reset();
  pending_.reset();
  to_download_.clear();
}

void ShieldsListsUpdater::PersistAndActivate(ActiveSet set) {
  local_state_->SetDict(prefs::kActiveSet, set.ToDict());
  ActiveLists::GetInstance()->SetActiveSet(std::move(set));
}

void ShieldsListsUpdater::CleanupUnreferenced(const ActiveSet& keep_a,
                                              const ActiveSet& keep_b,
                                              bool purge_downloads) {
  const base::FilePath& root = ActiveLists::GetInstance()->root();
  std::set<base::FilePath> keep;
  for (const ActiveSet* set : {&keep_a, &keep_b}) {
    for (const auto& [path, file] : set->files) {
      keep.insert(root.AppendASCII(DirNameOf(path)).AppendASCII(file.dir));
    }
  }
  file_task_runner_->PostTask(
      FROM_HERE, base::BindOnce(&DeleteUnreferenced, root, std::move(keep),
                                purge_downloads));
}

}  // namespace browther_shields_lists
