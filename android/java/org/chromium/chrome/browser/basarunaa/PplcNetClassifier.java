/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;

import ai.onnxruntime.OnnxTensor;
import ai.onnxruntime.OrtException;
import ai.onnxruntime.OrtSession;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;

import java.io.IOException;
import java.nio.FloatBuffer;
import java.util.Map;

import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Bbox;

/**
 * Classifier PP-LCNet pedestrian attribute — port natif de
 * {@code private/extensions/basarunaa/src/classifiers/pplcnet.js}.
 *
 * <p>Input : crop body bbox redimensionné en {@code 256×192} CHW float32
 * ImageNet-normalized (mean [0.485, 0.456, 0.406], std [0.229, 0.224, 0.225]).
 * Output : {@code [1, 26]} sigmoid logits = probabilités de chaque attribut
 * PULC person_attribute. <b>Index 22 = Female.</b>
 *
 * <p>Utilisé comme fallback gender quand le YOLO-face ne trouve pas de
 * visage (personne de dos, profil très serré, etc.) ou pour voter avec le
 * face classifier en dual mode (parité POC {@code _processDual}).
 *
 * <p>V1 Android : pas de body polygon mask (le POC utilise un mask pour
 * grayer le background, ici on crop juste la bbox). L'amélioration est
 * prévue V2 si on observe des dégradations gender sur dos visible.
 */
@NullMarked
public final class PplcNetClassifier implements AutoCloseable {
    private static final String TAG = "Basarunaa";
    private static final String MODEL = "pplcnet_pedestrian_attribute.onnx";
    private static final int INPUT_H = 256;
    private static final int INPUT_W = 192;
    private static final int FEMALE_ATTR_INDEX = 22;
    private static final float THRESHOLD = 0.5f;

    // ImageNet normalization mean/std (cf. preprocessForClassification POC).
    private static final float MEAN_R = 0.485f;
    private static final float MEAN_G = 0.456f;
    private static final float MEAN_B = 0.406f;
    private static final float STD_R = 0.229f;
    private static final float STD_G = 0.224f;
    private static final float STD_B = 0.225f;

    private final OrtSession session;
    private final String inputName;
    private final String outputName;

    public PplcNetClassifier() throws OrtException, IOException {
        session = OrtRuntime.loadModel(MODEL);
        inputName = session.getInputNames().iterator().next();
        outputName = session.getOutputNames().iterator().next();
        Log.i(TAG, "[PplcNet] ready (input=%s, output=%s)", inputName, outputName);
    }

    @Override
    public void close() throws OrtException {
        session.close();
    }

    /**
     * Classifie un body crop. Retourne un Result avec isFemale + confidence
     * (probabilité de la classe gagnante, ∈ [0.5, 1.0]).
     *
     * @param src image source complète
     * @param bbox bbox du body en coords source
     */
    public GenderAgeClassifier.Result classify(Bitmap src, Bbox bbox) throws OrtException {
        // Crop + resize 192×256 (W×H) sur fond gris (parité POC
        // preprocessForClassification).
        final Bitmap target = Bitmap.createBitmap(INPUT_W, INPUT_H, Bitmap.Config.ARGB_8888);
        try {
            final Canvas canvas = new Canvas(target);
            canvas.drawColor(Color.rgb(0x80, 0x80, 0x80));
            final Paint paint = new Paint(Paint.FILTER_BITMAP_FLAG | Paint.ANTI_ALIAS_FLAG);
            final Rect srcRect = new Rect(
                    Math.max(0, (int) bbox.x1),
                    Math.max(0, (int) bbox.y1),
                    Math.min(src.getWidth(), (int) bbox.x2),
                    Math.min(src.getHeight(), (int) bbox.y2));
            final Rect dstRect = new Rect(0, 0, INPUT_W, INPUT_H);
            canvas.drawBitmap(src, srcRect, dstRect, paint);

            final int area = INPUT_W * INPUT_H;
            final int[] argb = new int[area];
            target.getPixels(argb, 0, INPUT_W, 0, 0, INPUT_W, INPUT_H);

            final FloatBuffer chw = FloatBuffer.allocate(3 * area);
            final float[] r = new float[area];
            final float[] g = new float[area];
            final float[] b = new float[area];
            for (int i = 0; i < area; i++) {
                final int px = argb[i];
                r[i] = (((px >> 16) & 0xFF) / 255f - MEAN_R) / STD_R;
                g[i] = (((px >> 8) & 0xFF) / 255f - MEAN_G) / STD_G;
                b[i] = ((px & 0xFF) / 255f - MEAN_B) / STD_B;
            }
            chw.put(r);
            chw.put(g);
            chw.put(b);
            chw.flip();

            try (OnnxTensor input = OnnxTensor.createTensor(
                    OrtRuntime.env(), chw, new long[] {1, 3, INPUT_H, INPUT_W});
                    OrtSession.Result result = session.run(Map.of(inputName, input))) {
                final OnnxTensor outTensor = (OnnxTensor) result.get(0);
                final FloatBuffer flat = outTensor.getFloatBuffer();
                // Output sigmoid déjà appliqué dans le graph PULC → probabilités.
                // Index 22 = Female.
                final float femaleProb = flat.get(FEMALE_ATTR_INDEX);
                final boolean isFemale = femaleProb > THRESHOLD;
                final float confidence = isFemale ? femaleProb : 1f - femaleProb;
                return new GenderAgeClassifier.Result(isFemale, confidence);
            }
        } finally {
            target.recycle();
        }
    }
}
