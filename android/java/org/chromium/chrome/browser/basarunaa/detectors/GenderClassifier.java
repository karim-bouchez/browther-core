/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa.detectors;

import android.graphics.Bitmap;

import org.chromium.build.annotations.NullMarked;

import org.chromium.chrome.browser.basarunaa.GenderAgeClassifier;

/**
 * Classifier de genre face — InsightFace genderage 96×96.
 *
 * <p>Implémentations : {@link GenderAgeClassifier} (ORT), {@code
 * GenderAgeTfliteClassifier} (TFLite, Phase 6). Result type partagé
 * ({@link GenderAgeClassifier.Result}) — pas extrait dans ce package pour
 * éviter de churner toutes les références à {@code GenderAgeClassifier.Result}
 * dans {@code BasarunaaEngine}. La sémantique des champs reste identique.
 */
@NullMarked
public interface GenderClassifier extends AutoCloseable {
    /**
     * Classifie un visage déjà aligné 96×96 par {@code FaceAlign}. Le bitmap
     * est consommé en lecture seule ; à l'appelant de le recycle().
     */
    GenderAgeClassifier.Result classify(Bitmap alignedFace) throws Exception;

    @Override
    void close() throws Exception;
}
