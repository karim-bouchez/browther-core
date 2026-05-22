/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.sawtunaa;

import org.jni_zero.CalledByNative;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;

/**
 * Bridge C++ → Java pour le pipeline Sawtunaa (Jalon 2.B.5).
 *
 * <p>Le SawtunaaTabHelper C++ (composant cross-platform) appelle ces
 * méthodes via JNI à chaque action Mojo reçue du renderer. Pour le Jalon
 * 2.B.5 c'est purement du logging — l'objectif est de valider que la
 * chaîne renderer JS → Mojo → C++ TabHelper → JNI → Java atteint bien
 * la couche managée Android.
 *
 * <p>Les méthodes audio lourdes (preprocess avec Float32 samples, sync
 * ranges multi-éléments) reçoivent des arguments simplifiés (count/size
 * seulement) ; le marshaling complet (float[] + Vec<TimeRange>) arrivera
 * au Jalon 2.D quand on branchera réellement {@link NSNet2Processor} +
 * SawtunaaAudioPlayer derrière le bridge.
 *
 * <p>Toutes les méthodes sont statiques no-op-friendly — pas d'état Java
 * partagé, pas de référence native, pas de WebContents Java side. Si la
 * pref Sawtunaa est OFF le binder browser-side ne fire jamais, donc on
 * n'arrive pas ici.
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

    @CalledByNative
    public static void onPreprocessChunk(double timestampMs, int sampleCount) {
        Log.i(TAG, "[Java/Chunk] ts=%.2f n=%d", timestampMs, sampleCount);
    }

    @CalledByNative
    public static void onPlayAt(double timestampMs) {
        Log.i(TAG, "[Java/PlayAt] ms=%.2f", timestampMs);
    }

    @CalledByNative
    public static void onClearChunks() {
        Log.i(TAG, "[Java/ClearChunks]");
    }

    @CalledByNative
    public static void onPageReset(String url) {
        Log.i(TAG, "[Java/PageReset] %s", url);
    }

    @CalledByNative
    public static void onSeekTo(double toMs) {
        Log.i(TAG, "[Java/SeekTo] ms=%.2f", toMs);
    }

    @CalledByNative
    public static void onEvictRange(double startMs, double endMs) {
        Log.i(TAG, "[Java/EvictRange] %.2f -> %.2f", startMs, endMs);
    }

    @CalledByNative
    public static void onSyncRanges(int count) {
        Log.i(TAG, "[Java/SyncRanges] n=%d", count);
    }

    @CalledByNative
    public static void onPauseAudio() {
        Log.i(TAG, "[Java/PauseAudio]");
    }

    @CalledByNative
    public static void onResumeAudio() {
        Log.i(TAG, "[Java/ResumeAudio]");
    }
}
