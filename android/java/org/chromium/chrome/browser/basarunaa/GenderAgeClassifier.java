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
import java.util.Map;

/**
 * Classifier de genre InsightFace genderage — port natif du POC
 * {@code private/extensions/basarunaa/src/classifiers/onnx_generic.js}
 * configuré comme dans {@code src/offscreen.js#L130-139}.
 *
 * <p><b>Paramètres POC (à ne PAS divergir) :</b>
 * <ul>
 *   <li>Input 96×96, format CHW float32</li>
 *   <li>Normalization {@code 'raw'} : pixels 0-255 SANS division par 255,
 *       ordre RGB (pas BGR malgré la docstring obsolète de onnx_generic.js)</li>
 *   <li>Output : 4 logits (typiquement [male, female, age, ?]) — on softmax
 *       les 2 premiers (gender)</li>
 *   <li>{@code outputMode='binary_softmax'}, {@code femaleIndex=0}</li>
 * </ul>
 *
 * <p>L'entrée attendue est un Bitmap 96×96 déjà aligné par {@link FaceAlign}.
 */
@NullMarked
public final class GenderAgeClassifier implements AutoCloseable {
    private static final String TAG = "Basarunaa";
    private static final String MODEL = "genderage.onnx";
    private static final int INPUT_SIZE = 96;
    private static final int FEMALE_INDEX = 0;

    /** Résultat classification. */
    public static final class Result {
        public final boolean isFemale;
        public final float confidence; // probabilité de la classe gagnante

        Result(boolean isFemale, float confidence) {
            this.isFemale = isFemale;
            this.confidence = confidence;
        }
    }

    private final OrtSession session;
    private final String inputName;
    private final String outputName;

    public GenderAgeClassifier() throws OrtException, IOException {
        session = OrtRuntime.loadModel(MODEL);
        inputName = session.getInputNames().iterator().next();
        outputName = session.getOutputNames().iterator().next();
        Log.i(TAG, "[GenderAge] ready (input=%s, output=%s)", inputName, outputName);
    }

    @Override
    public void close() throws OrtException {
        session.close();
    }

    /**
     * Classifie un visage déjà aligné 96×96. Le bitmap est consommé en
     * lecture seule ; à l'appelant de le recycle().
     */
    public Result classify(Bitmap alignedFace) throws OrtException {
        if (alignedFace.getWidth() != INPUT_SIZE || alignedFace.getHeight() != INPUT_SIZE) {
            throw new IllegalArgumentException(
                    "GenderAgeClassifier expects "
                            + INPUT_SIZE
                            + "×"
                            + INPUT_SIZE
                            + " input, got "
                            + alignedFace.getWidth()
                            + "×"
                            + alignedFace.getHeight());
        }

        final int area = INPUT_SIZE * INPUT_SIZE;
        final int[] argb = new int[area];
        alignedFace.getPixels(argb, 0, INPUT_SIZE, 0, 0, INPUT_SIZE, INPUT_SIZE);

        // Normalization 'raw' : valeurs 0-255 RGB sans division, format CHW.
        final FloatBuffer chw = FloatBuffer.allocate(3 * area);
        final float[] r = new float[area];
        final float[] g = new float[area];
        final float[] b = new float[area];
        for (int i = 0; i < area; i++) {
            final int px = argb[i];
            r[i] = (px >> 16) & 0xFF;
            g[i] = (px >> 8) & 0xFF;
            b[i] = px & 0xFF;
        }
        chw.put(r);
        chw.put(g);
        chw.put(b);
        chw.flip();

        try (OnnxTensor input = OnnxTensor.createTensor(
                OrtRuntime.env(), chw, new long[] {1, 3, INPUT_SIZE, INPUT_SIZE});
                OrtSession.Result result = session.run(Map.of(inputName, input))) {
            // Output shape [1, N] (rank 2). Flat buffer pour rester robuste.
            final OnnxTensor outTensor = (OnnxTensor) result.get(0);
            final FloatBuffer flat = outTensor.getFloatBuffer();
            final long[] dims = outTensor.getInfo().getShape();
            final int n = (int) dims[dims.length - 1];
            final float[] logits = new float[n];
            flat.get(logits);
            return parseBinarySoftmax(logits);
        }
    }

    /**
     * Parse les 2 premiers logits (gender) via softmax → femaleProb.
     * Reproduit {@code _parseOutput#binary_softmax} du POC.
     */
    private static Result parseBinarySoftmax(float[] logits) {
        if (logits.length < 2) {
            throw new IllegalStateException(
                    "GenderAge output requires ≥2 logits, got " + logits.length);
        }
        // Softmax stable sur 2 valeurs.
        final float max = Math.max(logits[0], logits[1]);
        final float e0 = (float) Math.exp(logits[0] - max);
        final float e1 = (float) Math.exp(logits[1] - max);
        final float sum = e0 + e1;
        final float p0 = e0 / sum;
        final float p1 = e1 / sum;

        final float femaleProb = FEMALE_INDEX == 0 ? p0 : p1;
        final boolean isFemale = femaleProb > 0.5f;
        final float confidence = isFemale ? femaleProb : 1f - femaleProb;
        return new Result(isFemale, confidence);
    }
}
