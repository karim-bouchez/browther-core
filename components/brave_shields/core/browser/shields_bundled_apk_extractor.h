/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_COMPONENTS_BRAVE_SHIELDS_CORE_BROWSER_SHIELDS_BUNDLED_APK_EXTRACTOR_H_
#define BRAVE_COMPONENTS_BRAVE_SHIELDS_CORE_BROWSER_SHIELDS_BUNDLED_APK_EXTRACTOR_H_

#include "build/build_config.h"

#if BUILDFLAG(IS_ANDROID)

namespace brave_shields {

// Browther: Sur Android, les filter lists Shields sont bundlées dans
// l'APK comme android_assets. Comme adblock-rust + le code Brave attend
// un FilePath du filesystem (pas un memory-mapped APK asset), on extrait
// les assets vers DIR_USER_DATA/adblock_lists/ au premier boot.
//
// Idempotent : skip si DIR_USER_DATA/adblock_lists/list_catalog.json
// existe déjà (sentinelle d'extraction réussie).
//
// À appeler une fois au browser process startup, AVANT l'instanciation
// de AdBlockService (cf. BraveBrowserMainParts::PreCreateThreads ou
// PostCreateThreads). Bloquant — n'utiliser que dans un contexte où le
// blocking I/O est autorisé (early init).
//
// Voir private/docs/SHIELDS_BUNDLE.md.
void EnsureBundledShieldsExtracted();

}  // namespace brave_shields

#endif  // BUILDFLAG(IS_ANDROID)

#endif  // BRAVE_COMPONENTS_BRAVE_SHIELDS_CORE_BROWSER_SHIELDS_BUNDLED_APK_EXTRACTOR_H_
