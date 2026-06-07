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
import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Bbox;

/**
 * NanoDet-Plus-m 320 sentinel detector — anchor-free, 4 stride levels
 * {@code [8, 16, 32, 64]}. Output {@code [1, 2125, 112]} = 80 class scores
 * (already post-sigmoid in this export) + 32 bbox regression (4 × reg_max+1
 * = 4 × 8) decoded via distribution focal loss.
 *
 * <p>Port natif Java de {@code NanoDetSentinelDetector.swift} (iOS), qui est
 * lui-même un port ligne-à-ligne du POC {@code private/extensions/basarunaa/
 * src/detectors/nanodet.js}. Pour la V2.5 sentinel two-tier vidéo Android :
 * le scheduler JS lance ce sentinel léger ~10 Hz (~12ms inference) entre
 * deux YOLO full pose ~1 Hz (~80ms), pour smooth-tracker les positions
 * entre 2 verdicts gender et event-trigger un YOLO refresh quand une
 * nouvelle personne entre dans le frame.
 *
 * <p>Bboxes person-only (classIdx=0), pas de keypoint, pas de gender, pas
 * de NSFW. La fusion gender + matching face↔body reste à charge du YOLO
 * full pose.
 */
@NullMarked
public final class NanoDetSentinelDetector implements AutoCloseable {
    private static final String TAG = "Basarunaa";
    private static final String MODEL = "nanodet-plus-m_320.onnx";
    private static final int INPUT_SIZE = 320;
    private static final int NUM_CLASSES = 80;
    private static final int PERSON_CLASS_INDEX = 0;
    private static final int REG_MAX = 7;
    private static final int REG_LEN = REG_MAX + 1; // 8
    private static final int FEAT_LEN = NUM_CLASSES + 4 * REG_LEN; // 80 + 32 = 112
    private static final int[] STRIDES = {8, 16, 32, 64};
    /** Per POC default — sentinel intentionally permissive vs YOLO body 0.25. */
    private static final float CONF_THRESHOLD_FALLBACK = 0.3f;
    private static final float IOU_THRESHOLD = 0.5f;
    private static final float MIN_BOX_SIZE = 8f;

    private final OrtSession session;
    private final String inputName;
    private final String outputName;
    private final GridCell[] grids;

    private static final class GridCell {
        final int x;
        final int y;
        final int stride;

        GridCell(int x, int y, int stride) {
            this.x = x;
            this.y = y;
            this.stride = stride;
        }
    }

    public NanoDetSentinelDetector() throws OrtException, IOException {
        session = OrtRuntime.loadModel(MODEL);
        inputName = session.getInputNames().iterator().next();
        outputName = session.getOutputNames().iterator().next();

        final ArrayList<GridCell> built = new ArrayList<>(2125);
        for (int stride : STRIDES) {
            final int size = (INPUT_SIZE + stride - 1) / stride; // ceil
            for (int y = 0; y < size; y++) {
                for (int x = 0; x < size; x++) {
                    built.add(new GridCell(x, y, stride));
                }
            }
        }
        grids = built.toArray(new GridCell[0]);
        Log.i(TAG, "[NanoDet] loaded grids=%d (model=%s)", grids.length, MODEL);
    }

    /**
     * Détecte les bboxes person dans l'image et retourne en coordonnées
     * source. {@code confThreshold <= 0} → utilise {@link #CONF_THRESHOLD_FALLBACK}.
     */
    public List<Bbox> detect(Bitmap src, float confThreshold) throws OrtException {
        final int srcW = src.getWidth();
        final int srcH = src.getHeight();

        final Letterbox.Result lb = Letterbox.apply(src, INPUT_SIZE);
        try (OnnxTensor input = OnnxTensor.createTensor(
                OrtRuntime.env(), lb.tensor,
                new long[]{1, 3, INPUT_SIZE, INPUT_SIZE})) {
            try (OrtSession.Result result = session.run(
                    Collections.singletonMap(inputName, input))) {
                final Iterator<Map.Entry<String, ai.onnxruntime.OnnxValue>> it =
                        result.iterator();
                if (!it.hasNext()) {
                    Log.w(TAG, "[NanoDet] empty output");
                    return Collections.emptyList();
                }
                final ai.onnxruntime.OnnxValue value = it.next().getValue();
                final float[][][] data = (float[][][]) value.getValue();
                final float threshold = confThreshold > 0f
                        ? confThreshold : CONF_THRESHOLD_FALLBACK;
                final List<ScoredBbox> raw =
                        postprocess(data, threshold, lb, srcW, srcH);
                return nms(raw);
            }
        }
    }

    /**
     * Décode {@code data[1][2125][112]} (cell-major) ou {@code data[1][112][2125]}
     * (channel-major) en bboxes person. Scores = class index 0 ; bbox = DFL
     * over les 32 derniers channels (4 × 8).
     */
    private List<ScoredBbox> postprocess(
            float[][][] data, float threshold, Letterbox.Result lb,
            int srcW, int srcH) {
        // data shape : [1, A, B]. On déduit le layout depuis A vs B :
        //   cell-major : A == grids.length (2125), B == featLen (112)
        //   channel-major : A == featLen (112), B == grids.length (2125)
        final float[][] plane = data[0];
        final int a = plane.length;
        final int b = a > 0 ? plane[0].length : 0;
        final boolean cellMajor;
        if (a == grids.length && b == FEAT_LEN) {
            cellMajor = true;
        } else if (a == FEAT_LEN && b == grids.length) {
            cellMajor = false;
        } else {
            Log.e(TAG, "[NanoDet] unexpected output shape: [1, %d, %d]", a, b);
            return Collections.emptyList();
        }

        final int regBaseChannel = NUM_CLASSES;
        final ArrayList<ScoredBbox> results = new ArrayList<>(64);

        final int cellCount = grids.length;
        for (int i = 0; i < cellCount; i++) {
            final float score = cellMajor
                    ? plane[i][PERSON_CLASS_INDEX]
                    : plane[PERSON_CLASS_INDEX][i];
            if (score < threshold) continue;

            final float[] distances = new float[4];
            for (int d = 0; d < 4; d++) {
                // Softmax sur REG_LEN bins, somme pondérée par index.
                float maxVal = Float.NEGATIVE_INFINITY;
                for (int r = 0; r < REG_LEN; r++) {
                    final int channel = regBaseChannel + d * REG_LEN + r;
                    final float v = cellMajor ? plane[i][channel] : plane[channel][i];
                    if (v > maxVal) maxVal = v;
                }
                float sum = 0f;
                float weighted = 0f;
                for (int r = 0; r < REG_LEN; r++) {
                    final int channel = regBaseChannel + d * REG_LEN + r;
                    final float v = cellMajor ? plane[i][channel] : plane[channel][i];
                    final float e = (float) Math.exp(v - maxVal);
                    sum += e;
                    weighted += e * r;
                }
                distances[d] = sum > 0f ? weighted / sum : 0f;
            }

            final GridCell cell = grids[i];
            final float st = cell.stride;
            final float cx = (cell.x + 0.5f) * st;
            final float cy = (cell.y + 0.5f) * st;
            // distances en strides → pixels letterboxed
            final float lbX1 = cx - distances[0] * st;
            final float lbY1 = cy - distances[1] * st;
            final float lbX2 = cx + distances[2] * st;
            final float lbY2 = cy + distances[3] * st;

            // Unmap letterbox → image source : (lbCoord - pad) / scale
            float srcX1 = (lbX1 - lb.padX) / lb.scale;
            float srcY1 = (lbY1 - lb.padY) / lb.scale;
            float srcX2 = (lbX2 - lb.padX) / lb.scale;
            float srcY2 = (lbY2 - lb.padY) / lb.scale;
            // Clip à l'image source
            if (srcX1 < 0f) srcX1 = 0f;
            if (srcY1 < 0f) srcY1 = 0f;
            if (srcX2 > srcW) srcX2 = srcW;
            if (srcY2 > srcH) srcY2 = srcH;
            if (srcX2 - srcX1 < MIN_BOX_SIZE) continue;
            if (srcY2 - srcY1 < MIN_BOX_SIZE) continue;

            results.add(new ScoredBbox(new Bbox(srcX1, srcY1, srcX2, srcY2), score));
        }

        return results;
    }

    /** Greedy NMS sur simple (bbox, confidence). Mirrors POC utils/nms.js. */
    private static List<Bbox> nms(List<ScoredBbox> boxes) {
        Collections.sort(boxes, (x, y) -> Float.compare(y.confidence, x.confidence));
        final ArrayList<Bbox> kept = new ArrayList<>(boxes.size());
        for (ScoredBbox b : boxes) {
            boolean suppressed = false;
            for (Bbox k : kept) {
                if (iou(b.bbox, k) > IOU_THRESHOLD) {
                    suppressed = true;
                    break;
                }
            }
            if (!suppressed) kept.add(b.bbox);
        }
        return kept;
    }

    private static float iou(Bbox a, Bbox b) {
        final float interX1 = Math.max(a.x1, b.x1);
        final float interY1 = Math.max(a.y1, b.y1);
        final float interX2 = Math.min(a.x2, b.x2);
        final float interY2 = Math.min(a.y2, b.y2);
        final float interW = interX2 - interX1;
        final float interH = interY2 - interY1;
        if (interW <= 0f || interH <= 0f) return 0f;
        final float interArea = interW * interH;
        final float aArea = (a.x2 - a.x1) * (a.y2 - a.y1);
        final float bArea = (b.x2 - b.x1) * (b.y2 - b.y1);
        final float unionArea = aArea + bArea - interArea;
        return unionArea > 0f ? interArea / unionArea : 0f;
    }

    @Override
    public void close() throws OrtException {
        session.close();
    }

    private static final class ScoredBbox {
        final Bbox bbox;
        final float confidence;

        ScoredBbox(Bbox bbox, float confidence) {
            this.bbox = bbox;
            this.confidence = confidence;
        }
    }
}
