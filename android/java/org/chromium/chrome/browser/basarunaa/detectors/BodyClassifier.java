/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa.detectors;

import android.graphics.Bitmap;

import org.chromium.build.annotations.NullMarked;

import org.chromium.chrome.browser.basarunaa.GenderAgeClassifier;

/**
 * Classifier de genre corps — PPLCNet pedestrian attribute 224×224.
 *
 * <p>Implémentations : {@code PplcNetClassifier} (ORT), {@code
 * PplcNetTfliteClassifier} (TFLite, Phase 6). Le {@link GenderAgeClassifier.Result}
 * partagé permet à {@code BasarunaaEngine#pickBestGender} de comparer
 * face vs body sans connaître le backend.
 */
@NullMarked
public interface BodyClassifier extends AutoCloseable {
    /**
     * Classifie un crop body déjà préparé (généralement 224×224 RGB avec
     * polygon mask grayer du background). Le bitmap est consommé en lecture
     * seule ; à l'appelant de le recycle().
     */
    GenderAgeClassifier.Result classifyCrop(Bitmap bodyCrop) throws Exception;

    @Override
    void close() throws Exception;
}
