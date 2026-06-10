/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;
import org.chromium.chrome.browser.profiles.ProfileManager;
import org.chromium.components.user_prefs.UserPrefs;

/**
 * Accès Java aux préférences Basarunaa stockées côté C++. Centralise le
 * pattern {@code UserPrefs.get(profile).getBoolean(key)} pour éviter les
 * références hardcodées aux noms de pref dans les détecteurs.
 *
 * <p>Les clés sont les mêmes que celles déclarées dans
 * {@code brave/components/constants/pref_names.h} (kBasarunaa*). Tout accès
 * depuis Java doit transiter par cette classe pour qu'on tienne un index
 * unique des prefs consommées Android.
 */
@NullMarked
public final class BasarunaaPrefs {
    private static final String TAG = "Basarunaa";

    /** {@code kBasarunaaTfliteGpuEnabled} — Android V3 toggle TFLite GPU yolo-pose. */
    public static final String PREF_TFLITE_GPU_ENABLED = "brave.basarunaa.tflite_gpu_enabled";

    private BasarunaaPrefs() {}

    /**
     * Lit la pref {@link #PREF_TFLITE_GPU_ENABLED} (default true côté C++ via
     * {@code brave_profile_prefs.cc}). Retourne true si la pref est active et
     * que la lecture profile est OK ; en cas d'exception (profile not ready),
     * retourne le default {@code true} — comportement parité comportement V2
     * jusqu'à ce que le profile soit dispo, puis switch transparent à la
     * volée au prochain {@link BasarunaaEngine#ensureModelsLoaded}.
     */
    public static boolean tfliteGpuEnabled() {
        try {
            return UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                    .getBoolean(PREF_TFLITE_GPU_ENABLED);
        } catch (Throwable t) {
            Log.w(TAG, "[Prefs] read tflite_gpu_enabled failed, default true", t);
            return true;
        }
    }
}
