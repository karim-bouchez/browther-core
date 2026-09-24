// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/browther/referral/browther_referral_files.h"

#include <array>
#include <optional>
#include <string_view>
#include <utility>

#include "base/command_line.h"
#include "base/containers/flat_map.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/json/json_reader.h"
#include "base/memory/ref_counted_memory.h"
#include "base/no_destructor.h"
#include "base/path_service.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/thread_pool.h"
#include "base/values.h"
#include "build/build_config.h"
#include "chrome/browser/browser_process.h"
#include "content/public/browser/web_ui_data_source.h"

#if BUILDFLAG(IS_MAC)
#include "base/apple/bundle_locations.h"
#endif

namespace browther_referral {

namespace {

constexpr char kSwitch[] = "browther-referral-path";
constexpr char kDirName[] = "browther_referral";
// L'app entière (JS, CSS, textes d'UNE langue) pèse quelques centaines de Ko :
// au-delà, ce n'est pas un fichier à nous.
constexpr int64_t kMaxFileSize = 8 * 1024 * 1024;

// ⛔ Rien qui sorte du dossier : pas de `..`, pas de chemin absolu, un alphabet
// fermé (les fichiers de l'app n'ont que ça).
bool IsSafeRelativePath(std::string_view path) {
  if (path.empty() || path.size() > 200 || path[0] == '/' ||
      path.find("..") != std::string_view::npos) {
    return false;
  }
  for (char c : path) {
    if (!base::IsAsciiAlphaNumeric(c) && c != '.' && c != '-' && c != '_' &&
        c != '/') {
      return false;
    }
  }
  return true;
}

std::string StripQuery(const std::string& path) {
  const size_t cut = path.find_first_of("?#");
  return cut == std::string::npos ? path : path.substr(0, cut);
}

/**
 * 🔴 Où vit l'app — ⚠️ **sur un fil BLOQUANT uniquement** : le repli macOS teste
 * l'existence d'un fichier, et un accès disque sur le fil de l'UI lève un
 * `DCHECK` en build de dev (vu le 2026-09-22 : le navigateur mourait à
 * l'ouverture de l'écran, mais seulement SANS `--browther-referral-path`, qui
 * court-circuite le test). Résolu **une seule fois** (statique de fonction,
 * initialisation déjà protégée) : le dossier ne bouge pas en cours de session.
 */
const base::FilePath& AppDir() {
  static base::NoDestructor<base::FilePath> dir([] {
    const base::CommandLine& command_line =
        *base::CommandLine::ForCurrentProcess();
    if (command_line.HasSwitch(kSwitch)) {
      return command_line.GetSwitchValuePath(kSwitch);
    }
    base::FilePath exe_dir;
    base::PathService::Get(base::DIR_EXE, &exe_dir);
    base::FilePath candidate = exe_dir.AppendASCII(kDirName);
#if BUILDFLAG(IS_MAC)
    if (!base::PathExists(candidate.AppendASCII("index.html"))) {
      return base::apple::OuterBundlePath()
          .Append("Contents")
          .Append("Resources")
          .AppendASCII(kDirName);
    }
#endif
    return candidate;
  }());
  return *dir;
}

scoped_refptr<base::RefCountedMemory> ReadAppFile(std::string relative) {
  const base::FilePath file = AppDir().AppendASCII(relative);
  std::optional<int64_t> size = base::GetFileSize(file);
  if (!size || *size > kMaxFileSize) {
    return nullptr;
  }
  std::string contents;
  if (!base::ReadFileToString(file, &contents)) {
    return nullptr;
  }
  return base::MakeRefCounted<base::RefCountedString>(std::move(contents));
}

// Les quelques textes de l'app dont le NATIF a besoin (menu ⋯, panneau
// Sawtunaa), lus ensemble : un seul fichier, une seule fois.
using NativeTexts = base::flat_map<std::string, std::u16string>;

NativeTexts& CachedTexts() {
  static base::NoDestructor<NativeTexts> texts;
  return *texts;
}

std::string PrimaryLanguage(const std::string& locale) {
  const size_t cut = locale.find_first_of("-_");
  return base::ToLowerASCII(cut == std::string::npos ? locale
                                                       : locale.substr(0, cut));
}

std::u16string FallbackMenuLabel(const std::string& locale) {
  const std::string language = PrimaryLanguage(locale);
  if (language == "fr") {
    return u"Inviter un proche sur Browther";
  }
  if (language == "ar") {
    // « ادعُ قريبًا إلى Browther », la clé `menu.invite` de `ar.json` (octets
    // recopiés, ⛔ pas retapés).
    return u"\u0627\u062F\u0639\u064F \u0642\u0631\u064A\u0628\u064B"
           u"\u0627 \u0625\u0644\u0649 Browther";
  }
  return u"Invite someone to Browther";
}

// ⚠️ Les Paramètres, eux, portent le NOM de la rubrique (« Parrainage ») : leur
// rail n'aligne que des noms d'un ou deux mots, et c'est déjà ce que fait la
// ligne des Réglages iOS (Karim, 2026-09-23). ⛔ Ne pas y remettre le geste.
std::u16string FallbackSettingsTitle(const std::string& locale) {
  const std::string language = PrimaryLanguage(locale);
  if (language == "fr") {
    return u"Parrainage";
  }
  if (language == "ar") {
    // « التزكية », la clé `home.title` de `ar.json` (octets recopiés, ⛔ pas
    // retapés).
    return u"\u0627\u0644\u062A\u0632\u0643\u064A\u0629";
  }
  return u"Referrals";
}

/**
 * ⭐ Le libellé des deux entrées (menu ⋯ et Paramètres) : le GESTE, ⛔ pas le
 * nom du dispositif — « Parrainage » ne donne envie à personne dans un menu
 * (Karim, 2026-09-23). `menu.invite` = « Inviter un proche sur Browther », le
 * MÊME texte que le menu « … » d'iOS (`BrowtherReferralEntries.swift`) : une
 * porte d'entrée qui se lit pareil sur les deux plateformes.
 *
 * ⚠️ Les 27 langues propres au desktop n'ont pas toutes `menu.invite` ; elles
 * retombent sur le bouton de l'annonce (« Inviter un proche »), puis sur le
 * titre de l'écran.
 */
constexpr auto kMenuLabelKeys = std::to_array<std::string_view>(
    {"menu.invite", "announce.invite", "home.title"});

// ⚠️ Chacune est FACULTATIVE : une langue qui ne l'a pas donne une chaîne vide,
// et l'appelant se tait plutôt que d'afficher un trou.
constexpr auto kOtherKeys = std::to_array<std::string_view>(
    {"home.title", "settings.subtitle", "features.paused",
     "locked.musicRemoval", "locked.unlock"});

// Les textes d'une langue : `i18n/<locale>.json`, sinon `i18n/<langue>.json`.
std::optional<NativeTexts> ReadNativeTexts(std::string locale) {
  const base::FilePath dir = AppDir();
  for (const std::string& name : {locale, PrimaryLanguage(locale)}) {
    std::string contents;
    const base::FilePath file =
        dir.AppendASCII("i18n").AppendASCII(name + ".json");
    if (!IsSafeRelativePath(name + ".json") ||
        !base::ReadFileToStringWithMaxSize(file, &contents, kMaxFileSize)) {
      continue;
    }
    std::optional<base::DictValue> texts =
        base::JSONReader::ReadDict(contents, base::JSON_PARSE_RFC);
    if (!texts) {
      continue;
    }
    NativeTexts found;
    for (std::string_view key : kMenuLabelKeys) {
      const std::string* title = texts->FindString(key);
      if (title && !title->empty()) {
        found[std::string(kMenuLabel)] = base::UTF8ToUTF16(*title);
        break;
      }
    }
    for (std::string_view key : kOtherKeys) {
      if (const std::string* value = texts->FindString(key);
          value && !value->empty()) {
        found[std::string(key)] = base::UTF8ToUTF16(*value);
      }
    }
    if (found.contains(std::string(kMenuLabel))) {
      return found;
    }
  }
  return std::nullopt;
}

}  // namespace

void AddAppFiles(content::WebUIDataSource* source, const std::string& prefix) {
  source->SetRequestFilter(
      base::BindRepeating(
          [](std::string prefix, const std::string& path) {
            return base::StartsWith(StripQuery(path), prefix);
          },
          prefix),
      base::BindRepeating(
          [](std::string prefix, const std::string& path,
             content::WebUIDataSource::GotDataCallback callback) {
            std::string relative = StripQuery(path).substr(prefix.size());
            if (relative.empty()) {
              relative = "index.html";
            }
            if (!IsSafeRelativePath(relative)) {
              std::move(callback).Run(nullptr);
              return;
            }
            // ⚠️ Lecture de fichier = fil bloquant, jamais celui de l'UI.
            base::ThreadPool::PostTaskAndReplyWithResult(
                FROM_HERE,
                {base::MayBlock(), base::TaskPriority::USER_BLOCKING},
                base::BindOnce(&ReadAppFile, std::move(relative)),
                std::move(callback));
          },
          prefix));
}

void PreloadMenuLabel() {
  static bool started = false;
  if (started || !g_browser_process) {
    return;
  }
  started = true;
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::BEST_EFFORT},
      base::BindOnce(&ReadNativeTexts,
                     g_browser_process->GetApplicationLocale()),
      base::BindOnce([](std::optional<NativeTexts> texts) {
        if (texts) {
          CachedTexts() = std::move(*texts);
        }
      }));
}

std::u16string MenuLabel() {
  if (std::u16string label = Text(kMenuLabel); !label.empty()) {
    return label;
  }
  return FallbackMenuLabel(
      g_browser_process ? g_browser_process->GetApplicationLocale() : "en");
}

std::u16string SettingsTitle() {
  if (std::u16string title = Text(kSettingsTitle); !title.empty()) {
    return title;
  }
  return FallbackSettingsTitle(
      g_browser_process ? g_browser_process->GetApplicationLocale() : "en");
}

std::u16string Text(std::string_view key) {
  const auto it = CachedTexts().find(std::string(key));
  return it == CachedTexts().end() ? std::u16string() : it->second;
}

}  // namespace browther_referral
