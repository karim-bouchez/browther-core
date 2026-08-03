// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/basarunaa/core/basarunaa_features.h"

// Gardés volontairement : servent au bloc de reverrouillage commenté dans
// IsBasarunaaDebugUiEnabled(). Ne pas retirer en « nettoyant les includes ».
#include "base/command_line.h"
#include "build/build_config.h"

namespace basarunaa {

BASE_FEATURE(kBasarunaaVideoDecodeAhead,
             "BasarunaaVideoDecodeAhead",
             base::FEATURE_ENABLED_BY_DEFAULT);

// ⚠️ OUVERT EN RELEASE PENDANT LA PHASE DE TEST (décision Karim, 2026-08-03).
//
// Pourquoi : les DMG distribués aujourd'hui vont à des testeurs (Karim + proches),
// pas à des utilisateurs finaux. Sans les réglages de debug, un testeur ne peut
// ni régler les seuils ni COUPER le mode capture — et une pref `capture_mode`
// restée à true dans son profil devient impossible à éteindre depuis l'UI, ce
// qui télécharge une image annotée à chaque analyse (constaté sur 2026.7.31).
//
// ⚠️ À REVERROUILLER AVANT LA DISTRIBUTION GRAND PUBLIC : remettre le
// `#if defined(OFFICIAL_BUILD)` ci-dessous. C'est de l'outillage, pas une
// feature — un utilisateur final n'a rien à y faire.
//
// ⚠️ NE COUVRE PAS le dump de frames VIDÉO : `SaveCaptureRaw` /
// `RenderAnnotatedCaptureOnUI` restent compilés HORS du binaire Release
// (`#if !defined(OFFICIAL_BUILD)` dans basarunaa_image_analyzer.cc). C'est un
// prérequis du dossier Widevine VMP — le binaire distribué ne doit à aucun
// moment pouvoir écrire des pixels de flux protégé sur disque. En Release, le
// mode capture ne produit donc que les images de pages web (côté extension
// MV3), jamais de frames vidéo. Ne pas « harmoniser » les deux gates.
bool IsBasarunaaDebugUiEnabled() {
  // Réactiver ce bloc pour le grand public (cf. commentaire ci-dessus) :
  //
  // #if defined(OFFICIAL_BUILD)
  //   return base::CommandLine::ForCurrentProcess()->HasSwitch(
  //       "basarunaa-debug-ui");
  // #else
  //   return true;
  // #endif
  return true;
}

}  // namespace basarunaa
