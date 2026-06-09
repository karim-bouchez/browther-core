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
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

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

    /** Pool single-thread pour le pipeline full analyze (YOLO + NudeNet +
     *  classifiers). 1 inférence "lourde" à la fois sur tout le browser. */
    public static final ExecutorService PIPELINE_EXEC =
            Executors.newSingleThreadExecutor(r -> new Thread(r, "Basarunaa-Pipeline"));

    /**
     * Pool single-thread DÉDIÉ au sentinel vidéo (V2.5). Sentinel et analyze
     * full doivent rouler en parallèle pour la fluidité vidéo : si on les
     * sérialise sur PIPELINE_EXEC, le sentinel attend pendant le YOLO full
     * (~1 s sur Huawei CPU) → 1 résultat toutes les ~2 s, complètement
     * décalé visuellement (incident remonté device 2026-06-09).
     *
     * <p>Thread-safe : {@link #sentinelDetector} (session ORT NanoDet) est
     * accédé uniquement depuis ce pool, les détecteurs/classifiers du
     * pipeline analyze (pose/face/gender/nude/body) sont accédés uniquement
     * depuis {@link #PIPELINE_EXEC}.
     */
    public static final ExecutorService SENTINEL_EXEC =
            Executors.newSingleThreadExecutor(r -> {
                final Thread t = new Thread(r, "Basarunaa-Sentinel");
                t.setDaemon(true);
                return t;
            });

    /**
     * Pool 3-thread pour parallel NudeNet NSFW + YOLO-pose + YOLO-face
     * détection. Port iOS BasarunaaPipeline.swift Phase 1 (detect) + Phase 2
     * (checkNsfw async, L173-203). On lance les 3 sessions concurrentes :
     *
     * <ul>
     *   <li>YOLO-pose (~80ms)</li>
     *   <li>YOLO-face (~80ms)</li>
     *   <li>NudeNet NSFW (~250ms)</li>
     * </ul>
     *
     * <p>Le pipeline body+face continue dès que les 2 YOLO finissent ; le
     * verdict NSFW est consommé à la fin (override si positif). Vs iOS on
     * retourne 1 seul reply au JS (pas 2 réponses séparées Phase 1+2) — gain
     * équivalent côté wall-clock.
     *
     * <p>Sessions ORT distinctes donc thread-safe. Huawei 8 cores avec
     * {@code intraOpThreads=4} → 12 threads OS partagés sur 8 cores en
     * parallel. Gain mesuré attendu : ~250ms par analyze sur image dense
     * (NSFW masqué par le matching+classify séquentiel).
     *
     * <p>Daemon threads pour pas bloquer le shutdown du process.
     */
    public static final ExecutorService PARALLEL_EXEC =
            Executors.newFixedThreadPool(3, r -> {
                final Thread t = new Thread(r, "Basarunaa-Parallel");
                t.setDaemon(true);
                return t;
            });

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
    /**
     * Sentinel detector lazy-loadé séparément des 5 sessions image-pipeline.
     * Le caller image-only ne paie pas le coût (~16 MB modèle) tant qu'aucune
     * vidéo n'a été tappée. Parité iOS {@code loadSentinelIfNeeded}
     * (BasarunaaPipeline.swift#L355-L360).
     */
    @Nullable private NanoDetSentinelDetector sentinelDetector;
    private boolean modelsFailed;
    private boolean sentinelFailed;

    private BasarunaaEngine() {
        Log.i(TAG, "[Engine] singleton created (Jalon 2.E.6 — V1 image pipeline + NSFW)");
    }

    /**
     * Warmup ML async (port iOS BasarunaaPipeline.swift#warmup) — charge
     * les 5 sessions ORT sur PIPELINE_EXEC avant la première AnalyzeImage,
     * pour éviter le hit de 750ms cumulé qui rend le 1er hit ~2s sur device.
     * À appeler dès qu'on sait que la feature est ENABLED (Bridge / TabAnalyzer
     * created), pas en hot path.
     *
     * <p>No-op si déjà loadé ou en cours de load.
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
        // Sentinel chargé sur son propre thread pour qu'il ne bloque pas la
        // 1ʳᵉ frame vidéo (et qu'il ne soit pas bloqué par l'init du pipeline
        // full qui charge 5 sessions ORT en série).
        SENTINEL_EXEC.execute(() -> {
            final long t0 = System.nanoTime();
            ensureSentinelLoaded();
            final double ms = (System.nanoTime() - t0) / 1_000_000.0;
            if (sentinelFailed) {
                Log.w(TAG, "[Engine] warmup sentinel failed after %.1fms", ms);
            } else {
                Log.i(TAG, "[Engine] warmup sentinel done in %.1fms", ms);
            }
        });
    }

    /**
     * Analyse une image encodée et retourne le verdict ML.
     *
     * <p>Appelé depuis {@code BasarunaaTabAnalyzer.runAnalyze} sur
     * {@link #PIPELINE_EXEC}.
     */
    public BasarunaaResult analyze(int imageId, byte[] bytes, String mode,
                                   double confBody, double confFace,
                                   double genderCertainty, String debugMode) {
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
                        (float) confFace, (float) genderCertainty, debugMode, t0);
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

    /**
     * Lazy-init du sentinel detector — séparé de {@link #ensureModelsLoaded}
     * pour rester aligné iOS (image-only callers payent pas le coût). Retourne
     * {@code null} si le load fail (sentinel devient no-op).
     */
    private @Nullable NanoDetSentinelDetector ensureSentinelLoaded() {
        if (sentinelDetector != null) return sentinelDetector;
        if (sentinelFailed) return null;
        try {
            sentinelDetector = new NanoDetSentinelDetector();
            return sentinelDetector;
        } catch (Throwable t) {
            Log.e(TAG, "[Engine] sentinel load failed; switching to no-op", t);
            sentinelFailed = true;
            return null;
        }
    }

    /**
     * Sentinel light-weight inference pour le scheduler vidéo two-tier
     * (parité iOS {@code BasarunaaPipeline.sentinel} L157-L167). Retourne
     * juste les bboxes person (pas de gender, pas de NSFW, pas de keypoint).
     * Doit être appelé depuis {@link #PIPELINE_EXEC} (sérialisation avec les
     * AnalyzeImage en cours).
     *
     * @return liste bboxes en coords image source, ou liste vide en cas
     *         d'erreur (best-effort fallback)
     */
    public List<Bbox> sentinel(byte[] bytes, double confThreshold) {
        final long t0 = System.nanoTime();
        try {
            final NanoDetSentinelDetector det = ensureSentinelLoaded();
            if (det == null) return java.util.Collections.emptyList();

            final Bitmap src = BitmapFactory.decodeByteArray(bytes, 0, bytes.length);
            if (src == null) {
                Log.w(TAG, "[Engine] sentinel decode failed");
                return java.util.Collections.emptyList();
            }
            try {
                final List<Bbox> bboxes = det.detect(src, (float) confThreshold);
                final double elapsedMs = (System.nanoTime() - t0) / 1_000_000.0;
                Log.i(TAG, "[Engine] sentinel %dx%d bboxes=%d %.1fms",
                        src.getWidth(), src.getHeight(), bboxes.size(), elapsedMs);
                return bboxes;
            } finally {
                src.recycle();
            }
        } catch (Throwable t) {
            final double elapsedMs = (System.nanoTime() - t0) / 1_000_000.0;
            Log.e(TAG, "[Engine] sentinel failed after "
                    + String.format(java.util.Locale.US, "%.1fms", elapsedMs), t);
            return java.util.Collections.emptyList();
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
            String debugMode,
            long t0Nanos) throws Exception {
        // Port iOS BasarunaaPipeline.swift L214 — quand le panel debug est
        // off, on skip toutes les encodeJpeg (BitmapDataUrl) qui coûtent
        // ~30-80ms × person. Cumulé ~300ms gagnés sur image dense.
        final boolean wantsCrops = "debug".equals(debugMode);
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

        // Étapes 2 + 3 + NSFW : 3 inférences en PARALLEL sur 3 threads.
        // Port iOS Phase 1/Phase 2 split — sauf qu'on retourne 1 seul reply
        // au JS (pas 2 réponses séparées). NSFW (~250ms) masqué par les
        // ~80ms YOLO + matching + classify séquentiel qui tournent ensuite.
        // Si NSFW positif : on jette le travail body/face (acceptable, ~waste
        // léger vs simplicité de pas avoir à cancel les Futures).
        final Future<NudeNetDetector.Result> nsfwFuture = PARALLEL_EXEC.submit(
                () -> nudenet.check(src));
        final Future<List<PersonDetection>> bodiesFuture = PARALLEL_EXEC.submit(
                () -> pose.detect(src, confBody, NMS_IOU_THRESHOLD));
        final Future<List<FaceDetection>> facesFuture = PARALLEL_EXEC.submit(
                () -> face.detect(src, confFace, NMS_IOU_THRESHOLD));
        final List<PersonDetection> bodies = awaitFuture(bodiesFuture);
        final List<FaceDetection> faces = awaitFuture(facesFuture);

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
                        faceCropDataUrl = wantsCrops ? BitmapDataUrl.encodeJpeg(aligned) : null;
                    } finally {
                        aligned.recycle();
                    }
                }
                // Split crop / classify (pattern iOS) : génère TOUJOURS le
                // crop (cheap ~3ms) pour l'inférence ORT, mais skip
                // BitmapDataUrl.encodeJpeg (~30-80ms) quand debug off.
                final Bitmap bodyCrop =
                        PplcNetClassifier.cropBody(src, bodyDet.bbox, bodyMask);
                final String bodyCropDataUrl;
                final GenderAgeClassifier.@Nullable Result bodyResult;
                try {
                    bodyCropDataUrl = wantsCrops ? BitmapDataUrl.encodeJpeg(bodyCrop) : null;
                    final boolean strongFace =
                            faceResult != null && faceResult.confidence >= genderCertainty;
                    bodyResult = strongFace ? null : classifyCropSafe(body, bodyCrop);
                } finally {
                    bodyCrop.recycle();
                }
                final GenderAgeClassifier.@Nullable Result picked =
                        pickBestGender(faceResult, bodyResult);
                final String classifierUsed =
                        picked == null ? "none" : (picked == faceResult ? "face" : "body");
                persons.add(Person.forBody(
                        bodyDet, matchedFace, picked, classifierUsed,
                        faceCropDataUrl, bodyCropDataUrl));
            } else {
                // Body sans face matchée → PPLCNet seul. Toujours crop +
                // inférence (pas de face confiante pour skip).
                final Bitmap bodyCrop =
                        PplcNetClassifier.cropBody(src, bodyDet.bbox, bodyMask);
                final String bodyCropDataUrl;
                final GenderAgeClassifier.@Nullable Result bodyResult;
                try {
                    bodyCropDataUrl = wantsCrops ? BitmapDataUrl.encodeJpeg(bodyCrop) : null;
                    bodyResult = classifyCropSafe(body, bodyCrop);
                } finally {
                    bodyCrop.recycle();
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
                    faceCropDataUrl = wantsCrops ? BitmapDataUrl.encodeJpeg(aligned) : null;
                } finally {
                    aligned.recycle();
                }
            }
            persons.add(Person.forUnmatchedFace(synth, unmatchedFace, cls, faceCropDataUrl));
        }

        // Étape 7 : decision globale — court-circuitée si NSFW positif.
        // On consume nsfwFuture EN DERNIER pour laisser le pipeline tourner
        // en parallèle. Si positif → override decision="nsfw" + persons vide
        // (full-frame blur côté JS), le travail body/face est jeté.
        final NudeNetDetector.Result nsfw = awaitFuture(nsfwFuture);
        final String decision;
        final String personsJson;
        if (nsfw.isNsfw) {
            decision = "nsfw";
            personsJson = "[]";
            Log.i(TAG, "[Engine] analyze imageId=%d NSFW=true classes=%s (overrides %d persons)",
                    imageId, nsfw.flaggedClasses, persons.size());
        } else {
            decision = decide(mode, persons, (float) genderCertainty);
            personsJson = serializePersons(persons);
        }

        final double elapsedMs = (System.nanoTime() - t0Nanos) / 1_000_000.0;
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
     * Unwrap un Future en propageant Exception ↦ rethrow propre. Évite la
     * pollution InterruptedException + ExecutionException dans le caller.
     */
    private static <T> T awaitFuture(Future<T> future) throws Exception {
        try {
            return future.get();
        } catch (ExecutionException e) {
            final Throwable cause = e.getCause();
            if (cause instanceof Exception) throw (Exception) cause;
            if (cause instanceof Error) throw (Error) cause;
            throw e;
        }
    }

    /**
     * Classify body via PPLCNet (inférence ORT sur crop pré-généré) en
     * swallowing les exceptions (best-effort fallback). Pattern split
     * porté de iOS Swift {@code BasarunaaPipeline} : on génère le crop
     * une fois et on décide de runner ORT après.
     */
    private static GenderAgeClassifier.@Nullable Result classifyCropSafe(
            PplcNetClassifier classifier, Bitmap crop) {
        try {
            return classifier.classifyCrop(crop);
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
