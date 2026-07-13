/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import android.graphics.Bitmap;

import ai.onnxruntime.OnnxTensor;
import ai.onnxruntime.OrtException;
import ai.onnxruntime.OrtSession;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;

import java.io.IOException;
import java.nio.FloatBuffer;
import java.util.List;
import java.util.Map;

/**
 * Détecteur single-shot gender-v2n : bbox + genre 3 classes (male/female/child)
 * + 17 keypoints COCO, en UNE inférence ORT. Remplace la cascade YOLO-pose +
 * YOLO-face + genderage + PPLCNet (migration 2026-07-13, cf.
 * {@code private/docs/BASARUNAA_MOBILE_GENDER_V2N.md}).
 *
 * <p>Format ONNX : input {@code [1, 3, 640, 640]} float32 RGB [0,1] letterboxé,
 * output {@code [1, 58, N]} où {@code 58 = 4 (xywh) + 3 (scores classe) + 51
 * (17 kpts × xyc)}. Le DÉCODAGE (argmax classe, un-letterbox, faceBbox, NMS) vit
 * dans le module PUR {@link GenderV2nDecode} — validé contre le golden
 * {@code tests/golden/gender-v2n/}. Ce fichier ne fait que : letterbox → ORT →
 * accès FloatBuffer C-major → decode.
 */
@NullMarked
public final class GenderV2nDetector implements AutoCloseable {
    private static final String TAG = "Basarunaa";
    private static final String MODEL = "gender-v2n-640.onnx";
    private static final int INPUT_SIZE = 640;
    private static final int NUM_CHANNELS = 58; // 4 + 3 + 17*3
    private static final int NUM_CLASSES = 3;
    private static final int NUM_KEYPOINTS = 17;

    private final OrtSession session;
    private final String inputName;
    private final String outputName;

    public GenderV2nDetector() throws OrtException, IOException {
        session = OrtRuntime.loadModel(MODEL);
        inputName = session.getInputNames().iterator().next();
        outputName = session.getOutputNames().iterator().next();
        Log.i(TAG, "[GenderV2n] ready (input=%s, output=%s)", inputName, outputName);
    }

    @Override
    public void close() throws OrtException {
        session.close();
    }

    /**
     * Détecte TOUTES les persons (pur extracteur — aucune décision de flou : la
     * policy vit dans {@code core/policy.ts}, appliquée côté bundle android/ TS).
     *
     * @param src image source (taille arbitraire)
     * @param confThreshold seuil de score (pref slider conf_body)
     * @param iouThreshold seuil IoU pour NMS (typiquement 0.5)
     */
    public List<GenderV2nDecode.PersonRaw> detect(
            Bitmap src, float confThreshold, float iouThreshold) throws OrtException {
        final int srcW = src.getWidth();
        final int srcH = src.getHeight();
        final Letterbox.Result lb = Letterbox.apply(src, INPUT_SIZE);

        try (OnnxTensor input = OnnxTensor.createTensor(
                        OrtRuntime.env(), lb.tensor, new long[] {1, 3, INPUT_SIZE, INPUT_SIZE});
                OrtSession.Result result = session.run(Map.of(inputName, input))) {
            final OnnxTensor outTensor = (OnnxTensor) result.get(0);
            final long[] dims = outTensor.getInfo().getShape();
            // Output [1, 58, N] (rank 3) ou [1, 1, 58, N] (rank 4) — N = dernière dim.
            final int numDetections = (int) dims[dims.length - 1];
            final FloatBuffer flat = outTensor.getFloatBuffer();
            // Layout C-major : flat[c * numDetections + i] = value(channel c, det i).
            return GenderV2nDecode.decode(
                    NUM_CHANNELS,
                    numDetections,
                    NUM_CLASSES,
                    NUM_KEYPOINTS,
                    lb.scale,
                    lb.padX,
                    lb.padY,
                    srcW,
                    srcH,
                    confThreshold,
                    iouThreshold,
                    GenderV2nDecode.DEFAULT_FACE_PADDING,
                    (c, i) -> flat.get(c * numDetections + i));
        }
    }
}
