// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BROWTHER_SHIELDS_LISTS_ACTIVE_LISTS_H_
#define BRAVE_COMPONENTS_BROWTHER_SHIELDS_LISTS_ACTIVE_LISTS_H_

#include <cstdint>
#include <string>
#include <string_view>

#include "base/callback_list.h"
#include "base/containers/flat_map.h"
#include "base/files/file_path.h"
#include "base/functional/callback.h"
#include "base/no_destructor.h"
#include "base/values.h"

class PrefRegistrySimple;
class PrefService;

namespace browther_shields_lists {

// Un fichier de l'ensemble téléchargé actif.
struct ActiveFile {
  std::string sha256;
  int64_t size = 0;
  // Le fichier vit dans <racine>/<dossier du composant>/<dir>/. `dir` est la
  // version de l'index qui l'a APPORTÉ : un fichier inchangé garde son dossier
  // d'une mise à jour à l'autre. C'est important sur iOS, où Brave prend ce nom
  // de dossier pour la version de la liste et ne recompile que s'il change.
  std::string dir;
};

// L'ensemble téléchargé actif. `version` vide = aucun : tout vient du bundle.
struct ActiveSet {
  ActiveSet();
  ActiveSet(const ActiveSet&);
  ActiveSet& operator=(const ActiveSet&);
  ActiveSet(ActiveSet&&);
  ActiveSet& operator=(ActiveSet&&);
  ~ActiveSet();

  base::DictValue ToDict() const;
  // Ignore toute entrée malformée (pref corrompue) plutôt que de la suivre.
  static ActiveSet FromDict(const base::DictValue& dict);

  std::string version;
  // Clé : chemin relatif publié (« <component_id>/list.txt »…).
  base::flat_map<std::string, ActiveFile> files;
};

// Les listes téléchargées que les providers Shields doivent charger à la place
// de celles du bundle. En mémoire, thread UI uniquement : les providers le
// lisent dans leur constructeur, où l'accès disque est interdit.
class ActiveLists {
 public:
  static ActiveLists* GetInstance();

  ActiveLists(const ActiveLists&) = delete;
  ActiveLists& operator=(const ActiveLists&) = delete;

  // Dossier à charger pour `dir_name` (un component_id, ou kResourcesDir), ou
  // chemin vide si l'ensemble actif ne le fournit pas : le provider garde
  // alors la liste du bundle.
  base::FilePath GetDownloadedDir(std::string_view dir_name) const;

  // Prévient (les providers) à chaque changement de l'ensemble actif.
  base::CallbackListSubscription RegisterChangedCallback(
      base::RepeatingClosure callback);

  const ActiveSet& active_set() const { return set_; }
  const base::FilePath& root() const { return root_; }

  // Démarrage : pose la racine et l'ensemble lu dans les prefs, sans prévenir
  // personne (aucun provider n'existe encore).
  void Initialize(const base::FilePath& root, ActiveSet set);
  // Remplace l'ensemble actif et prévient les providers.
  void SetActiveSet(ActiveSet set);

 private:
  friend class base::NoDestructor<ActiveLists>;
  ActiveLists();
  ~ActiveLists();

  base::FilePath root_;
  ActiveSet set_;
  base::RepeatingClosureList callbacks_;
};

// <root>/<dossier du composant>/<dir>/<fichier> pour un chemin relatif publié.
base::FilePath GetActiveFilePath(const base::FilePath& root,
                                 std::string_view relative_path,
                                 std::string_view dir);

void RegisterLocalStatePrefs(PrefRegistrySimple* registry);

// À appeler AVANT de construire les providers Shields.
// `download_root` : dossier propre aux listes téléchargées, dans les données de
// l'app (jamais dans le bundle, qui est signé et en lecture seule).
void LoadActiveListsFromPrefs(PrefService* local_state,
                              const base::FilePath& download_root);

}  // namespace browther_shields_lists

#endif  // BRAVE_COMPONENTS_BROWTHER_SHIELDS_LISTS_ACTIVE_LISTS_H_
