// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BROWTHER_SHIELDS_LISTS_SHIELDS_LISTS_UPDATER_H_
#define BRAVE_COMPONENTS_BROWTHER_SHIELDS_LISTS_SHIELDS_LISTS_UPDATER_H_

#include <memory>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "base/files/file_path.h"
#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/task/sequenced_task_runner.h"
#include "base/timer/timer.h"
#include "brave/components/browther_shields_lists/active_lists.h"
#include "brave/components/browther_shields_lists/signed_manifest.h"

class PrefService;

namespace network {
class SharedURLLoaderFactory;
class SimpleURLLoader;
}  // namespace network

namespace browther_shields_lists {

// Met à jour les listes Shields sans release : lit l'index signé publié sur
// browther-download.devndin.com/shields/v1/, télécharge les fichiers qui ont
// changé, vérifie leur empreinte, puis bascule ActiveLists — les providers
// rechargent le moteur à chaud.
//
// Brave fait la même chose avec son component updater, mais son serveur exige
// une clé privée que seuls ses builds officiels embarquent (HTTP 403 pour nous).
// Voir private/docs/SHIELDS_BUNDLE.md § « Mise à jour à chaud ».
//
// Règle de fraîcheur : on garde toujours le plus récent entre le bundle de
// l'app (bundle_version.txt) et l'ensemble téléchargé. Une mise à jour de l'app
// qui embarque des listes plus fraîches reprend donc la main toute seule, même
// si la publication s'est arrêtée.
class ShieldsListsUpdater {
 public:
  using URLLoaderFactoryGetter =
      base::RepeatingCallback<scoped_refptr<network::SharedURLLoaderFactory>()>;

  // `bundled_root` : le dossier adblock_lists/ du bundle (pour sa version).
  // `local_state` doit survivre à l'objet. ActiveLists doit avoir été
  // initialisé (LoadActiveListsFromPrefs).
  ShieldsListsUpdater(PrefService* local_state,
                      const base::FilePath& bundled_root,
                      URLLoaderFactoryGetter url_loader_factory_getter);
  ~ShieldsListsUpdater();
  ShieldsListsUpdater(const ShieldsListsUpdater&) = delete;
  ShieldsListsUpdater& operator=(const ShieldsListsUpdater&) = delete;

  // Contrôle l'ensemble actif sur disque, puis vérifie les mises à jour après
  // un délai, et ensuite à intervalle régulier.
  void Start();

  struct StartupCheck {
    StartupCheck();
    StartupCheck(StartupCheck&&);
    StartupCheck& operator=(StartupCheck&&);
    ~StartupCheck();

    std::string bundled_version;
    // Fichiers de l'ensemble actif manquants ou altérés sur disque.
    std::set<std::string> broken_files;
  };

 private:
  void OnStartupChecked(StartupCheck check);
  void CheckForUpdate();
  void OnManifestDownloaded(std::optional<std::string> body);
  void DownloadNext();
  void OnFileDownloaded(base::FilePath downloaded);
  void OnFileInstalled(bool ok);
  void Commit();
  void Abort(const std::string& reason);
  void PersistAndActivate(ActiveSet set);
  void CleanupUnreferenced(const ActiveSet& keep_a,
                           const ActiveSet& keep_b,
                           bool purge_downloads);
  // Le plus récent de la version du bundle et de celle de l'ensemble actif.
  std::string CurrentVersion() const;

  const raw_ptr<PrefService> local_state_;
  const base::FilePath bundled_root_;
  URLLoaderFactoryGetter url_loader_factory_getter_;
  std::string base_url_;
  std::string bundled_version_;
  // Un fichier de l'ensemble actif était manquant ou altéré au démarrage : on
  // accepte de re-télécharger le même index (sinon il faudrait attendre une
  // nouvelle publication pour le récupérer).
  bool repair_needed_ = false;

  base::OneShotTimer startup_timer_;
  base::RepeatingTimer periodic_timer_;
  scoped_refptr<base::SequencedTaskRunner> file_task_runner_;

  // Mise à jour en cours.
  std::unique_ptr<network::SimpleURLLoader> loader_;
  std::optional<ActiveSet> pending_;
  std::vector<std::string> to_download_;
  int downloaded_count_ = 0;

  base::WeakPtrFactory<ShieldsListsUpdater> weak_factory_{this};
};

}  // namespace browther_shields_lists

#endif  // BRAVE_COMPONENTS_BROWTHER_SHIELDS_LISTS_SHIELDS_LISTS_UPDATER_H_
