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

import org.chromium.chrome.browser.basarunaa.detectors.NudeDetector;

import java.io.IOException;
import java.nio.FloatBuffer;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * NudeNet NSFW detector — port natif simplifié de
 * {@code private/extensions/basarunaa/src/classifiers/nsfw.js#_runNudenet}.
 *
 * <p><b>Différence avec le POC :</b> on n'a PAS embarqué Marqo ViT
 * (nsfw-marqo-vit-384.onnx 23 MB) dans le bundle Android pour économiser
 * la taille APK. Le POC l'utilise pour activer les classes
 * {@code *_COVERED} (faux positifs sur t-shirts/pantalons) quand
 * {@code marqoScore > 0.3}. Sans Marqo : on déclenche NSFW <b>uniquement</b>
 * sur les classes {@code *_EXPOSED} (parité comportement par défaut du
 * POC quand Marqo ne flag pas).
 *
 * <p>Format ONNX : input {@code [1, 3, 320, 320]} float32, output
 * {@code [1, 22, 2100]} YOLO-style : 4 (xywh) + 18 classes. Letterbox
 * gris #808080, normalize /255 RGB.
 *
 * <p>Pour la V1 Android, on ne retourne que {@code isNsfw} (bool global)
 * — on ne remonte pas les bboxes des body parts (utilisées seulement pour
 * le debug overlay POC, non câblé Android V1).
 */
@NullMarked
public final class NudeNetDetector implements NudeDetector {
    private static final String TAG = "Basarunaa";
    private static final String MODEL = "nudenet-320.onnx";
    private static final int INPUT_SIZE = 320;
    private static final int NUM_CLASSES = 18;
    private static final float CONF_THRESHOLD = 0.5f; // parité nsfw.js (0.3 → 0.5 : faux positifs objets allongés)

    /** 18 classes NudeNet (cf. nsfw.js POC). */
    public static final String[] CLASSES = {
            "FEMALE_GENITALIA_COVERED",
            "FACE_FEMALE",
            "BUTTOCKS_EXPOSED",
            "FEMALE_BREAST_EXPOSED",
            "FEMALE_GENITALIA_EXPOSED",
            "MALE_BREAST_EXPOSED",
            "ANUS_EXPOSED",
            "FEET_EXPOSED",
            "BELLY_COVERED",
            "FEET_COVERED",
            "ARMPITS_COVERED",
            "ARMPITS_EXPOSED",
            "FACE_MALE",
            "BELLY_EXPOSED",
            "MALE_GENITALIA_EXPOSED",
            "ANUS_COVERED",
            "FEMALE_BREAST_COVERED",
            "BUTTOCKS_COVERED",
    };

    /**
     * Classes qui déclenchent NSFW dès qu'elles dépassent le seuil. Parité
     * POC {@code FLAGGED_CLASSES} : uniquement les {@code *_EXPOSED}. Les
     * {@code *_COVERED} ne sont jamais flaggées Android V1 (sans Marqo,
     * faux positifs sur t-shirts/pantalons).
     */
    private static final Set<Integer> FLAGGED_CLASSES = new HashSet<>();

    static {
        FLAGGED_CLASSES.add(2); // BUTTOCKS_EXPOSED
        FLAGGED_CLASSES.add(3); // FEMALE_BREAST_EXPOSED
        FLAGGED_CLASSES.add(4); // FEMALE_GENITALIA_EXPOSED
        FLAGGED_CLASSES.add(5); // MALE_BREAST_EXPOSED
        FLAGGED_CLASSES.add(6); // ANUS_EXPOSED
        FLAGGED_CLASSES.add(14); // MALE_GENITALIA_EXPOSED
    }

    private final OrtSession session;
    private final String inputName;
    private final String outputName;

    public NudeNetDetector() throws OrtException, IOException {
        session = OrtRuntime.loadModel(MODEL);
        inputName = session.getInputNames().iterator().next();
        outputName = session.getOutputNames().iterator().next();
        Log.i(TAG, "[NudeNet] ready (input=%s, output=%s)", inputName, outputName);
    }

    @Override
    public void close() throws OrtException {
        session.close();
    }

    /** Résultat NSFW : flag global + classes EXPOSED détectées. */
    public static final class Result {
        public final boolean isNsfw;
        public final List<String> flaggedClasses;

        Result(boolean isNsfw, List<String> flaggedClasses) {
            this.isNsfw = isNsfw;
            this.flaggedClasses = flaggedClasses;
        }

        static Result empty() {
            return new Result(false, Collections.emptyList());
        }
    }

    /**
     * Détecte les NSFW body parts sur l'image source.
     *
     * <p>Bitmap source non modifié. À l'appelant de gérer son cycle de vie.
     */
    public Result check(Bitmap src) throws OrtException {
        // Letterbox 320×320 (réutilise le helper YOLO : mêmes contraintes
        // padding gris #808080 + RGB CHW [0,1] normalisé /255).
        final Letterbox.Result lb = Letterbox.apply(src, INPUT_SIZE);

        try (OnnxTensor input = OnnxTensor.createTensor(
                OrtRuntime.env(), lb.tensor, new long[] {1, 3, INPUT_SIZE, INPUT_SIZE});
                OrtSession.Result result = session.run(Map.of(inputName, input))) {
            // Output shape [1, 22, N] (rank 3) ou [1, 1, 22, N] (rank 4) selon
            // export. Flat buffer + dernière dim → robuste.
            final OnnxTensor outTensor = (OnnxTensor) result.get(0);
            final long[] dims = outTensor.getInfo().getShape();
            final int numDetections = (int) dims[dims.length - 1];
            final FloatBuffer flat = outTensor.getFloatBuffer();
            return postprocess(flat, numDetections);
        }
    }

    private static Result postprocess(FloatBuffer flat, int numDetections) {
        final ArrayList<String> flagged = new ArrayList<>();
        final HashSet<Integer> seenIndices = new HashSet<>();

        // Layout C-major : flat[f * numDetections + i] = features[f][i].
        // 22 features = 4 (xywh) + 18 classes.
        for (int i = 0; i < numDetections; i++) {
            int bestClass = 0;
            float bestConf = 0f;
            for (int c = 0; c < NUM_CLASSES; c++) {
                final float conf = flat.get((4 + c) * numDetections + i);
                if (conf > bestConf) {
                    bestConf = conf;
                    bestClass = c;
                }
            }
            if (bestConf < CONF_THRESHOLD) continue;
            if (!FLAGGED_CLASSES.contains(bestClass)) continue;
            if (seenIndices.add(bestClass)) {
                flagged.add(CLASSES[bestClass]);
            }
        }
        return new Result(!flagged.isEmpty(), flagged);
    }
}
