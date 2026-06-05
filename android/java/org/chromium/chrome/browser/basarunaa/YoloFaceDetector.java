/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import android.graphics.Bitmap;

import ai.onnxruntime.OnnxTensor;
import ai.onnxruntime.OnnxValue;
import ai.onnxruntime.OrtException;
import ai.onnxruntime.OrtSession;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Bbox;
import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.FaceDetection;
import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Keypoint;

/**
 * Détecteur YOLOv8n-Face : bbox visage + 5 landmarks (left_eye, right_eye,
 * nose, left_mouth, right_mouth).
 *
 * <p>Port natif de {@code private/extensions/basarunaa/src/detectors/
 * yolo_face.js}. 3 têtes FPN (strides 8, 16, 32), chacune de shape
 * {@code [1, 80, H, W]} où {@code 80 = 64 (DFL bbox) + 1 (conf) + 15 (5 × 3)}.
 *
 * <p>Décodage DFL (Distribution Focal Loss) : pour chaque distance bbox,
 * 16 bins avec softmax + somme pondérée → expected value en strides.
 *
 * <p>Les landmarks sont précisément ce dont InsightFace
 * {@code FaceAlign.normCrop} a besoin (5 points 112×112) — c'est l'avantage
 * principal du YOLOv8-face dans le POC.
 */
@NullMarked
public final class YoloFaceDetector implements AutoCloseable {
    private static final String TAG = "Basarunaa";
    private static final String MODEL = "yolov8n-face.onnx";
    private static final int INPUT_SIZE = 640;
    private static final int[] STRIDES = {8, 16, 32};
    private static final int DFL_BINS = 16;
    private static final int CONF_CHANNEL = 64; // après 64 channels DFL (4 × 16)
    private static final int LANDMARK_START = 65;

    private final OrtSession session;
    private final String inputName;
    private final String[] outputNames;

    public YoloFaceDetector() throws OrtException, IOException {
        session = OrtRuntime.loadModel(MODEL);
        inputName = session.getInputNames().iterator().next();
        // Préserve l'ordre de sortie ONNX (stride 8, 16, 32).
        outputNames = new String[session.getOutputNames().size()];
        int i = 0;
        for (Iterator<String> it = session.getOutputNames().iterator(); it.hasNext(); ) {
            outputNames[i++] = it.next();
        }
        Log.i(TAG, "[YoloFace] ready (input=%s, outputs=%d)", inputName, outputNames.length);
    }

    @Override
    public void close() throws OrtException {
        session.close();
    }

    public List<FaceDetection> detect(Bitmap src, float confThreshold, float iouThreshold)
            throws OrtException {
        final int srcW = src.getWidth();
        final int srcH = src.getHeight();
        final Letterbox.Result lb = Letterbox.apply(src, INPUT_SIZE);

        try (OnnxTensor input = OnnxTensor.createTensor(
                OrtRuntime.env(), lb.tensor, new long[] {1, 3, INPUT_SIZE, INPUT_SIZE});
                OrtSession.Result result = session.run(Map.of(inputName, input))) {
            // 3 sorties [1, 80, H, W] — on les unpacke en float[1][80][H][W].
            final float[][][][][] outs = new float[3][][][][];
            final long[][] dims = new long[3][];
            for (int fpn = 0; fpn < 3; fpn++) {
                final OnnxValue val = result.get(fpn);
                outs[fpn] = new float[][][][] {(float[][][]) val.getValue()};
                dims[fpn] = ((OnnxTensor) val).getInfo().getShape();
            }
            return postprocess(outs, dims, lb, srcW, srcH, confThreshold, iouThreshold);
        }
    }

    private static List<FaceDetection> postprocess(
            float[][][][][] outs,
            long[][] dims,
            Letterbox.Result lb,
            int srcW,
            int srcH,
            float confThreshold,
            float iouThreshold) {
        final ArrayList<FaceDetection> boxes = new ArrayList<>();

        for (int fpn = 0; fpn < 3; fpn++) {
            final int stride = STRIDES[fpn];
            // shape [1, 80, gridH, gridW] : outs[fpn][0][channel][gy][gx]
            final float[][][] data = outs[fpn][0];
            final int gridH = (int) dims[fpn][2];
            final int gridW = (int) dims[fpn][3];

            for (int gy = 0; gy < gridH; gy++) {
                for (int gx = 0; gx < gridW; gx++) {
                    final float conf = sigmoid(data[CONF_CHANNEL][gy][gx]);
                    if (conf < confThreshold) continue;

                    final float[] dists = decodeDfl(data, gx, gy);
                    final float ax = (gx + 0.5f) * stride;
                    final float ay = (gy + 0.5f) * stride;

                    // bbox en espace letterboxé puis remap.
                    final float lx1 = ax - dists[0] * stride;
                    final float ly1 = ay - dists[1] * stride;
                    final float lx2 = ax + dists[2] * stride;
                    final float ly2 = ay + dists[3] * stride;

                    final float x1 = Math.max(0f, (lx1 - lb.padX) / lb.scale);
                    final float y1 = Math.max(0f, (ly1 - lb.padY) / lb.scale);
                    final float x2 = Math.min((float) srcW, (lx2 - lb.padX) / lb.scale);
                    final float y2 = Math.min((float) srcH, (ly2 - lb.padY) / lb.scale);

                    // 5 landmarks : channels 65..79, format [x, y, visible] × 5.
                    final Keypoint[] landmarks = new Keypoint[5];
                    for (int l = 0; l < 5; l++) {
                        final int baseChannel = LANDMARK_START + l * 3;
                        final float lx = data[baseChannel][gy][gx];
                        final float ly = data[baseChannel + 1][gy][gx];
                        final float lv = data[baseChannel + 2][gy][gx];

                        final float origX = ((lx * stride + ax) - lb.padX) / lb.scale;
                        final float origY = ((ly * stride + ay) - lb.padY) / lb.scale;
                        landmarks[l] = new Keypoint(origX, origY, sigmoid(lv));
                    }

                    boxes.add(new FaceDetection(new Bbox(x1, y1, x2, y2), conf, landmarks));
                }
            }
        }
        return Nms.suppress(boxes, iouThreshold);
    }

    /**
     * Décode DFL pour une position anchor : 64 channels = 4 distances × 16 bins.
     * Softmax par distance, puis somme pondérée par index du bin → expected value.
     */
    private static float[] decodeDfl(float[][][] data, int gx, int gy) {
        final float[] dists = new float[4];
        final float[] vals = new float[DFL_BINS];
        final float[] exps = new float[DFL_BINS];

        for (int d = 0; d < 4; d++) {
            float maxVal = Float.NEGATIVE_INFINITY;
            for (int b = 0; b < DFL_BINS; b++) {
                final int ch = d * DFL_BINS + b;
                final float v = data[ch][gy][gx];
                vals[b] = v;
                if (v > maxVal) maxVal = v;
            }
            float sum = 0f;
            for (int b = 0; b < DFL_BINS; b++) {
                exps[b] = (float) Math.exp(vals[b] - maxVal);
                sum += exps[b];
            }
            float dist = 0f;
            for (int b = 0; b < DFL_BINS; b++) {
                dist += (exps[b] / sum) * b;
            }
            dists[d] = dist;
        }
        return dists;
    }

    private static float sigmoid(float x) {
        return 1f / (1f + (float) Math.exp(-x));
    }
}
