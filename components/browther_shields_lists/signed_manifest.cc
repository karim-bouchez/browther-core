// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/browther_shields_lists/signed_manifest.h"

#include <array>
#include <utility>
#include <vector>

#include "base/base64.h"
#include "base/containers/span.h"
#include "base/json/json_reader.h"
#include "base/strings/strcat.h"
#include "base/strings/string_util.h"
#include "base/values.h"
#include "crypto/keypair.h"
#include "crypto/sign.h"

namespace browther_shields_lists {

namespace {

// Clé publique Ed25519 des listes publiées. La clé privée vit dans le Trousseau
// macOS de Karim (« browther-shields-lists-signing ») et dans le secret GitHub
// SHIELDS_SIGNING_KEY de browther-private. Doit rester identique à
// PUBLIC_KEY_B64 de private/scripts/publish-shields-lists.py
// (QQJBur/Pss5Q7gF+2P0clNwiv3nvXHop3ypPIKQjnMQ=).
// ⚠️ Changer de clé = les apps déjà installées refusent tout jusqu'à leur
// prochaine mise à jour : elles retombent sur leurs listes embarquées.
constexpr std::array<uint8_t, 32> kPublicKey = {
    0x41, 0x02, 0x41, 0xba, 0xbf, 0xcf, 0xb2, 0xce, 0x50, 0xee, 0x01,
    0x7e, 0xd8, 0xfd, 0x1c, 0x94, 0xdc, 0x22, 0xbf, 0x79, 0xef, 0x5c,
    0x7a, 0x29, 0xdf, 0x2a, 0x4f, 0x20, 0xa4, 0x23, 0x9c, 0xc4};

constexpr int kManifestFormat = 1;
constexpr size_t kComponentIdLength = 32;
constexpr size_t kMaxFiles = 64;
// La plus grosse liste connue (l'ancienne source de « Porn blocker ») pesait
// 11,9 Mo ; la liste par défaut en fait 5,2.
constexpr int64_t kMaxFileSize = 32 * 1024 * 1024;
constexpr size_t kSignatureLength = 64;

constexpr char kListFile[] = "list.txt";
constexpr char kResourcesPath[] = "_resources/resources.json";

bool IsComponentId(std::string_view value) {
  if (value.size() != kComponentIdLength) {
    return false;
  }
  for (char c : value) {
    if (c < 'a' || c > 'p') {
      return false;
    }
  }
  return true;
}

}  // namespace

Manifest::Manifest() = default;
Manifest::Manifest(const Manifest&) = default;
Manifest& Manifest::operator=(const Manifest&) = default;
Manifest::Manifest(Manifest&&) = default;
Manifest& Manifest::operator=(Manifest&&) = default;
Manifest::~Manifest() = default;

bool IsValidVersion(std::string_view version) {
  if (version.size() != 14) {
    return false;
  }
  for (char c : version) {
    if (!base::IsAsciiDigit(c)) {
      return false;
    }
  }
  return true;
}

bool IsValidSha256(std::string_view hex) {
  if (hex.size() != 64) {
    return false;
  }
  for (char c : hex) {
    if (!base::IsAsciiDigit(c) && (c < 'a' || c > 'f')) {
      return false;
    }
  }
  return true;
}

bool IsValidRelativePath(std::string_view path) {
  if (path == kResourcesPath) {
    return true;
  }
  return path.size() == kComponentIdLength + 1 + sizeof(kListFile) - 1 &&
         IsComponentId(path.substr(0, kComponentIdLength)) &&
         path[kComponentIdLength] == '/' &&
         path.substr(kComponentIdLength + 1) == kListFile;
}

std::string_view DirNameOf(std::string_view relative_path) {
  return relative_path.substr(0, relative_path.find('/'));
}

std::string RelativePathForDir(std::string_view dir_name) {
  if (dir_name == kResourcesDir) {
    return kResourcesPath;
  }
  return base::StrCat({dir_name, "/", kListFile});
}

std::optional<Manifest> ParseSignedManifestForTesting(
    std::string_view envelope_json,
    base::span<const uint8_t, 32> public_key) {
  std::optional<base::DictValue> envelope =
      base::JSONReader::ReadDict(envelope_json, base::JSON_PARSE_RFC);
  if (!envelope) {
    return std::nullopt;
  }
  const std::string* manifest_json = envelope->FindString("manifest");
  const std::string* signature_b64 = envelope->FindString("signature");
  if (!manifest_json || !signature_b64) {
    return std::nullopt;
  }
  std::optional<std::vector<uint8_t>> signature =
      base::Base64Decode(*signature_b64);
  if (!signature || signature->size() != kSignatureLength) {
    return std::nullopt;
  }
  // La signature porte sur les octets exacts de la chaîne « manifest » : pas
  // de canonicalisation JSON à reproduire des deux côtés.
  if (!crypto::sign::Verify(
          crypto::sign::ED25519,
          crypto::keypair::PublicKey::FromEd25519PublicKey(public_key),
          base::as_byte_span(*manifest_json), *signature)) {
    return std::nullopt;
  }

  std::optional<base::DictValue> dict =
      base::JSONReader::ReadDict(*manifest_json, base::JSON_PARSE_RFC);
  if (!dict || dict->FindInt("format") != kManifestFormat) {
    return std::nullopt;
  }
  const std::string* version = dict->FindString("version");
  const base::DictValue* files = dict->FindDict("files");
  if (!version || !IsValidVersion(*version) || !files || files->empty() ||
      files->size() > kMaxFiles) {
    return std::nullopt;
  }

  Manifest manifest;
  manifest.version = *version;
  for (const auto [path, value] : *files) {
    const base::DictValue* file = value.GetIfDict();
    if (!IsValidRelativePath(path) || !file) {
      return std::nullopt;
    }
    const std::string* sha256 = file->FindString("sha256");
    const std::optional<int> size = file->FindInt("size");
    if (!sha256 || !IsValidSha256(*sha256) || !size || *size <= 0 ||
        *size > kMaxFileSize) {
      return std::nullopt;
    }
    manifest.files.emplace(path, ManifestFile{*sha256, *size});
  }
  return manifest;
}

std::optional<Manifest> ParseSignedManifest(std::string_view envelope_json) {
  return ParseSignedManifestForTesting(envelope_json, kPublicKey);
}

}  // namespace browther_shields_lists
