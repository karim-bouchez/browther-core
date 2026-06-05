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
import org.chromium.build.annotations.Nullable;

import java.io.IOException;
import java.nio.FloatBuffer;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Bbox;
import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Keypoint;
import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.PersonDetection;

/**
 * Détecteur YOLO11n-Pose : bbox personne + 17 keypoints COCO.
 *
 * <p>Port natif de {@code private/extensions/basarunaa/src/detectors/
 * yolo_pose.js}. Format ONNX : input {@code [1, 3, 640, 640]} float32,
 * output {@code [1, 56, N]} où {@code 56 = 4 (xywh) + 1 (score) + 51 (17 × 3)}.
 *
 * <p>Bbox face dérivée des keypoints 0-4 (nez, yeux, oreilles) si au moins
 * 2 keypoints visibles (confidence > 0.3).
 */
@NullMarked
public final class YoloPoseDetector implements AutoCloseable {
    private static final String TAG = "Basarunaa";
    private static final String MODEL = "yolo11n-pose.onnx";
    private static final int INPUT_SIZE = 640;
    private static final int NUM_KEYPOINTS = 17;
    private static final float FACE_KP_CONF_MIN = 0.3f;
    private static final float DEFAULT_FACE_PADDING = 0.4f;

    private final OrtSession session;
    private final String inputName;
    private final String outputName;

    public YoloPoseDetector() throws OrtException, IOException {
        session = OrtRuntime.loadModel(MODEL);
        inputName = session.getInputNames().iterator().next();
        outputName = session.getOutputNames().iterator().next();
        Log.i(TAG, "[YoloPose] ready (input=%s, output=%s)", inputName, outputName);
    }

    @Override
    public void close() throws OrtException {
        session.close();
    }

    /**
     * Détecte les personnes + leurs keypoints + bbox face dérivée.
     *
     * @param src image source (taille arbitraire)
     * @param confThreshold seuil de confidence personne (pref slider conf_body)
     * @param iouThreshold seuil IoU pour NMS (typiquement 0.5)
     */
    public List<PersonDetection> detect(Bitmap src, float confThreshold, float iouThreshold)
            throws OrtException {
        final int srcW = src.getWidth();
        final int srcH = src.getHeight();
        final Letterbox.Result lb = Letterbox.apply(src, INPUT_SIZE);

        try (OnnxTensor input = OnnxTensor.createTensor(
                OrtRuntime.env(), lb.tensor, new long[] {1, 3, INPUT_SIZE, INPUT_SIZE});
                OrtSession.Result result = session.run(Map.of(inputName, input))) {
            // Output shape varie selon l'export ONNX : [1, 56, N] (rank 3) ou
            // [1, 1, 56, N] (rank 4). On lit le buffer flat + dernière dim
            // pour rester robuste au rank.
            final OnnxTensor outTensor = (OnnxTensor) result.get(0);
            final long[] dims = outTensor.getInfo().getShape();
            final int numDetections = (int) dims[dims.length - 1];
            final FloatBuffer flat = outTensor.getFloatBuffer();
            return postprocess(flat, numDetections, lb, srcW, srcH, confThreshold,
                    iouThreshold);
        }
    }

    private static List<PersonDetection> postprocess(
            FloatBuffer flat,
            int numDetections,
            Letterbox.Result lb,
            int srcW,
            int srcH,
            float confThreshold,
            float iouThreshold) {
        if (numDetections == 0) return Collections.emptyList();

        // Layout C-major : flat[f * numDetections + i] = features[f][i].
        // 56 features = 4 (xywh) + 1 (score) + 51 (17 keypoints × 3).
        final ArrayList<PersonDetection> boxes = new ArrayList<>();
        for (int i = 0; i < numDetections; i++) {
            final float score = flat.get(4 * numDetections + i);
            if (score < confThreshold) continue;

            final float cx = flat.get(i);
            final float cy = flat.get(numDetections + i);
            final float w = flat.get(2 * numDetections + i);
            final float h = flat.get(3 * numDetections + i);

            final float x1 = Math.max(0f, (cx - w / 2f - lb.padX) / lb.scale);
            final float y1 = Math.max(0f, (cy - h / 2f - lb.padY) / lb.scale);
            final float x2 = Math.min((float) srcW, (cx + w / 2f - lb.padX) / lb.scale);
            final float y2 = Math.min((float) srcH, (cy + h / 2f - lb.padY) / lb.scale);

            final Keypoint[] keypoints = new Keypoint[NUM_KEYPOINTS];
            for (int k = 0; k < NUM_KEYPOINTS; k++) {
                final int base = 5 + k * 3;
                final float kx = (flat.get(base * numDetections + i) - lb.padX) / lb.scale;
                final float ky = (flat.get((base + 1) * numDetections + i) - lb.padY) / lb.scale;
                final float kc = flat.get((base + 2) * numDetections + i);
                keypoints[k] = new Keypoint(kx, ky, kc);
            }

            final Bbox bbox = new Bbox(x1, y1, x2, y2);
            final Bbox faceBbox =
                    deriveFaceBbox(keypoints, srcW, srcH, DEFAULT_FACE_PADDING);
            boxes.add(new PersonDetection(bbox, score, keypoints, faceBbox));
        }
        return Nms.suppress(boxes, iouThreshold);
    }

    /**
     * Dérive la bbox face depuis les 5 premiers keypoints (nez, yeux,
     * oreilles). Retourne null si <2 keypoints visibles (conf > 0.3).
     *
     * <p>Port de {@code yolo_pose.js#_deriveFaceBbox}.
     */
    @Nullable
    private static Bbox deriveFaceBbox(
            Keypoint[] keypoints, int srcW, int srcH, float facePadding) {
        // Compte les keypoints face visibles (0..4) et calcule min/max.
        int visibleCount = 0;
        float minX = Float.POSITIVE_INFINITY;
        float minY = Float.POSITIVE_INFINITY;
        float maxX = Float.NEGATIVE_INFINITY;
        float maxY = Float.NEGATIVE_INFINITY;
        for (int k = 0; k < 5; k++) {
            final Keypoint kp = keypoints[k];
            if (kp.confidence <= FACE_KP_CONF_MIN) continue;
            visibleCount++;
            if (kp.x < minX) minX = kp.x;
            if (kp.y < minY) minY = kp.y;
            if (kp.x > maxX) maxX = kp.x;
            if (kp.y > maxY) maxY = kp.y;
        }
        if (visibleCount < 2) return null;

        final float w = maxX - minX;
        final float h = maxY - minY;
        final float size = Math.max(w, h); // carré
        final float centerX = (minX + maxX) / 2f;
        final float centerY = (minY + maxY) / 2f;
        final float halfSize = (size * (1f + facePadding)) / 2f;

        return new Bbox(
                Math.max(0f, centerX - halfSize),
                Math.max(0f, centerY - halfSize),
                Math.min((float) srcW, centerX + halfSize),
                Math.min((float) srcH, centerY + halfSize));
    }
}
