/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa.detectors;

import android.graphics.Bitmap;

import org.chromium.build.annotations.NullMarked;

import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.FaceDetection;

import java.util.List;

/**
 * Détecteur YOLO-face : bbox visage + 5 keypoints face (yeux, nez, bouche).
 *
 * <p>Implémentations : {@code YoloFaceDetector} (ORT). <b>Pas de variante
 * TFLite</b> : la conversion onnx2tf échoue sur ce modèle (post-process YOLO
 * embarqué avec anchor decoder + Concat NMS dynamique). Reste en ORT_CPU
 * indépendamment du backend global retenu. Cf. {@code docs/V3_GPU_BENCH.md}
 * § Phase 1.
 */
@NullMarked
public interface FaceDetector extends AutoCloseable {
    /**
     * Détecte les visages dans une image.
     *
     * @param src image source (taille arbitraire)
     * @param confThreshold seuil de confidence (pref slider conf_face)
     * @param iouThreshold seuil IoU pour NMS (typiquement 0.5)
     */
    List<FaceDetection> detect(Bitmap src, float confThreshold, float iouThreshold)
            throws Exception;

    @Override
    void close() throws Exception;
}
