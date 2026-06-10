/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa.detectors;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;

import org.chromium.chrome.browser.basarunaa.BasarunaaBackend;
import org.chromium.chrome.browser.basarunaa.BasarunaaPrefs;
import org.chromium.chrome.browser.basarunaa.ComparePoseDetector;
import org.chromium.chrome.browser.basarunaa.GenderAgeClassifier;
import org.chromium.chrome.browser.basarunaa.NanoDetSentinelDetector;
import org.chromium.chrome.browser.basarunaa.NudeNetDetector;
import org.chromium.chrome.browser.basarunaa.PplcNetClassifier;
import org.chromium.chrome.browser.basarunaa.YoloFaceDetector;
import org.chromium.chrome.browser.basarunaa.YoloPoseDetector;
import org.chromium.chrome.browser.basarunaa.YoloPoseTfliteDetector;

/**
 * Factory unique des détecteurs Basarunaa — choisit l'implémentation ORT vs
 * TFLite selon le {@link BasarunaaBackend} effectif et la disponibilité d'une
 * variante TFLite par modèle.
 *
 * <p><b>Couverture TFLite par modèle</b> (à jour Phase 1 conversion) :
 * <table>
 *   <tr><th>Modèle</th><th>Variante TFLite</th></tr>
 *   <tr><td>yolo11n-pose</td><td>✓ fp32 (fp16 KO, max_diff 3.27)</td></tr>
 *   <tr><td>yolov8n-face</td><td>✗ — onnx2tf Concat dim mismatch, reste ORT</td></tr>
 *   <tr><td>nanodet-plus-m_320</td><td>✓ fp32, fp16 marginal</td></tr>
 *   <tr><td>nudenet-320</td><td>✗ — onnx2tf Mul broadcast, reste ORT</td></tr>
 *   <tr><td>genderage</td><td>✓ fp16 strict accuracy</td></tr>
 *   <tr><td>pplcnet_pedestrian_attribute</td><td>✓ fp16 strict accuracy</td></tr>
 * </table>
 *
 * <p>Cf. {@code docs/V3_GPU_BENCH.md} pour les détails. La factory retombe
 * automatiquement sur ORT pour {@code yolov8n-face} et {@code nudenet-320}
 * même si le backend global est TFLite.
 *
 * <p><b>Status Phase 3</b> : toutes les méthodes retournent encore les impls
 * ORT — les variantes {@code *TfliteDetector} arrivent Phase 4 (pose proto)
 * puis Phase 6 (les 3 autres convertibles).
 */
@NullMarked
public final class DetectorFactory {
    private static final String TAG = "Basarunaa";

    private DetectorFactory() {}

    /**
     * Choisit dynamiquement le PoseDetector. Phase 5 bench Huawei a établi
     * que TFLite GPU FP32 sur yolo-pose donne 4.6× (410ms→88ms vs ORT CPU) —
     * <b>le seul modèle où on a un gain GPU prouvé</b>. Sur les autres
     * modèles, ORT CPU bat TFLite GPU (overhead launch > calcul).
     *
     * <p>Décision :
     * <ol>
     *   <li>Si la pref {@code brave.basarunaa.tflite_gpu_enabled} est ON
     *       (default true) ET le device supporte le GPU delegate (via
     *       {@link BasarunaaBackend#gpuSupported}) → TFLITE_GPU_FP32.</li>
     *   <li>Sinon → ORT_CPU (fallback safe — bench Phase 5 ref).</li>
     * </ol>
     *
     * <p>Le {@code backend} param est ignoré pour ce modèle (les autres
     * createXxx l'utilisent encore pour cohérence API ; un futur Phase 6.2
     * micro-bench par device pourra unifier).
     */
    public static PoseDetector createPose(BasarunaaBackend backend) throws Exception {
        if (BasarunaaPrefs.tfliteGpuEnabled() && BasarunaaBackend.gpuSupported()) {
            final PoseDetector tflitePose =
                    new YoloPoseTfliteDetector(BasarunaaBackend.TFLITE_GPU_FP32);
            if (BasarunaaPrefs.tfliteCompareMode()) {
                Log.i(TAG, "[Factory] pose: TFLite GPU FP32 + ComparePoseDetector"
                        + " (Phase 6.1 debug — coût +ORT ~410ms/img)");
                return new ComparePoseDetector(tflitePose, new YoloPoseDetector());
            }
            Log.i(TAG, "[Factory] pose: TFLite GPU FP32 (pref ON, gpuSupported=true)");
            return tflitePose;
        }
        Log.d(TAG, "[Factory] pose: ORT_CPU (pref OFF or gpu unsupported)");
        return new YoloPoseDetector();
    }

    public static FaceDetector createFace(BasarunaaBackend backend) throws Exception {
        // Toujours ORT — pas de variante TFLite possible pour yolov8n-face
        // (onnx2tf Concat dim mismatch sur post-process YOLO).
        if (backend.isTflite()) {
            Log.d(TAG, "[Factory] face: no TFLite variant available, using ORT");
        }
        return new YoloFaceDetector();
    }

    public static GenderClassifier createGender(BasarunaaBackend backend) throws Exception {
        if (backend.isTflite()) {
            // TODO Phase 6 : return new GenderAgeTfliteClassifier(backend);
            Log.d(TAG, "[Factory] gender: TFLite impl pending (Phase 6), using ORT");
        }
        return new GenderAgeClassifier();
    }

    public static BodyClassifier createBody(BasarunaaBackend backend) throws Exception {
        if (backend.isTflite()) {
            // TODO Phase 6 : return new PplcNetTfliteClassifier(backend);
            Log.d(TAG, "[Factory] body: TFLite impl pending (Phase 6), using ORT");
        }
        return new PplcNetClassifier();
    }

    public static NudeDetector createNude(BasarunaaBackend backend) throws Exception {
        // Toujours ORT — pas de variante TFLite possible pour nudenet-320
        // (onnx2tf Mul broadcast sur anchor decoder YOLO).
        if (backend.isTflite()) {
            Log.d(TAG, "[Factory] nude: no TFLite variant available, using ORT");
        }
        return new NudeNetDetector();
    }

    public static SentinelDetector createSentinel(BasarunaaBackend backend) throws Exception {
        if (backend.isTflite()) {
            // TODO Phase 6 : return new NanoDetSentinelTfliteDetector(backend);
            Log.d(TAG, "[Factory] sentinel: TFLite impl pending (Phase 6), using ORT");
        }
        return new NanoDetSentinelDetector();
    }
}
