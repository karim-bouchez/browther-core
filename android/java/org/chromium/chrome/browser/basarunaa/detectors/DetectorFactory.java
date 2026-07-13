/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa.detectors;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;

import org.chromium.chrome.browser.basarunaa.BasarunaaBackend;
import org.chromium.chrome.browser.basarunaa.NanoDetSentinelDetector;

/**
 * Factory du détecteur SENTINEL Basarunaa (NanoDet, two-tier vidéo).
 *
 * <p>Migration gender-v2n (2026-07-13) : la cascade image (YOLO-pose + YOLO-face
 * + genderage + PPLCNet + variantes TFLite) a été retirée — le single-shot
 * {@link org.chromium.chrome.browser.basarunaa.GenderV2nDetector} (instancié
 * directement par {@code BasarunaaEngine}) la remplace. Il ne reste que le
 * sentinel (bboxes person légères pour le scheduler vidéo).
 */
@NullMarked
public final class DetectorFactory {
    private static final String TAG = "Basarunaa";

    private DetectorFactory() {}

    public static SentinelDetector createSentinel(BasarunaaBackend backend) throws Exception {
        if (backend.isTflite()) {
            // TODO Phase 6 : return new NanoDetSentinelTfliteDetector(backend);
            Log.d(TAG, "[Factory] sentinel: TFLite impl pending (Phase 6), using ORT");
        }
        return new NanoDetSentinelDetector();
    }
}
