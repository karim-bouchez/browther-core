/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa.detectors;

import android.graphics.Bitmap;

import org.chromium.build.annotations.NullMarked;

import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.PersonDetection;

import java.util.List;

/**
 * Détecteur YOLO-pose : bbox personne + 17 keypoints COCO + bbox face dérivée.
 *
 * <p>Implémentations : {@code YoloPoseDetector} (ORT), {@code
 * YoloPoseTfliteDetector} (TFLite, Phase 4). Le choix se fait via {@link
 * DetectorFactory#createPose}.
 */
@NullMarked
public interface PoseDetector extends AutoCloseable {
    /**
     * Détecte les personnes + leurs keypoints + bbox face dérivée.
     *
     * @param src image source (taille arbitraire)
     * @param confThreshold seuil de confidence personne (pref slider conf_body)
     * @param iouThreshold seuil IoU pour NMS (typiquement 0.5)
     */
    List<PersonDetection> detect(Bitmap src, float confThreshold, float iouThreshold)
            throws Exception;

    @Override
    void close() throws Exception;
}
