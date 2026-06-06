/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.PointF;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Bbox;
import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.FaceDetection;
import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Keypoint;
import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.PersonDetection;

/**
 * Singleton ML engine pour Basarunaa Android (Jalon 2.E.5).
 *
 * <p>Pipeline V1 image (parité POC {@code _processDual}) :
 * <ol>
 *   <li>Décodage byte[] → Bitmap</li>
 *   <li>{@link NudeNetDetector} NSFW check (court-circuit full-frame
 *       si une classe EXPOSED dépasse 0.3). Skip Marqo (pas bundlé).</li>
 *   <li>YOLO-pose (body bbox + 17 keypoints + faceBbox dérivée)</li>
 *   <li>YOLO-face (face bbox + 5 landmarks)</li>
 *   <li>{@link PersonMatcher} face↔body global optimal</li>
 *   <li>Pour chaque body matched : {@link FaceAlign} + {@link
 *       GenderAgeClassifier}</li>
 *   <li>Pour chaque face unmatched : synthetic body bbox + face classifier</li>
 *   <li>Décision {@code "keep" | "blur" | "nsfw"} selon mode + gender +
 *       NSFW flag</li>
 * </ol>
 *
 * <p><b>Skipped V1 :</b> body polygon mask (PPLCNet sans mask : V2 si gender
 * dégradé sur dos visible), Marqo NSFW whole-image scoring (active les
 * classes COVERED, pas bundlé), NanoDet sentinel two-tier vidéo (bundlé,
 * câblé en V2).
 *
 * <p>Sessions ORT chargées paresseusement au premier {@link #analyze} via
 * double-checked locking. Séquentiel single-thread sur
 * {@link #PIPELINE_EXEC} (justifié par le bench POC : 2 sessions YOLO
 * concurrentes monopolisent les CPU cores plus longtemps qu'en séquentiel).
 */
@NullMarked
public final class BasarunaaEngine {
    private static final String TAG = "Basarunaa";
    private static final float NMS_IOU_THRESHOLD = 0.5f;
    private static final int ALIGN_OUTPUT_SIZE = 96;

    /** Pool single-thread global : 1 inférence ML à la fois sur tout le browser. */
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

    // Lazy-init sessions. Tous les accès depuis PIPELINE_EXEC donc pas besoin
    // de synchronization au-delà de l'init (assertion implicite : 1 thread).
    @Nullable private YoloPoseDetector poseDetector;
    @Nullable private YoloFaceDetector faceDetector;
    @Nullable private GenderAgeClassifier genderClassifier;
    @Nullable private NudeNetDetector nudeNetDetector;
    @Nullable private PplcNetClassifier bodyClassifier;
    private boolean modelsFailed;

    private BasarunaaEngine() {
        Log.i(TAG, "[Engine] singleton created (Jalon 2.E.6 — V1 image pipeline + NSFW)");
    }

    /**
     * Analyse une image encodée et retourne le verdict ML.
     *
     * <p>Appelé depuis {@code BasarunaaTabAnalyzer.runAnalyze} sur
     * {@link #PIPELINE_EXEC}.
     */
    public BasarunaaResult analyze(int imageId, byte[] bytes, String mode,
                                   double confBody, double confFace,
                                   double genderCertainty) {
        final long t0 = System.nanoTime();
        try {
            ensureModelsLoaded();
            if (modelsFailed) {
                Log.w(TAG, "[Engine] analyze imageId=%d skipped (models failed)", imageId);
                return BasarunaaResult.empty(imageId);
            }

            final Bitmap src = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
            if (src == null) {
                Log.w(TAG, "[Engine] analyze imageId=%d decode failed", imageId);
                return BasarunaaResult.empty(imageId);
            }

            try {
                return processImage(imageId, src, mode, (float) confBody,
                        (float) confFace, (float) genderCertainty, t0);
            } finally {
                src.recycle();
            }
        } catch (Throwable t) {
            // Capture tout : OrtException, IOException, OOM ML, JSONException.
            // L'utilisateur préfère un floutage manqué qu'un crash render.
            final double elapsedMs = (System.nanoTime() - t0) / 1_000_000.0;
            Log.e(TAG, "[Engine] analyze imageId=" + imageId + " failed after "
                    + String.format(java.util.Locale.US, "%.1fms", elapsedMs), t);
            return BasarunaaResult.empty(imageId);
        }
    }

    private void ensureModelsLoaded() {
        if (poseDetector != null
                && faceDetector != null
                && genderClassifier != null
                && nudeNetDetector != null
                && bodyClassifier != null) {
            return;
        }
        try {
            if (poseDetector == null) poseDetector = new YoloPoseDetector();
            if (faceDetector == null) faceDetector = new YoloFaceDetector();
            if (genderClassifier == null) genderClassifier = new GenderAgeClassifier();
            if (nudeNetDetector == null) nudeNetDetector = new NudeNetDetector();
            if (bodyClassifier == null) bodyClassifier = new PplcNetClassifier();
        } catch (Throwable t) {
            Log.e(TAG, "[Engine] models load failed; switching to no-op", t);
            modelsFailed = true;
        }
    }

    @SuppressWarnings("NullAway") // null-checks manuels avant chaque deref
    private BasarunaaResult processImage(
            int imageId,
            Bitmap src,
            String mode,
            float confBody,
            float confFace,
            float genderCertainty,
            long t0Nanos) throws Exception {
        // Copies locales non-null après ensureModelsLoaded (NullAway ne sait
        // pas que modelsFailed=false implique tous les fields non-null).
        final NudeNetDetector nudenet =
                java.util.Objects.requireNonNull(nudeNetDetector);
        final YoloPoseDetector pose = java.util.Objects.requireNonNull(poseDetector);
        final YoloFaceDetector face = java.util.Objects.requireNonNull(faceDetector);
        final GenderAgeClassifier gender =
                java.util.Objects.requireNonNull(genderClassifier);
        final PplcNetClassifier body =
                java.util.Objects.requireNonNull(bodyClassifier);

        final int imgW = src.getWidth();
        final int imgH = src.getHeight();

        // NSFW check en premier : court-circuite tout le pipeline body/face
        // si l'image contient une classe EXPOSED. Retourne decision="nsfw"
        // + personsJson vide (full-frame blur côté JS).
        final NudeNetDetector.Result nsfw = nudenet.check(src);
        if (nsfw.isNsfw) {
            final double elapsedMs = (System.nanoTime() - t0Nanos) / 1_000_000.0;
            Log.i(TAG, "[Engine] analyze imageId=%d NSFW=true classes=%s %.1fms",
                    imageId, nsfw.flaggedClasses, elapsedMs);
            return new BasarunaaResult(imageId, "nsfw", "[]", elapsedMs);
        }

        // Étapes 2 + 3 : YOLO-pose + YOLO-face séquentiels (single-thread).
        final List<PersonDetection> bodies =
                pose.detect(src, confBody, NMS_IOU_THRESHOLD);
        final List<FaceDetection> faces =
                face.detect(src, confFace, NMS_IOU_THRESHOLD);

        // Étape 4 : matching.
        final Map<Integer, PersonMatcher.Match> matched = PersonMatcher.match(bodies, faces);

        // Étape 5 : classify bodies matchés (face) + body sans face → PPLCNet.
        // Optim : skip PPLCNet quand la face est déjà très confiante
        // (>= genderCertainty seuil), économise ~150ms × person.
        final ArrayList<Person> persons = new ArrayList<>();
        for (int bi = 0; bi < bodies.size(); bi++) {
            final PersonDetection bodyDet = bodies.get(bi);
            final PersonMatcher.Match m = matched.get(bi);

            // Polygon mask body (parité POC core/body-polygon.ts) — grayer
            // le background avant que PPLCNet ne classifie.
            final BodyPolygon.Result polyResult =
                    BodyPolygon.build(bodyDet.keypoints, bodyDet.bbox, imgW, imgH);
            final List<PointF> bodyMask =
                    polyResult.isBodyShaped ? polyResult.points : null;

            if (m != null) {
                final FaceDetection matchedFace = m.face;
                final Bitmap aligned = FaceAlign.align(
                        src, bodyDet.keypoints, matchedFace.bbox, ALIGN_OUTPUT_SIZE);
                GenderAgeClassifier.@Nullable Result faceResult = null;
                @Nullable String faceCropDataUrl = null;
                if (aligned != null) {
                    try {
                        faceResult = gender.classify(aligned);
                        faceCropDataUrl = BitmapDataUrl.encodeJpeg(aligned);
                    } finally {
                        aligned.recycle();
                    }
                }
                final boolean strongFace =
                        faceResult != null && faceResult.confidence >= genderCertainty;
                final Bitmap[] bodyCropOut = new Bitmap[1];
                final GenderAgeClassifier.@Nullable Result bodyResult =
                        strongFace
                                ? null
                                : classifyBodySafe(
                                        body, src, bodyDet.bbox, bodyMask, bodyCropOut);
                @Nullable String bodyCropDataUrl = null;
                if (bodyCropOut[0] != null) {
                    bodyCropDataUrl = BitmapDataUrl.encodeJpeg(bodyCropOut[0]);
                    bodyCropOut[0].recycle();
                }
                final GenderAgeClassifier.@Nullable Result picked =
                        pickBestGender(faceResult, bodyResult);
                final String classifierUsed =
                        picked == null ? "none" : (picked == faceResult ? "face" : "body");
                persons.add(Person.forBody(
                        bodyDet, matchedFace, picked, classifierUsed,
                        faceCropDataUrl, bodyCropDataUrl));
            } else {
                // Body sans face matchée → PPLCNet seul.
                final Bitmap[] bodyCropOut = new Bitmap[1];
                final GenderAgeClassifier.@Nullable Result bodyResult =
                        classifyBodySafe(body, src, bodyDet.bbox, bodyMask, bodyCropOut);
                @Nullable String bodyCropDataUrl = null;
                if (bodyCropOut[0] != null) {
                    bodyCropDataUrl = BitmapDataUrl.encodeJpeg(bodyCropOut[0]);
                    bodyCropOut[0].recycle();
                }
                final String classifierUsed = bodyResult != null ? "body" : "none";
                persons.add(Person.forBody(
                        bodyDet, null, bodyResult, classifierUsed, null, bodyCropDataUrl));
            }
        }

        // Étape 6 : faces unmatched → synthetic body + classify face.
        final HashSet<Integer> usedFaceIndices = new HashSet<>();
        for (PersonMatcher.Match m : matched.values()) {
            usedFaceIndices.add(m.faceIndex);
        }
        for (int fi = 0; fi < faces.size(); fi++) {
            if (usedFaceIndices.contains(fi)) continue;
            final FaceDetection unmatchedFace = faces.get(fi);
            final Bbox synth = syntheticBody(unmatchedFace.bbox, imgW, imgH);
            final Bitmap aligned =
                    FaceAlign.align(src, null, unmatchedFace.bbox, ALIGN_OUTPUT_SIZE);
            GenderAgeClassifier.@Nullable Result cls = null;
            @Nullable String faceCropDataUrl = null;
            if (aligned != null) {
                try {
                    cls = gender.classify(aligned);
                    faceCropDataUrl = BitmapDataUrl.encodeJpeg(aligned);
                } finally {
                    aligned.recycle();
                }
            }
            persons.add(Person.forUnmatchedFace(synth, unmatchedFace, cls, faceCropDataUrl));
        }

        // Étape 7 : decision globale.
        final String decision = decide(mode, persons, (float) genderCertainty);

        final double elapsedMs = (System.nanoTime() - t0Nanos) / 1_000_000.0;
        final String personsJson = serializePersons(persons);
        Log.i(TAG, "[Engine] analyze imageId=%d %dx%d bodies=%d faces=%d → %s %.1fms",
                imageId, imgW, imgH, bodies.size(), faces.size(), decision, elapsedMs);

        // Log structured pour diag device : gender/conf/cu par person + bbox.
        // Tronqué à 800 char pour limiter la spam logcat sur images denses.
        if (!persons.isEmpty()) {
            final StringBuilder sb = new StringBuilder("[Engine] persons=[");
            for (int i = 0; i < persons.size(); i++) {
                final Person p = persons.get(i);
                if (i > 0) sb.append(", ");
                sb.append(String.format(java.util.Locale.US,
                        "{g=%s c=%.2f cu=%s bbox=[%.0f,%.0f,%.0f,%.0f]}",
                        p.gender == null ? "?" : p.gender,
                        p.genderConfidence,
                        p.classifierUsed,
                        p.bbox.x1, p.bbox.y1, p.bbox.x2, p.bbox.y2));
                if (sb.length() > 800) {
                    sb.append(", …");
                    break;
                }
            }
            sb.append("]");
            Log.i(TAG, sb.toString());
        }

        return new BasarunaaResult(imageId, decision, personsJson, elapsedMs);
    }

    /**
     * Classify body via PPLCNet en swallowing les exceptions ORT (best-effort
     * fallback : un body sans gender vaut mieux qu'un crash pipeline).
     */
    private static GenderAgeClassifier.@Nullable Result classifyBodySafe(
            PplcNetClassifier classifier,
            Bitmap src,
            Bbox bbox,
            @Nullable List<PointF> polygon,
            Bitmap @Nullable [] outCrop) {
        try {
            return classifier.classify(src, bbox, polygon, outCrop);
        } catch (Throwable t) {
            Log.w(TAG, "[Engine] body classify failed: " + t.getMessage());
            return null;
        }
    }

    /**
     * Choisit le verdict le plus confiant entre face et body. Si l'un est
     * null, retourne l'autre. Parité POC pipeline.js#_processDual.
     */
    private static GenderAgeClassifier.@Nullable Result pickBestGender(
            GenderAgeClassifier.@Nullable Result face,
            GenderAgeClassifier.@Nullable Result body) {
        if (face == null) return body;
        if (body == null) return face;
        return face.confidence >= body.confidence ? face : body;
    }

    /** Synthetic body bbox depuis une face unmatched (parité POC). */
    private static Bbox syntheticBody(Bbox faceBbox, int imgW, int imgH) {
        final float faceW = faceBbox.width();
        final float faceH = faceBbox.height();
        final float cx = (faceBbox.x1 + faceBbox.x2) / 2f;
        final float bodyW = faceW * 4f;
        return new Bbox(
                Math.max(0f, cx - bodyW / 2f),
                Math.max(0f, faceBbox.y1 - faceH * 0.3f),
                Math.min((float) imgW, cx + bodyW / 2f),
                Math.min((float) imgH, faceBbox.y1 + faceH * 7f));
    }

    /**
     * Décide {@code "keep"} ou {@code "blur"} selon mode + gender + seuil
     * de certitude. Pas de NSFW V1 (déporté en 2.E.6).
     */
    private static String decide(String mode, List<Person> persons, float genderCertainty) {
        if (persons.isEmpty()) return "keep";
        for (Person p : persons) {
            if (shouldBlur(p, mode, genderCertainty)) return "blur";
        }
        return "keep";
    }

    private static boolean shouldBlur(Person p, String mode, float genderCertainty) {
        if ("blur-all".equals(mode)) return true;
        if (p.gender == null) return false;
        if (p.genderConfidence < genderCertainty) return false;
        if ("blur-female".equals(mode)) return "female".equals(p.gender);
        if ("blur-male".equals(mode)) return "male".equals(p.gender);
        return false;
    }

    private static String serializePersons(List<Person> persons) throws JSONException {
        final JSONArray arr = new JSONArray();
        for (Person p : persons) {
            arr.put(p.toJson());
        }
        return arr.toString();
    }

    /** POJO interne représentant un Person sérialisable (cf. core/types.ts). */
    private static final class Person {
        final Bbox bbox;
        @Nullable final Bbox faceBbox;
        final Keypoint @Nullable [] keypoints;
        @Nullable final String gender; // "female" | "male"
        final float genderConfidence;
        final String classifierUsed; // "face" | "body" | "unmatched" | "none"
        final boolean isSyntheticBody;
        final float bodyConfidence;
        final float faceConfidence;
        @Nullable final String faceCropDataUrl;
        @Nullable final String bodyCropDataUrl;

        private Person(Bbox bbox, @Nullable Bbox faceBbox,
                       Keypoint @Nullable [] keypoints,
                       @Nullable String gender, float genderConfidence,
                       String classifierUsed, boolean isSyntheticBody,
                       float bodyConfidence, float faceConfidence,
                       @Nullable String faceCropDataUrl,
                       @Nullable String bodyCropDataUrl) {
            this.bbox = bbox;
            this.faceBbox = faceBbox;
            this.keypoints = keypoints;
            this.gender = gender;
            this.genderConfidence = genderConfidence;
            this.classifierUsed = classifierUsed;
            this.isSyntheticBody = isSyntheticBody;
            this.bodyConfidence = bodyConfidence;
            this.faceConfidence = faceConfidence;
            this.faceCropDataUrl = faceCropDataUrl;
            this.bodyCropDataUrl = bodyCropDataUrl;
        }

        static Person forBody(PersonDetection body, @Nullable FaceDetection matchedFace,
                              GenderAgeClassifier.@Nullable Result cls,
                              String classifierUsed,
                              @Nullable String faceCropDataUrl,
                              @Nullable String bodyCropDataUrl) {
            return new Person(
                    body.bbox,
                    matchedFace != null ? matchedFace.bbox : body.faceBbox,
                    body.keypoints,
                    cls != null ? (cls.isFemale ? "female" : "male") : null,
                    cls != null ? cls.confidence : 0f,
                    classifierUsed,
                    false,
                    body.confidence,
                    matchedFace != null ? matchedFace.confidence : 0f,
                    faceCropDataUrl,
                    bodyCropDataUrl);
        }

        static Person forUnmatchedFace(Bbox synth, FaceDetection face,
                                       GenderAgeClassifier.@Nullable Result cls,
                                       @Nullable String faceCropDataUrl) {
            return new Person(
                    synth,
                    face.bbox,
                    null,
                    cls != null ? (cls.isFemale ? "female" : "male") : null,
                    cls != null ? cls.confidence : 0f,
                    "unmatched",
                    true,
                    0f,
                    face.confidence,
                    faceCropDataUrl,
                    null);
        }

        @SuppressWarnings("NullAway") // null-checks explicites sur faceBbox/keypoints/gender
        JSONObject toJson() throws JSONException {
            final JSONObject o = new JSONObject();
            o.put("bbox", bboxToJson(bbox));
            if (faceBbox != null) o.put("faceBbox", bboxToJson(faceBbox));
            if (keypoints != null) o.put("keypoints", keypointsToJson(keypoints));
            if (gender != null) {
                o.put("gender", gender);
                o.put("genderConfidence", genderConfidence);
            }
            o.put("classifierUsed", classifierUsed);
            if (isSyntheticBody) o.put("isSyntheticBody", true);
            if (bodyConfidence > 0f) o.put("bodyConfidence", bodyConfidence);
            if (faceConfidence > 0f) o.put("faceConfidence", faceConfidence);
            if (faceCropDataUrl != null) o.put("faceCropDataUrl", faceCropDataUrl);
            if (bodyCropDataUrl != null) o.put("bodyCropDataUrl", bodyCropDataUrl);
            return o;
        }

        private static JSONArray bboxToJson(Bbox b) throws JSONException {
            final JSONArray a = new JSONArray();
            a.put(b.x1).put(b.y1).put(b.x2).put(b.y2);
            return a;
        }

        private static JSONArray keypointsToJson(Keypoint[] kps) throws JSONException {
            final JSONArray a = new JSONArray();
            for (Keypoint kp : kps) {
                final JSONObject k = new JSONObject();
                k.put("x", kp.x);
                k.put("y", kp.y);
                k.put("confidence", kp.confidence);
                a.put(k);
            }
            return a;
        }
    }
}
