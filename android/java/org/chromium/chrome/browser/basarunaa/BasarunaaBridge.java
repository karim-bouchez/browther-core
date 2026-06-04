/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import org.jni_zero.CalledByNative;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;

/**
 * Bridge C++ → Java statique pour Basarunaa (logging only). Mirror du pattern
 * {@code SawtunaaBridge}.
 *
 * <p>Les actions image (analyzeImage, cancelAnalyze, pageReset) sont routées
 * par le {@code BasarunaaTabHelper} C++ vers une instance Java
 * {@link BasarunaaTabAnalyzer} per-WebContents — pas via ce bridge. On garde
 * ce point d'entrée uniquement pour {@link #onLogJs} et {@link #onMetric},
 * qui n'ont aucun état partagé et bénéficient du tag logcat global.
 */
@NullMarked
public final class BasarunaaBridge {
    private static final String TAG = "Basarunaa";

    private BasarunaaBridge() {}

    @CalledByNative
    public static void onLogJs(String message) {
        Log.i(TAG, "[Java/LogJs] %s", message);
    }

    @CalledByNative
    public static void onMetric(String metricJson) {
        Log.i(TAG, "[Java/Metric] %s", metricJson);
    }
}
