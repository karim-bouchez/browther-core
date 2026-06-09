/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa.detectors;

import android.graphics.Bitmap;

import org.chromium.build.annotations.NullMarked;

import org.chromium.chrome.browser.basarunaa.NudeNetDetector;

/**
 * Détecteur NSFW NudeNet 320×320 — full-frame blur si positif.
 *
 * <p>Implémentations : {@link NudeNetDetector} (ORT). <b>Pas de variante
 * TFLite</b> : la conversion onnx2tf échoue (Mul broadcast issue dans
 * l'anchor decoder YOLO). Reste en ORT_CPU indépendamment du backend global.
 * Cf. {@code docs/V3_GPU_BENCH.md} § Phase 1.
 */
@NullMarked
public interface NudeDetector extends AutoCloseable {
    /** Vérifie si l'image contient du contenu NSFW. */
    NudeNetDetector.Result check(Bitmap src) throws Exception;

    @Override
    void close() throws Exception;
}
