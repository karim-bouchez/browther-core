// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/browther_shields_lists/active_lists.h"

#include <utility>

#include "brave/components/browther_shields_lists/pref_names.h"
#include "brave/components/browther_shields_lists/signed_manifest.h"
#include "components/prefs/pref_registry_simple.h"
#include "components/prefs/pref_service.h"

namespace browther_shields_lists {

namespace {

constexpr char kVersionKey[] = "version";
constexpr char kFilesKey[] = "files";
constexpr char kSha256Key[] = "sha256";
constexpr char kSizeKey[] = "size";
constexpr char kDirKey[] = "dir";

}  // namespace

ActiveSet::ActiveSet() = default;
ActiveSet::ActiveSet(const ActiveSet&) = default;
ActiveSet& ActiveSet::operator=(const ActiveSet&) = default;
ActiveSet::ActiveSet(ActiveSet&&) = default;
ActiveSet& ActiveSet::operator=(ActiveSet&&) = default;
ActiveSet::~ActiveSet() = default;

base::DictValue ActiveSet::ToDict() const {
  base::DictValue files_dict;
  for (const auto& [path, file] : files) {
    files_dict.Set(path, base::DictValue()
                             .Set(kSha256Key, file.sha256)
                             .Set(kSizeKey, static_cast<int>(file.size))
                             .Set(kDirKey, file.dir));
  }
  return base::DictValue()
      .Set(kVersionKey, version)
      .Set(kFilesKey, std::move(files_dict));
}

// static
ActiveSet ActiveSet::FromDict(const base::DictValue& dict) {
  ActiveSet set;
  const std::string* version = dict.FindString(kVersionKey);
  const base::DictValue* files = dict.FindDict(kFilesKey);
  if (!version || !IsValidVersion(*version) || !files) {
    return set;
  }
  for (const auto [path, value] : *files) {
    const base::DictValue* file = value.GetIfDict();
    if (!file || !IsValidRelativePath(path)) {
      continue;
    }
    const std::string* sha256 = file->FindString(kSha256Key);
    const std::optional<int> size = file->FindInt(kSizeKey);
    const std::string* dir = file->FindString(kDirKey);
    if (!sha256 || !IsValidSha256(*sha256) || !size || !dir ||
        !IsValidVersion(*dir)) {
      continue;
    }
    set.files.emplace(path, ActiveFile{*sha256, *size, *dir});
  }
  if (!set.files.empty()) {
    set.version = *version;
  }
  return set;
}

// static
ActiveLists* ActiveLists::GetInstance() {
  static base::NoDestructor<ActiveLists> instance;
  return instance.get();
}

ActiveLists::ActiveLists() = default;
ActiveLists::~ActiveLists() = default;

base::FilePath ActiveLists::GetDownloadedDir(std::string_view dir_name) const {
  if (root_.empty()) {
    return base::FilePath();
  }
  auto it = set_.files.find(RelativePathForDir(dir_name));
  if (it == set_.files.end()) {
    return base::FilePath();
  }
  return root_.AppendASCII(dir_name).AppendASCII(it->second.dir);
}

base::FilePath GetActiveFilePath(const base::FilePath& root,
                                 std::string_view relative_path,
                                 std::string_view dir) {
  const size_t slash = relative_path.find('/');
  return root.AppendASCII(DirNameOf(relative_path))
      .AppendASCII(dir)
      .AppendASCII(relative_path.substr(slash + 1));
}

base::CallbackListSubscription ActiveLists::RegisterChangedCallback(
    base::RepeatingClosure callback) {
  return callbacks_.Add(std::move(callback));
}

void ActiveLists::Initialize(const base::FilePath& root, ActiveSet set) {
  root_ = root;
  set_ = std::move(set);
}

void ActiveLists::SetActiveSet(ActiveSet set) {
  set_ = std::move(set);
  callbacks_.Notify();
}

void RegisterLocalStatePrefs(PrefRegistrySimple* registry) {
  registry->RegisterDictionaryPref(prefs::kActiveSet);
}

void LoadActiveListsFromPrefs(PrefService* local_state,
                              const base::FilePath& download_root) {
  ActiveLists::GetInstance()->Initialize(
      download_root,
      ActiveSet::FromDict(local_state->GetDict(prefs::kActiveSet)));
}

}  // namespace browther_shields_lists
