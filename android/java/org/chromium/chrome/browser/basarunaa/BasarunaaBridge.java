/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import org.jni_zero.CalledByNative;
import org.jni_zero.JNINamespace;
import org.jni_zero.NativeMethods;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;

/**
 * Bridge C++ ↔ Java pour Basarunaa.
 *
 * <p>Pattern parité {@code BrowtherAnalyticsBridge} : la classe est statique
 * et référencée depuis du Java reachable, donc R8 la garde dans le dex avec
 * ses bindings {@code @NativeMethods} (le binding {@code @NativeMethods}
 * porté par un {@code BasarunaaTabAnalyzer} non-reachable est strippé par
 * R8 alors que les `@CalledByNative` côté analyzer survivent — incident
 * observé au premier build 2026-06-04, fix par centralisation ici).
 *
 * <p>Direction <b>C++ → Java</b> ({@code @CalledByNative}) :
 *   - {@link #onLogJs(String)}
 *   - {@link #onMetric(String)}
 *
 * <p>Direction <b>Java → C++</b> ({@code @NativeMethods}) :
 *   - {@link #notifyAnalyzeReply} : appelée par {@link BasarunaaTabAnalyzer}
 *     après inférence ML pour reporter le verdict au tab helper C++. Le
 *     pointer natif est passé tel quel ; sa validité est garantie côté
 *     Java par l'appelant (check de {@code mNativeHelper != 0}).
 */
@JNINamespace("basarunaa")
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

    /**
     * Reporte le verdict ML au C++ pour push vers le renderer source via
     * {@code BasarunaaApply::Apply}.
     */
    public static void notifyAnalyzeReply(long nativeHelper, int imageId,
                                          String decision, String personsJson,
                                          double elapsedMs) {
        BasarunaaBridgeJni.get().onAnalyzeReply(
                nativeHelper, imageId, decision, personsJson, elapsedMs);
    }

    /**
     * V2.5 — reporte le verdict sentinel au C++ pour push vers le renderer
     * source via {@code BasarunaaApply::ApplyVideoSentinel}.
     *
     * @param bboxesJson JSON array de {@code [x1,y1,x2,y2]} en coords source
     */
    public static void notifySentinelReply(long nativeHelper, int frameId,
                                            String bboxesJson) {
        BasarunaaBridgeJni.get().onSentinelReply(nativeHelper, frameId, bboxesJson);
    }

    @NativeMethods
    interface Natives {
        /**
         * Callback Java → C++ vers {@code BasarunaaTabHelper::OnAnalyzeReply}.
         * Le {@code nativeHelper} est un pointer brute du tab helper, sa
         * validité est garantie côté Java par le check de l'appelant.
         */
        void onAnalyzeReply(long nativeHelper, int imageId, String decision,
                            String personsJson, double elapsedMs);

        /**
         * V2.5 — callback Java → C++ vers
         * {@code BasarunaaTabHelper::OnSentinelReply}.
         */
        void onSentinelReply(long nativeHelper, int frameId, String bboxesJson);
    }
}
