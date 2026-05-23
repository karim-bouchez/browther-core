/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.sawtunaa;

import org.jni_zero.CalledByNative;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;

/**
 * Bridge C++ → Java statique pour Sawtunaa (logging only).
 *
 * <p>Les actions audio (preprocessChunk, playAt, pauseAudio, etc.) sont
 * routées par le {@code SawtunaaTabHelper} C++ vers une instance Java
 * {@link SawtunaaPlayer} per-WebContents — pas via ce bridge. On garde
 * ce point d'entrée uniquement pour les deux endpoints log-only qui
 * traversent toute la pile renderer → browser : {@link #onLogJs} et
 * {@link #onMetric}. Ils peuvent rester statiques car ils n'ont aucun
 * état partagé et le routing par WebContents n'apporte rien (le tag
 * de log permet déjà de filtrer par tab si besoin).
 */
@NullMarked
public final class SawtunaaBridge {
    private static final String TAG = "Sawtunaa";

    private SawtunaaBridge() {}

    @CalledByNative
    public static void onLogJs(String message) {
        Log.i(TAG, "[Java/LogJs] %s", message);
    }

    @CalledByNative
    public static void onMetric(String metricJson) {
        Log.i(TAG, "[Java/Metric] %s", metricJson);
    }
}
