/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_COMPONENTS_NTP_BACKGROUND_IMAGES_BROWSER_BROWTHER_BACKGROUNDS_APK_EXTRACTOR_H_
#define BRAVE_COMPONENTS_NTP_BACKGROUND_IMAGES_BROWSER_BROWTHER_BACKGROUNDS_APK_EXTRACTOR_H_

#include "build/build_config.h"

#if BUILDFLAG(IS_ANDROID)

namespace ntp_background_images {

// Browther: Sur Android, les 10 paysages islamiques NTP sont bundlés dans
// l'APK comme android_assets (cf. browther_backgrounds_mobile/BUILD.gn).
// NTPBackgroundImagesService attend un FilePath sur disque pour parser
// photo.json et servir les .jpg via file://, donc on extrait les assets
// vers DIR_USER_DATA/browther_backgrounds_mobile/ au premier boot.
//
// Idempotent : skip si DIR_USER_DATA/browther_backgrounds_mobile/photo.json
// existe déjà (sentinelle d'extraction réussie, extraite en dernier pour
// garantir l'atomicité — si le boot crashe au milieu, on re-extraira tout
// au prochain boot).
//
// À appeler une fois au browser process startup, AVANT que le
// NTPBackgroundImagesService ne lise le dossier (cf.
// BraveBrowserMainParts). Bloquant — n'utiliser que dans un contexte où
// le blocking I/O est autorisé (early init).
void EnsureBrowtherBackgroundsExtracted();

}  // namespace ntp_background_images

#endif  // BUILDFLAG(IS_ANDROID)

#endif  // BRAVE_COMPONENTS_NTP_BACKGROUND_IMAGES_BROWSER_BROWTHER_BACKGROUNDS_APK_EXTRACTOR_H_
