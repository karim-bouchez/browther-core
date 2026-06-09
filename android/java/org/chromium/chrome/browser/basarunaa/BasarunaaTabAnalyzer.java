/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import org.jni_zero.CalledByNative;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;
import org.chromium.chrome.browser.preferences.BravePref;
import org.chromium.chrome.browser.profiles.ProfileManager;
import org.chromium.components.user_prefs.UserPrefs;

/**
 * Per-WebContents Java analyzer (mirror du pattern {@code SawtunaaPlayer}).
 *
 * <p>Reçoit les actions du JS via Mojo → {@code BasarunaaTabHelper} C++ → JNI :
 * {@link #analyzeImage}, {@link #cancelAnalyze}, {@link #pageReset}. Dispatch
 * vers le {@link BasarunaaEngine} singleton sur son pool single-thread global,
 * et retourne le verdict via {@link BasarunaaBridge#notifyAnalyzeReply} →
 * C++ → push Mojo {@code BasarunaaApply::Apply} au renderer source.
 *
 * <p>{@code mNativeHelper} = pointer brute du {@code BasarunaaTabHelper}
 * passé au constructeur. Stocké pour permettre le callback C++ via
 * {@link BasarunaaBridge}. Le tab helper se charge d'invalider ce
 * pointeur en cas de destruction (via {@link #destroy}).
 */
@NullMarked
public final class BasarunaaTabAnalyzer {
    private static final String TAG = "Basarunaa";

    private final int mInstanceId;
    private long mNativeHelper;

    /** Créé depuis JNI par {@code BasarunaaTabHelper::BasarunaaTabHelper}. */
    @CalledByNative
    public static BasarunaaTabAnalyzer create(int instanceId, long nativeHelper) {
        Log.i(TAG, "[Analyzer#%d] created (native=%d)", instanceId, nativeHelper);
        // Warmup async dès la création du 1er analyzer pour éviter le hit de
        // ~750ms cumulé de lazy-init des sessions ORT au 1er AnalyzeImage
        // (parité iOS BasarunaaPipeline.swift#warmup). No-op si déjà chargé.
        BasarunaaEngine.getInstance().warmupAsync();
        return new BasarunaaTabAnalyzer(instanceId, nativeHelper);
    }

    private BasarunaaTabAnalyzer(int instanceId, long nativeHelper) {
        mInstanceId = instanceId;
        mNativeHelper = nativeHelper;
    }

    /** Appelé depuis le dtor C++ pour invalider {@link #mNativeHelper}. */
    @CalledByNative
    public void destroy() {
        Log.i(TAG, "[Analyzer#%d] destroyed", mInstanceId);
        mNativeHelper = 0;
    }

    /**
     * Reçoit une image encodée du JS via Mojo → C++ → JNI. Dispatch sur le
     * pool {@link BasarunaaEngine#PIPELINE_EXEC} pour ne pas bloquer le
     * browser UI thread, et reply via {@link BasarunaaBridge#notifyAnalyzeReply}.
     *
     * @param imageId data-basarunaa-id côté DOM (unique par page)
     * @param bytes JPEG/PNG/WEBP encodés
     * @param mode pref Basarunaa.mode courante
     * @param confBody pref Basarunaa.conf_body courante
     * @param confFace pref Basarunaa.conf_face courante
     * @param genderCertainty pref Basarunaa.gender_certainty courante
     */
    @CalledByNative
    public void analyzeImage(int imageId, byte[] bytes, String mode,
                              double confBody, double confFace,
                              double genderCertainty) {
        // Snapshot le pointer pour le test après retour du pipeline (tab peut
        // disparaitre entre temps).
        final long nativeHelperSnapshot = mNativeHelper;
        final int instanceId = mInstanceId;
        // Lecture pref debug-mode AVANT dispatch sur PIPELINE_EXEC (UserPrefs
        // / ProfileManager requiert browser UI thread). Port iOS wantsCrops =
        // debugMode == "debug" (BasarunaaPipeline.swift#L213-214) — quand off,
        // skip BitmapDataUrl.encodeJpeg = ~300ms gagnés sur image dense.
        final String debugMode = UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                .getString(BravePref.BASARUNAA_DEBUG_MODE);
        BasarunaaEngine.PIPELINE_EXEC.execute(() -> {
            BasarunaaResult result;
            try {
                result = BasarunaaEngine.getInstance()
                        .analyze(imageId, bytes, mode, confBody, confFace,
                                genderCertainty, debugMode);
            } catch (Throwable t) {
                Log.e(TAG, "[Analyzer#" + instanceId + "] analyze failed", t);
                result = BasarunaaResult.empty(imageId);
            }
            // mNativeHelper peut être 0 si destroy() a tourné pendant l'inférence.
            // Snapshot ci-dessus + check final = race-free.
            if (nativeHelperSnapshot == 0 || mNativeHelper == 0) {
                Log.w(TAG, "[Analyzer#%d] reply dropped (native invalidated)", instanceId);
                return;
            }
            BasarunaaBridge.notifyAnalyzeReply(
                    nativeHelperSnapshot,
                    result.imageId,
                    result.decision,
                    result.personsJson,
                    result.elapsedMs);
        });
    }

    /**
     * V2.5 — reçoit un frame video pour sentinel léger (NanoDet) depuis le
     * scheduler JS via Mojo → C++ → JNI. Dispatch sur le pool
     * {@link BasarunaaEngine#PIPELINE_EXEC} comme {@link #analyzeImage} pour
     * sérialiser les inférences ORT (1 à la fois sur le browser). Reply via
     * {@link BasarunaaBridge#notifySentinelReply} → C++ → push Mojo
     * {@code BasarunaaApply::ApplyVideoSentinel} au renderer source.
     *
     * @param frameId compteur unique côté scheduler vidéo JS (pas confusion
     *                avec imageId du pipeline image)
     * @param bytes JPEG/PNG/WEBP de la frame vidéo capturée
     * @param confBody seuil de confiance person (pref slider, partagé avec
     *                 YOLO body)
     */
    @CalledByNative
    public void sentinelFrame(int frameId, byte[] bytes, double confBody) {
        final long nativeHelperSnapshot = mNativeHelper;
        final int instanceId = mInstanceId;
        // SENTINEL_EXEC (séparé de PIPELINE_EXEC qui sérialise les YOLO/NSFW
        // ~1 s sur Huawei CPU). Sans ça → sentinel attend la fin du pipeline
        // full → 1 résultat toutes les ~2 s, décalage visible (fix 2026-06-09).
        BasarunaaEngine.SENTINEL_EXEC.execute(() -> {
            String bboxesJson;
            try {
                final java.util.List<BasarunaaTypes.Bbox> bboxes =
                        BasarunaaEngine.getInstance().sentinel(bytes, confBody);
                bboxesJson = serializeBboxes(bboxes);
            } catch (Throwable t) {
                Log.e(TAG, "[Analyzer#" + instanceId + "] sentinel failed", t);
                bboxesJson = "[]";
            }
            if (nativeHelperSnapshot == 0 || mNativeHelper == 0) {
                Log.w(TAG, "[Analyzer#%d] sentinel reply dropped (native invalidated)",
                        instanceId);
                return;
            }
            BasarunaaBridge.notifySentinelReply(
                    nativeHelperSnapshot, frameId, bboxesJson);
        });
    }

    private static String serializeBboxes(java.util.List<BasarunaaTypes.Bbox> bboxes) {
        final StringBuilder sb = new StringBuilder(bboxes.size() * 32);
        sb.append('[');
        for (int i = 0; i < bboxes.size(); i++) {
            final BasarunaaTypes.Bbox b = bboxes.get(i);
            if (i > 0) sb.append(',');
            sb.append('[')
                    .append(b.x1).append(',')
                    .append(b.y1).append(',')
                    .append(b.x2).append(',')
                    .append(b.y2).append(']');
        }
        sb.append(']');
        return sb.toString();
    }

    @CalledByNative
    public void cancelAnalyze(int imageId) {
        Log.i(TAG, "[Analyzer#%d] cancelAnalyze id=%d (best-effort, no-op in stub)",
                mInstanceId, imageId);
        // Jalon 2.E pourra marquer imageId comme cancelled et le pipeline check
        // avant chaque inférence. Aujourd'hui pipeline trivial donc pas utile.
    }

    @CalledByNative
    public void pageReset(String url) {
        Log.i(TAG, "[Analyzer#%d] pageReset url=%s", mInstanceId, url);
        // Jalon 2.E : clear decision cache local éventuel + drop pending.
    }
}
