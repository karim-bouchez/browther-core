/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import android.graphics.Bitmap;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;

import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Bbox;
import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.PersonDetection;
import org.chromium.chrome.browser.basarunaa.detectors.PoseDetector;

import java.util.List;

/**
 * Wrapper Phase 6.1 debug — run en parallèle un détecteur TFLite (GPU FP32) ET
 * un détecteur ORT_CPU sur la même bitmap, log les écarts détaillés, et
 * retourne le résultat <b>TFLite</b> (parité comportementale avec la pref
 * {@code kBasarunaaTfliteGpuEnabled} active).
 *
 * <p>Activable via {@code kBasarunaaTfliteCompareMode} (default false). Coût
 * ≈ ORT inference (~410ms Huawei) en plus par image → ne jamais laisser ON
 * en prod, c'est un outil d'investigation device-only.
 *
 * <p>Conçu pour l'incident 2026-06-10 (cf. memory
 * {@code feedback_tflite_bench_inference_not_accuracy}) : sur le desktop le
 * harness Python {@code private/scripts/diff-yolo-pose-ort-vs-tflite.py}
 * montre parité stricte ORT vs TFLite CPU (8 détections identiques, max_diff
 * 5e-6 score) sur image canonique. Le drift suspecté = Mali-G76 GPU FP32 →
 * FP24 sur Mul/Concat. Ce détecteur le mesure directement sur device.
 *
 * <p>Logs émis (tag {@code Basarunaa}) :
 * <pre>
 * [Compare] tflite=12 (88.5ms)  ort=5 (412.0ms)  delta=+7
 * [Compare] TFLite #0 (score=0.91) ≈ ORT #0 (iou=0.99, score_delta=+0.001)
 * [Compare] TFLite #7 (score=0.27) SANS ORT match (best_iou=0.18) — drift artifact ?
 * [Compare] ORT #2 (score=0.83) MANQUÉ par TFLite (best_iou=0.41) — gpu missed detection
 * </pre>
 */
@NullMarked
public final class ComparePoseDetector implements PoseDetector {
    private static final String TAG = "Basarunaa";
    private static final float MATCH_IOU_MIN = 0.5f;

    private final PoseDetector tflite;
    private final PoseDetector ort;

    public ComparePoseDetector(PoseDetector tflite, PoseDetector ort) {
        this.tflite = tflite;
        this.ort = ort;
    }

    @Override
    public List<PersonDetection> detect(
            Bitmap src, float confThreshold, float iouThreshold) throws Exception {
        final long t0 = System.nanoTime();
        final List<PersonDetection> tfliteResults = tflite.detect(src, confThreshold, iouThreshold);
        final long t1 = System.nanoTime();
        final List<PersonDetection> ortResults = ort.detect(src, confThreshold, iouThreshold);
        final long t2 = System.nanoTime();

        final double tfliteMs = (t1 - t0) / 1_000_000.0;
        final double ortMs = (t2 - t1) / 1_000_000.0;

        Log.i(TAG, "[Compare] tflite=%d (%.1fms)  ort=%d (%.1fms)  delta=%+d",
                tfliteResults.size(), tfliteMs,
                ortResults.size(), ortMs,
                tfliteResults.size() - ortResults.size());

        // Pour chaque détection TFLite : trouver son closest ORT et logger
        // l'IoU + le delta de score. Sans match >= seuil → flag drift artifact.
        for (int i = 0; i < tfliteResults.size(); i++) {
            final PersonDetection t = tfliteResults.get(i);
            float bestIou = 0f;
            int bestIdx = -1;
            for (int j = 0; j < ortResults.size(); j++) {
                final float v = bboxIou(t.bbox, ortResults.get(j).bbox);
                if (v > bestIou) {
                    bestIou = v;
                    bestIdx = j;
                }
            }
            if (bestIou < MATCH_IOU_MIN) {
                Log.w(TAG, "[Compare] TFLite #%d (score=%.3f) SANS ORT match"
                        + " (best_iou=%.3f) — drift artifact ?",
                        i, t.confidence, bestIou);
            } else {
                final PersonDetection o = ortResults.get(bestIdx);
                Log.d(TAG, "[Compare] TFLite #%d (score=%.3f) ≈ ORT #%d"
                        + " (iou=%.2f, score_delta=%+.3f)",
                        i, t.confidence, bestIdx, bestIou,
                        t.confidence - o.confidence);
            }
        }

        // Pour chaque détection ORT sans match TFLite → flag missed detection.
        for (int j = 0; j < ortResults.size(); j++) {
            final PersonDetection o = ortResults.get(j);
            float bestIou = 0f;
            for (PersonDetection t : tfliteResults) {
                final float v = bboxIou(o.bbox, t.bbox);
                if (v > bestIou) bestIou = v;
            }
            if (bestIou < MATCH_IOU_MIN) {
                Log.w(TAG, "[Compare] ORT #%d (score=%.3f) MANQUÉ par TFLite"
                        + " (best_iou=%.3f) — gpu missed detection",
                        j, o.confidence, bestIou);
            }
        }

        return tfliteResults;
    }

    @Override
    public void close() throws Exception {
        try {
            tflite.close();
        } finally {
            ort.close();
        }
    }

    /** Port {@link Nms#iou} (package-private là-bas, on duplique ici). */
    private static float bboxIou(Bbox a, Bbox b) {
        final float x1 = Math.max(a.x1, b.x1);
        final float y1 = Math.max(a.y1, b.y1);
        final float x2 = Math.min(a.x2, b.x2);
        final float y2 = Math.min(a.y2, b.y2);
        final float inter = Math.max(0f, x2 - x1) * Math.max(0f, y2 - y1);
        if (inter == 0f) return 0f;
        return inter / (a.area() + b.area() - inter);
    }
}
