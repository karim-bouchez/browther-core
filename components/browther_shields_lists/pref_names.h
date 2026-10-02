// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BROWTHER_SHIELDS_LISTS_PREF_NAMES_H_
#define BRAVE_COMPONENTS_BROWTHER_SHIELDS_LISTS_PREF_NAMES_H_

namespace browther_shields_lists::prefs {

// Local state. L'ensemble de listes téléchargé actif (cf. ActiveSet::ToDict) :
//   {"version": "20261002202801",
//    "files": {"<component_id>/list.txt": {"sha256": "…", "size": 123,
//                                          "dir": "20261002202801"}, …}}
// Lu de façon synchrone au démarrage, avant la construction des providers
// Shields — c'est pour ça que ce n'est pas un fichier.
inline constexpr char kActiveSet[] = "browther.shields_lists.active_set";

}  // namespace browther_shields_lists::prefs

#endif  // BRAVE_COMPONENTS_BROWTHER_SHIELDS_LISTS_PREF_NAMES_H_
