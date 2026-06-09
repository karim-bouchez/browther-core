/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;

/**
 * Backend de runtime ML retenu pour le pipeline Basarunaa Android (V3).
 *
 * <p>Le pipeline tournait initialement 100% sur {@link OrtRuntime} (ONNX
 * Runtime + XNNPACK CPU 8 cores). Le V3 introduit un runtime alternatif
 * TensorFlow Lite + GpuDelegate (OpenGL ES / Vulkan compute) avec l'objectif
 * d'un gain perf 2-4× sur les modèles YOLO/CNN. NNAPI a été testé et rejeté
 * (5-23× plus lent sur Huawei UBV0218815000852, cf. memory
 * {@code feedback_basarunaa_android_nnapi_useless}).
 *
 * <p>Le pattern est un <b>double runtime + pref toggle live</b> : chaque
 * détecteur est instancié via {@link
 * org.chromium.chrome.browser.basarunaa.detectors.DetectorFactory} qui choisit
 * son impl ORT ou TFLite selon le backend retourné par {@link #pickBest}.
 *
 * <p><b>Compromis</b> : 2 modèles (yolov8n-face, nudenet-320) ne se convertissent
 * pas via onnx2tf (post-process YOLO embarqué) → ils restent en ORT_CPU même
 * si {@link #TFLITE_GPU_FP32} est sélectionné globalement. Le factory gère ce
 * cas par modèle (cf. memory {@code feedback_basarunaa_android_nnapi_useless}
 * + commit V3 Phase 1 conversion).
 */
@NullMarked
public enum BasarunaaBackend {
    /** Référence — ONNX Runtime + XNNPACK CPU. Toujours disponible. */
    ORT_CPU,

    /** TFLite + XNNPACK CPU. Fallback intermédiaire si GPU délégué KO. */
    TFLITE_CPU,

    /** TFLite + GpuDelegate, modèle FP32. Sûr — gain typique ~2×. */
    TFLITE_GPU_FP32,

    /** TFLite + GpuDelegate, modèle FP16. Plus rapide ~3-4×, accuracy à valider par modèle. */
    TFLITE_GPU_FP16;

    private static final String TAG = "Basarunaa";

    public boolean isTflite() {
        return this != ORT_CPU;
    }

    public boolean isGpu() {
        return this == TFLITE_GPU_FP32 || this == TFLITE_GPU_FP16;
    }

    public boolean isFp16() {
        return this == TFLITE_GPU_FP16;
    }

    /**
     * Choisit le backend optimal pour ce device en fonction de la pref user.
     *
     * <p>Si la pref est désactivée (par défaut tant que Phase 0 sanity check
     * Huawei n'est pas validé) → {@link #ORT_CPU}.
     *
     * <p>Si pref activée et GPU delegate supporté par le device (via
     * {@code CompatibilityList#isDelegateSupportedOnThisDevice}) → {@link
     * #TFLITE_GPU_FP32} par défaut (FP16 à activer par-modèle via override).
     *
     * <p>Si pref activée mais GPU non supporté → {@link #TFLITE_CPU}, fallback
     * intermédiaire pour permettre un bench sans TFLite GPU.
     *
     * <p>Tout throwable (classe TFLite non chargeable, init GPU exception) →
     * fallback {@link #ORT_CPU}.
     */
    public static BasarunaaBackend pickBest(boolean userPrefTfliteGpu) {
        if (!userPrefTfliteGpu) return ORT_CPU;
        try {
            // Lazy : ne touche la classe TFLite que si la pref est on, évite
            // de charger les .so GpuDelegate pour rien sur ORT_CPU pur.
            final org.tensorflow.lite.gpu.CompatibilityList compat =
                    new org.tensorflow.lite.gpu.CompatibilityList();
            final boolean gpuOk = compat.isDelegateSupportedOnThisDevice();
            Log.i(TAG, "[Backend] CompatibilityList.gpuOk=%b", gpuOk);
            return gpuOk ? TFLITE_GPU_FP32 : TFLITE_CPU;
        } catch (Throwable t) {
            Log.w(TAG, "[Backend] GPU capability check failed; fallback ORT_CPU", t);
            return ORT_CPU;
        }
    }
}
