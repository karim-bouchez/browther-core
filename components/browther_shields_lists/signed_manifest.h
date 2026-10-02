// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BROWTHER_SHIELDS_LISTS_SIGNED_MANIFEST_H_
#define BRAVE_COMPONENTS_BROWTHER_SHIELDS_LISTS_SIGNED_MANIFEST_H_

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

#include "base/containers/flat_map.h"
#include "base/containers/span.h"

namespace browther_shields_lists {

// Dossier des scriptlets, homonyme de celui du bundle (adblock_lists/_resources/).
inline constexpr char kResourcesDir[] = "_resources";

struct ManifestFile {
  std::string sha256;  // hexadécimal minuscule
  int64_t size = 0;
};

// L'index publié par private/scripts/publish-shields-lists.py.
struct Manifest {
  Manifest();
  Manifest(const Manifest&);
  Manifest& operator=(const Manifest&);
  Manifest(Manifest&&);
  Manifest& operator=(Manifest&&);
  ~Manifest();

  // Horodatage UTC AAAAMMJJHHMMSS de la génération des listes : comparable
  // comme une chaîne, et au même format que bundle_version.txt du bundle.
  std::string version;
  // Clé : chemin relatif (« <component_id>/list.txt », « _resources/resources.json »).
  base::flat_map<std::string, ManifestFile> files;
};

bool IsValidVersion(std::string_view version);
bool IsValidSha256(std::string_view hex);
// N'accepte QUE les deux formes publiées : le chemin sert à construire un
// chemin disque, rien d'autre ne doit passer (pas de « .. », pas de « / » en tête).
bool IsValidRelativePath(std::string_view path);

// « <component_id>/list.txt » → « <component_id> » ; « _resources/… » → « _resources ».
std::string_view DirNameOf(std::string_view relative_path);
// Inverse de DirNameOf.
std::string RelativePathForDir(std::string_view dir_name);

// Vérifie la signature Ed25519 de l'enveloppe
// {"manifest": "<json>", "signature": "<base64>"} avec la clé publique
// embarquée, puis lit l'index. nullopt au moindre écart : signature, format,
// version, chemin, empreinte ou taille.
std::optional<Manifest> ParseSignedManifest(std::string_view envelope_json);
std::optional<Manifest> ParseSignedManifestForTesting(
    std::string_view envelope_json,
    base::span<const uint8_t, 32> public_key);

}  // namespace browther_shields_lists

#endif  // BRAVE_COMPONENTS_BROWTHER_SHIELDS_LISTS_SIGNED_MANIFEST_H_
