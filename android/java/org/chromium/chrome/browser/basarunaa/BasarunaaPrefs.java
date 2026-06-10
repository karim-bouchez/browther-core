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

    /**
     * {@code kBasarunaaTfliteCompareMode} — Phase 6.1 debug. Quand ON ET
     * {@link #PREF_TFLITE_GPU_ENABLED} ON, le factory wrap le YoloPose TFLite
     * dans un {@code ComparePoseDetector} qui run aussi ORT_CPU pour mesurer le
     * drift Mali-G76 GPU FP32 vs CPU sur le device user.
     */
    public static final String PREF_TFLITE_COMPARE_MODE = "brave.basarunaa.tflite_compare_mode";

    private BasarunaaPrefs() {}

    /**
     * Lit la pref {@link #PREF_TFLITE_GPU_ENABLED} (default false côté C++ via
     * {@code brave_profile_prefs.cc} — voir le commentaire sur le default
     * pourquoi pas true post-Phase 6 incident). En cas d'exception (profile
     * not ready au boot), fallback false pour rester sur ORT_CPU sain.
     */
    public static boolean tfliteGpuEnabled() {
        try {
            return UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                    .getBoolean(PREF_TFLITE_GPU_ENABLED);
        } catch (Throwable t) {
            Log.w(TAG, "[Prefs] read tflite_gpu_enabled failed, default false", t);
            return false;
        }
    }

    /**
     * Lit la pref {@link #PREF_TFLITE_COMPARE_MODE} (default false). À activer
     * manuellement (avec {@link #tfliteGpuEnabled()} ON) pour comparer ORT vs
     * TFLite sur device. Coût ~410ms par inférence — ne PAS laisser ON en prod.
     */
    public static boolean tfliteCompareMode() {
        try {
            return UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                    .getBoolean(PREF_TFLITE_COMPARE_MODE);
        } catch (Throwable t) {
            Log.w(TAG, "[Prefs] read tflite_compare_mode failed, default false", t);
            return false;
        }
    }
}
