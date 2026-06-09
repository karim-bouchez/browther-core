/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa.detectors;

import android.graphics.Bitmap;

import org.chromium.build.annotations.NullMarked;

import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Bbox;

import java.util.List;

/**
 * Détecteur sentinel NanoDet 320×320 — détection rapide person-only pour
 * pipeline vidéo two-tier (sentinel léger ~12ms / 100ms + YOLO lourd ~80ms /
 * ~1s).
 *
 * <p>Implémentations : {@code NanoDetSentinelDetector} (ORT), {@code
 * NanoDetSentinelTfliteDetector} (TFLite, Phase 6).
 */
@NullMarked
public interface SentinelDetector extends AutoCloseable {
    /**
     * Détecte les bbox personne dans une image. Rapide — utilisé sur chaque
     * frame vidéo, le YOLO-pose n'est appelé que tous les ~10 frames.
     */
    List<Bbox> detect(Bitmap src, float confThreshold) throws Exception;

    @Override
    void close() throws Exception;
}
