/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import android.graphics.Bitmap;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;

import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Bbox;
import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Keypoint;
import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.PersonDetection;
import org.chromium.chrome.browser.basarunaa.detectors.PoseDetector;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Variante TFLite du {@link YoloPoseDetector} — pendant du runtime ORT, port
 * ligne-à-ligne du post-process pour rester en parité comportementale stricte
 * (les bboxes/keypoints/face dérivée doivent être identiques à ε près).
 *
 * <p>Différences runtime :
 * <ul>
 *   <li>Input layout {@code [1, 640, 640, 3]} NHWC (onnx2tf transpose les
 *       inputs 4D image). Utilise {@link Letterbox#applyNhwc}.</li>
 *   <li>Output layout : introspection runtime via {@link
 *       org.tensorflow.lite.Tensor#shape()}. Le modèle YOLO11n-Pose est rank-3
 *       en sortie ({@code [1, 56, N]}) — onnx2tf ne transpose pas les rank-3,
 *       donc on retombe sur le même layout C-major que le ORT detector. Filet
 *       de sécurité si une variante du modèle pose la sortie en {@code [1, N,
 *       56]}, on remappe au runtime.</li>
 *   <li>Délégation GPU activée selon le {@link BasarunaaBackend} retenu —
 *       {@code TFLITE_GPU_FP32} / {@code TFLITE_GPU_FP16}.</li>
 * </ul>
 *
 * <p>Asset : {@code assets/basarunaa/yolo11n-pose.fp32.tflite} (FP16 KO sur ce
 * modèle, max_diff 3.27 — cf. {@code docs/V3_GPU_BENCH.md} § Phase 1).
 */
@NullMarked
public final class YoloPoseTfliteDetector implements PoseDetector {
    private static final String TAG = "Basarunaa";
    private static final String MODEL_BASE = "yolo11n-pose";
    private static final int INPUT_SIZE = 640;
    private static final int NUM_KEYPOINTS = 17;
    private static final int NUM_FEATURES = 56; // 4 xywh + 1 score + 51 (17 × 3)
    private static final float FACE_KP_CONF_MIN = 0.3f;
    private static final float DEFAULT_FACE_PADDING = 0.4f;

    private final TfliteRuntime.LoadedModel model;
    private final boolean outputIsFeaturesFirst; // true → [1, 56, N], false → [1, N, 56]
    private final int outputNumDetections;
    private final int outputBufferElements;

    public YoloPoseTfliteDetector(BasarunaaBackend backend) throws IOException {
        // yolo-pose FP16 inutilisable (bug onnx2tf, max_diff 3.27). On force le
        // FP32 même quand le backend ambiant est TFLITE_GPU_FP16.
        final BasarunaaBackend effective =
                backend == BasarunaaBackend.TFLITE_GPU_FP16
                        ? BasarunaaBackend.TFLITE_GPU_FP32
                        : backend;
        final String assetName = TfliteRuntime.assetNameFor(MODEL_BASE, effective);
        model = TfliteRuntime.loadModel(assetName, effective);

        final int[] outShape = model.interpreter.getOutputTensor(0).shape();
        if (outShape.length != 3 || outShape[0] != 1) {
            throw new IllegalStateException(
                    "YoloPoseTflite: unexpected output rank/shape " + java.util.Arrays.toString(outShape));
        }
        if (outShape[1] == NUM_FEATURES) {
            outputIsFeaturesFirst = true;
            outputNumDetections = outShape[2];
        } else if (outShape[2] == NUM_FEATURES) {
            outputIsFeaturesFirst = false;
            outputNumDetections = outShape[1];
        } else {
            throw new IllegalStateException(
                    "YoloPoseTflite: cannot locate features axis in shape "
                            + java.util.Arrays.toString(outShape));
        }
        outputBufferElements = NUM_FEATURES * outputNumDetections;
        Log.i(TAG, "[YoloPoseTflite] ready (backend=%s, outShape=%s, featuresFirst=%b)",
                effective.name(), java.util.Arrays.toString(outShape), outputIsFeaturesFirst);
    }

    @Override
    public void close() {
        model.close();
    }

    /**
     * Bump conf threshold sur path TFLite GPU pour compenser le drift Mali
     * FP24 (Phase 6.1 fix v3/v4). Itérations device Huawei UBV0218815000852 :
     * <ul>
     *   <li>+0.00 : 20 dét vs 5 ORT (delta +15)</li>
     *   <li>+0.20 : 7 dét vs 5 (delta +2, fantômes restants 0.537/0.620)</li>
     *   <li>+0.40 : 5 dét vs 5 (delta 0) ← retenu</li>
     * </ul>
     * Tradeoff : avec slider body 0.25 + bump 0.40 = effective 0.65. Les
     * vraies personnes en bordure de visibilité (face cachée, dos tourné)
     * peuvent scorer 0.45-0.65 et seront perdues — User peut récupérer via
     * le slider conf_body du panel (descendre = thresh plus bas, max recovery).
     * Sur les devices sans drift (futurs Snapdragon/Tensor benchés en Phase
     * 6.2), cette marge est gratuite — quasi tous les anchors restent au-dessus.
     */
    private static final float TFLITE_CONF_BUMP = 0.40f;

    @Override
    public List<PersonDetection> detect(Bitmap src, float confThreshold, float iouThreshold) {
        final int srcW = src.getWidth();
        final int srcH = src.getHeight();
        final Letterbox.Result lb = Letterbox.applyNhwc(src, INPUT_SIZE);

        final ByteBuffer inputBuf = ByteBuffer.allocateDirect(4 * 3 * INPUT_SIZE * INPUT_SIZE)
                .order(ByteOrder.nativeOrder());
        inputBuf.asFloatBuffer().put(lb.tensor);

        final ByteBuffer outputBuf = ByteBuffer.allocateDirect(4 * outputBufferElements)
                .order(ByteOrder.nativeOrder());

        final Map<Integer, Object> outputs = new HashMap<>();
        outputs.put(0, outputBuf);
        model.interpreter.runForMultipleInputsOutputs(new Object[] {inputBuf}, outputs);

        outputBuf.rewind();
        final FloatBuffer flat = outputBuf.asFloatBuffer();
        return postprocess(flat, lb, srcW, srcH, confThreshold + TFLITE_CONF_BUMP, iouThreshold);
    }

    private List<PersonDetection> postprocess(
            FloatBuffer flat,
            Letterbox.Result lb,
            int srcW,
            int srcH,
            float confThreshold,
            float iouThreshold) {
        final int n = outputNumDetections;
        if (n == 0) return Collections.emptyList();

        final ArrayList<PersonDetection> boxes = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            final float score = readFeature(flat, 4, i);
            if (score < confThreshold) continue;

            final float cx = readFeature(flat, 0, i);
            final float cy = readFeature(flat, 1, i);
            final float w = readFeature(flat, 2, i);
            final float h = readFeature(flat, 3, i);

            final float x1 = Math.max(0f, (cx - w / 2f - lb.padX) / lb.scale);
            final float y1 = Math.max(0f, (cy - h / 2f - lb.padY) / lb.scale);
            final float x2 = Math.min((float) srcW, (cx + w / 2f - lb.padX) / lb.scale);
            final float y2 = Math.min((float) srcH, (cy + h / 2f - lb.padY) / lb.scale);

            // GPU drift filter (Phase 6.1) : Mali-G76 GPU FP32 (compute shader
            // OpenGL ES interne FP24) produit des anchors low-conf dont le
            // centre prédit (cx,cy) tombe HORS de l'image actuelle (dans la
            // zone de padding gris #808080). Le clamping max(0)/min(srcW/H)
            // ci-dessus convertit ça en bbox dégénérée (x1>x2 ou y1>y2 si la
            // bbox passe entièrement à côté de l'image, OU x2-x1≈0 si elle
            // chevauche un bord). Area=0 → IoU=0 avec tout → NMS jamais merge
            // → 15+ fantômes survivent. Filtre post-conversion ici car raw w/h
            // sont positives normales — c'est cx/cy qui sortent. ORT CPU n'a
            // jamais ce bug ; YoloPoseDetector.postprocess ne filtre pas par
            // parité POC.
            if (x2 - x1 < 1f || y2 - y1 < 1f) continue;

            final Keypoint[] keypoints = new Keypoint[NUM_KEYPOINTS];
            for (int k = 0; k < NUM_KEYPOINTS; k++) {
                final int base = 5 + k * 3;
                final float kx = (readFeature(flat, base, i) - lb.padX) / lb.scale;
                final float ky = (readFeature(flat, base + 1, i) - lb.padY) / lb.scale;
                final float kc = readFeature(flat, base + 2, i);
                keypoints[k] = new Keypoint(kx, ky, kc);
            }

            final Bbox bbox = new Bbox(x1, y1, x2, y2);
            final Bbox faceBbox = deriveFaceBbox(keypoints, srcW, srcH, DEFAULT_FACE_PADDING);
            boxes.add(new PersonDetection(bbox, score, keypoints, faceBbox));
        }
        return Nms.suppress(boxes, iouThreshold);
    }

    /**
     * Lit la feature {@code f} de la détection {@code i} en gérant les 2
     * layouts possibles. Layout {@code [1, 56, N]} (features-first) → index
     * {@code f * N + i}. Layout {@code [1, N, 56]} → index {@code i * 56 + f}.
     */
    private float readFeature(FloatBuffer flat, int f, int i) {
        if (outputIsFeaturesFirst) {
            return flat.get(f * outputNumDetections + i);
        }
        return flat.get(i * NUM_FEATURES + f);
    }

    /**
     * Port du même {@code deriveFaceBbox} que {@link YoloPoseDetector} —
     * bbox face dérivée des 5 premiers keypoints (nez, yeux, oreilles). Doit
     * être identique au runtime ORT (parité comportementale stricte, cf.
     * memory {@code feedback_port_basarunaa_core_first}).
     */
    @Nullable
    private static Bbox deriveFaceBbox(
            Keypoint[] keypoints, int srcW, int srcH, float facePadding) {
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
        final float size = Math.max(w, h);
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
