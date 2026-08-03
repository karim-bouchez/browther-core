/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Singleton ML engine pour Basarunaa Android — **single-shot gender-v2n**
 * (migration 2026-07-13, cf. {@code private/docs/BASARUNAA_MOBILE_GENDER_V2N.md}).
 *
 * <p>Une inférence ORT (gender-v2n, {@link GenderV2nDetector}) donne persons +
 * genre 3 classes + keypoints. La cascade historique (YOLO-pose + YOLO-face +
 * genderage + PPLCNet + matching + synth bodies + NudeNet) est retirée du hot
 * path. Le moteur est un **PUR EXTRACTEUR** : il sérialise TOUTES les persons
 * (genre brut + conf) ; la décision de flou vit dans {@code core/policy.ts},
 * appliquée côté bundle android/ TS.
 *
 * <p>NSFW plein cadre : retiré du hot path (parité desktop = opt-in OFF par
 * défaut). TODO : ré-exposer en opt-in via {@code ApplyNsfw} comme iOS.
 *
 * <p>Sentinel NanoDet retiré (2026-08-03) — la vidéo est one-tier : le
 * scheduler TS envoie des analyzeImage gender-v2n à 250 ms en tracking
 * (cf. {@code src/android/video/pipeline.ts}).
 */
@NullMarked
public final class BasarunaaEngine {
    private static final String TAG = "Basarunaa";
    private static final float NMS_IOU_THRESHOLD = 0.5f;
    private static final String[] GENDER_NAMES = {"male", "female", "child"};

    /** Pool single-thread pour le pipeline full analyze (single-shot gender-v2n). */
    public static final ExecutorService PIPELINE_EXEC =
            Executors.newSingleThreadExecutor(r -> new Thread(r, "Basarunaa-Pipeline"));

    @Nullable private static volatile BasarunaaEngine sInstance;

    public static BasarunaaEngine getInstance() {
        BasarunaaEngine local = sInstance;
        if (local == null) {
            synchronized (BasarunaaEngine.class) {
                local = sInstance;
                if (local == null) {
                    local = new BasarunaaEngine();
                    sInstance = local;
                }
            }
        }
        return local;
    }

    @Nullable private GenderV2nDetector genderDetector;
    private boolean modelsFailed;

    private BasarunaaEngine() {
        Log.i(TAG, "[Engine] singleton created (single-shot gender-v2n)");
    }

    /**
     * Warmup ML async — charge la session ORT gender-v2n sur PIPELINE_EXEC,
     * avant la première AnalyzeImage.
     */
    public void warmupAsync() {
        PIPELINE_EXEC.execute(() -> {
            final long t0 = System.nanoTime();
            ensureModelsLoaded();
            final double ms = (System.nanoTime() - t0) / 1_000_000.0;
            if (modelsFailed) {
                Log.w(TAG, "[Engine] warmup pipeline failed after %.1fms", ms);
            } else {
                Log.i(TAG, "[Engine] warmup pipeline done in %.1fms", ms);
            }
        });
    }

    /**
     * Analyse une image encodée. Renvoie TOUTES les persons (genre 3 classes +
     * conf + keypoints) sérialisées — pas de décision de flou (policy en JS).
     *
     * <p>Signature conservée (appelée par {@code BasarunaaTabAnalyzer}). Les
     * params {@code mode}/{@code genderCertainty} ne sont plus utilisés par le
     * moteur (la policy vit côté JS) ; {@code confBody} pilote le seuil de
     * détection.
     */
    public BasarunaaResult analyze(int imageId, byte[] bytes, String mode,
                                   double confBody,
                                   double genderCertainty, String debugMode) {
        final long t0 = System.nanoTime();
        try {
            ensureModelsLoaded();
            if (modelsFailed || genderDetector == null) {
                Log.w(TAG, "[Engine] analyze imageId=%d skipped (models failed)", imageId);
                return BasarunaaResult.empty(imageId);
            }

            final Bitmap src = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
            if (src == null) {
                Log.w(TAG, "[Engine] analyze imageId=%d decode failed", imageId);
                return BasarunaaResult.empty(imageId);
            }

            try {
                final List<GenderV2nDecode.PersonRaw> persons =
                        genderDetector.detect(src, (float) confBody, NMS_IOU_THRESHOLD);
                final String personsJson = serializePersons(persons);
                // `decision` = vestigial (le RFO ne le forward plus au JS ; la
                // policy vit dans core/policy). Conservé pour la signature mojom.
                final String decision = persons.isEmpty() ? "keep" : "blur";
                final double elapsedMs = (System.nanoTime() - t0) / 1_000_000.0;
                Log.i(TAG, "[Engine] analyze imageId=%d %dx%d persons=%d %.1fms",
                        imageId, src.getWidth(), src.getHeight(), persons.size(), elapsedMs);
                return new BasarunaaResult(imageId, decision, personsJson, elapsedMs);
            } finally {
                src.recycle();
            }
        } catch (Throwable t) {
            final double elapsedMs = (System.nanoTime() - t0) / 1_000_000.0;
            Log.e(TAG, "[Engine] analyze imageId=" + imageId + " failed after "
                    + String.format(java.util.Locale.US, "%.1fms", elapsedMs), t);
            return BasarunaaResult.empty(imageId);
        }
    }

    private void ensureModelsLoaded() {
        if (genderDetector != null) {
            return;
        }
        try {
            genderDetector = new GenderV2nDetector();
        } catch (Throwable t) {
            Log.e(TAG, "[Engine] gender-v2n load failed; switching to no-op", t);
            modelsFailed = true;
        }
    }

    /**
     * Sérialise les persons brutes en JSON conforme au contrat natif partagé
     * (core/native-contract) : {@code {bbox, keypoints:[[x,y,c]],
     * gender:'male'|'female'|'child', genderConfidence}}.
     */
    private static String serializePersons(List<GenderV2nDecode.PersonRaw> persons)
            throws JSONException {
        final JSONArray arr = new JSONArray();
        for (GenderV2nDecode.PersonRaw p : persons) {
            final JSONObject o = new JSONObject();
            o.put("bbox", doubleArrayToJson(p.bbox));
            o.put("keypoints", keypointsToJson(p.keypoints));
            o.put("gender", GENDER_NAMES[p.genderClass]);
            o.put("genderConfidence", p.confidence);
            arr.put(o);
        }
        return arr.toString();
    }

    private static JSONArray doubleArrayToJson(double[] a) throws JSONException {
        final JSONArray out = new JSONArray();
        for (double v : a) out.put(v);
        return out;
    }

    /** Keypoints en ARRAYS {@code [[x,y,conf], ...]} (contrat partagé). */
    private static JSONArray keypointsToJson(GenderV2nDecode.Keypoint[] kps)
            throws JSONException {
        final JSONArray a = new JSONArray();
        for (GenderV2nDecode.Keypoint kp : kps) {
            final JSONArray k = new JSONArray();
            k.put(kp.x).put(kp.y).put(kp.confidence);
            a.put(k);
        }
        return a;
    }
}
