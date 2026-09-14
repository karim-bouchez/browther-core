/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_BROWSER_UI_WEBUI_WELCOME_PAGE_BROWTHER_INTRO_SYSTEM_VOLUME_H_
#define BRAVE_BROWSER_UI_WEBUI_WELCOME_PAGE_BROWTHER_INTRO_SYSTEM_VOLUME_H_

#include <optional>

// Le son de l'ORDINATEUR, pour l'écran Musique de l'introduction.
//
// L'extrait peut jouer sans qu'on entende rien (Mac en sourdine, volume à
// zéro) : l'écran doit le dire plutôt que de laisser croire à une panne
// (ONBOARDING-SPEC.md § 4.4). Une page web ne peut ni lire ni régler ce niveau,
// d'où ce passage par le navigateur.
namespace browther_intro {

struct SystemVolume {
  // 0…1. Absent si la sortie n'a pas de réglage de volume (certains écrans
  // HDMI, interfaces audio) : l'écran masque alors la jauge.
  std::optional<double> level;
  bool muted = false;
};

// Sortie audio par défaut. `std::nullopt` hors macOS et Windows, ou si la
// sortie est introuvable.
std::optional<SystemVolume> GetSystemVolume();

// Règle le niveau (0…1) de la sortie par défaut et retire la sourdine si le
// niveau est non nul : monter le curseur doit rendre le son audible.
void SetSystemVolume(double level);

}  // namespace browther_intro

#endif  // BRAVE_BROWSER_UI_WEBUI_WELCOME_PAGE_BROWTHER_INTRO_SYSTEM_VOLUME_H_
