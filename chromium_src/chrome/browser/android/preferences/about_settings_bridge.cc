/* Copyright (c) 2019 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

#include "base/android/apk_info.h"
#include "base/android/jni_string.h"
#include "brave/components/version_info/version_info.h"
#include "chrome/android/chrome_jni_headers/AboutSettingsBridge_jni.h"

#define JNI_AboutSettingsBridge_GetApplicationVersion \
  JNI_AboutSettingsBridge_GetApplicationVersion_ChromiumImpl
// Suppress DEFINE_JNI in included file - we call it ourselves at the end
#pragma push_macro("DEFINE_JNI")
#undef DEFINE_JNI
#define DEFINE_JNI(...)
#include <chrome/browser/android/preferences/about_settings_bridge.cc>
#undef DEFINE_JNI
#pragma pop_macro("DEFINE_JNI")
#undef JNI_AboutSettingsBridge_GetApplicationVersion

static std::string JNI_AboutSettingsBridge_GetApplicationVersion(JNIEnv* env) {
  JNI_AboutSettingsBridge_GetApplicationVersion_ChromiumImpl(env);

  // Browther : même présentation que la carte « Version » d'iOS —
  //   Browther 2026.9.21
  //   BraveCore 1.90.0 (146.0.7680.164)
  // La 1re ligne porte notre CalVer (versionName de l'APK, posé par
  // build-android-remote.sh via --android_override_version_name) : c'est le
  // numéro que l'utilisateur voit sur le Play Store et qu'il nous cite. Avant,
  // seul le numéro de Brave (1.90.0) apparaissait, indiscernable d'une
  // version à l'autre. Repli sur l'ancien format si le versionName est vide.
  const std::string& calver = base::android::apk_info::package_version_name();
  std::string application(base::android::apk_info::host_package_label());
  application.append(" ");
  if (!calver.empty()) {
    application.append(calver);
    application.append("\nBraveCore ");
    application.append(
        version_info::GetBraveVersionWithoutChromiumMajorVersion());
    application.append(" (");
    application.append(version_info::GetBraveChromiumVersionNumber());
    application.append(")");
    return application;
  }
  application.append(
      version_info::GetBraveVersionWithoutChromiumMajorVersion());
  application.append(", Chromium ");
  application.append(version_info::GetBraveChromiumVersionNumber());

  return application;
}

DEFINE_JNI(AboutSettingsBridge)
