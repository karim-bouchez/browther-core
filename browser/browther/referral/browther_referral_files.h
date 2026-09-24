// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_FILES_H_
#define BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_FILES_H_

#include <string>
#include <string_view>

namespace content {
class WebUIDataSource;
}

// L'app web du parrainage (React, `private/webui/referral/`) est servie DEPUIS
// LE DISQUE, comme les extensions Basarunaa et Sawtunaa — ⛔ pas empaquetée par
// grit. ⭐ Retoucher l'interface = reconstruire l'app et recharger la page, sans
// rebuild Chromium (≈ 30 min à chaque fois sur le Mac de 16 Go, cf.
// `feedback_ui_preview_before_long_build`).
//
// Où elle vit :
//   1. `--browther-referral-path=<dossier>` (dev : pointer directement sur
//      `private/webui/referral/dist`) ;
//   2. `DIR_EXE/browther_referral/` (builds de dev, Windows) ;
//   3. macOS : `Browther.app/Contents/Resources/browther_referral/` (Release
//      signée : le sceau couvre Resources/, pas MacOS/).
namespace browther_referral {

// Sert les requêtes `<prefix><fichier>` de `source` depuis le dossier de l'app.
// `prefix` vide = toute la source (l'écran Parrainage, dont `index.html` est la
// page par défaut) ; `"browther-referral/"` pour les pages qui l'accueillent
// (Nouvel Onglet, introduction).
void AddAppFiles(content::WebUIDataSource* source, const std::string& prefix);

// Le libellé de l'entrée « Parrainage » du menu ⋯ — la clé `home.title` des
// textes de l'app, dans la langue de Browther. ⭐ Pas de chaîne grit : les
// textes du parrainage n'ont qu'UN pool (celui de l'iOS, repris par le
// desktop), et un `IDS_` de plus recompilerait ~300 fichiers. Lu une fois, sur
// un fil bloquant, dès le premier onglet (`PreloadMenuLabel`) ; d'ici là, et si
// l'app n'est pas déployée, un repli intégré (fr / ar / en).
void PreloadMenuLabel();

// Le menu ⋯ porte le GESTE (« Inviter un proche sur Browther »), les Paramètres
// le NOM de la rubrique (« Parrainage ») — leur rail n'aligne que des noms d'un
// ou deux mots, et c'est déjà le partage retenu sur iOS (Karim, 2026-09-23).
std::u16string MenuLabel();
std::u16string SettingsTitle();

// ⭐ Un texte de l'app, pour le NATIF (⛔ pas une chaîne grit, cf. ci-dessus) :
//   `kMenuSubtitle`   la 2ᵉ ligne de l'entrée du menu — sans elle, le libellé
//                     seul ne dit pas ce qu'on y gagne et l'entrée se noie dans
//                     un menu de fonctions (recette Karim, 2026-09-23) ;
//   `kPausedStatus` / `kPausedBody` / `kPausedCta`  ce que la popup Sawtunaa
//                     dit quand le retrait de la musique est en pause : l'état
//                     sous l'interrupteur, le pourquoi, l'action.
// ⚠️ **Vide** tant que les textes ne sont pas lus, ou si la langue ne les a
// pas : l'appelant se tait alors, ⛔ il n'affiche pas un trou.
inline constexpr std::string_view kMenuLabel = "menu.label";
inline constexpr std::string_view kSettingsTitle = "home.title";
inline constexpr std::string_view kMenuSubtitle = "settings.subtitle";
inline constexpr std::string_view kPausedStatus = "features.paused";
inline constexpr std::string_view kPausedBody = "locked.musicRemoval";
// ⚠️ « Débloquer », ⛔ pas « Soutenir dev&din » : depuis la popup d'une
// fonctionnalité bloquée, c'est le RÉSULTAT qui parle (Karim, 2026-09-24).
inline constexpr std::string_view kPausedCta = "locked.unlock";
std::u16string Text(std::string_view key);

}  // namespace browther_referral

#endif  // BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_FILES_H_
