/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import android.content.Context;
import android.content.res.AssetFileDescriptor;

import ai.onnxruntime.OrtEnvironment;
import ai.onnxruntime.OrtException;
import ai.onnxruntime.OrtSession;

import org.chromium.base.ContextUtils;
import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;

/**
 * Helper partagé ORT pour le pipeline Basarunaa Android (Jalon 2.E.2).
 *
 * <p>Sert de point unique pour : (1) accès au singleton {@link OrtEnvironment}
 * — thread-safe selon le contrat ORT, (2) lecture d'un asset bundlé
 * {@code assets/basarunaa/<name>.onnx} → {@link OrtSession} pré-configurée
 * avec les opts standardisées (BASIC_OPT, intra-op threads = min(4, cpus)),
 * (3) helper pour les détecteurs qui veulent surcharger les opts.
 *
 * <p>Centralise les choix qui doivent rester identiques entre les détecteurs
 * (yolo-pose, yolo-face, genderage, nanodet, pplcnet, nudenet) pour rester
 * cohérents avec les mesures Jalon 1 bench Huawei (avg 4 ms target).
 *
 * <p><b>NNAPI :</b> volontairement non activé en prod — sur Huawei
 * UBV0218815000852 NNAPI est 5-23× plus lent que CPU pur (driver NPU Kirin
 * absent). Cf. {@code feedback_basarunaa_android_nnapi_useless}. Disponible
 * via {@link BasarunaaBenchmark} pour les bencher futurs devices uniquement.
 *
 * <p><b>Threading :</b> {@link OrtSession#run} est thread-safe ORT-side, mais
 * en pratique on appelle toutes les sessions depuis le single-thread executor
 * {@code BasarunaaEngine.PIPELINE_EXEC} pour éviter que les 2 sessions YOLO
 * monopolisent les CPU cores plus longtemps qu'en séquentiel (cf. bench POC).
 */
@NullMarked
public final class OrtRuntime {
    private static final String TAG = "Basarunaa";
    private static final String ASSET_DIR = "basarunaa";

    /** Nombre max de threads intra-op ; le min entre 4 et le nombre de cores. */
    private static final int MAX_INTRA_OP_THREADS = 4;

    private OrtRuntime() {}

    /** Singleton ORT process-wide. Thread-safe selon contrat ORT. */
    public static OrtEnvironment env() {
        return OrtEnvironment.getEnvironment();
    }

    /** Opts par défaut : BASIC_OPT + threads = min(4, cpus), CPU backend. */
    public static OrtSession.SessionOptions defaultOptions() throws OrtException {
        final OrtSession.SessionOptions opts = new OrtSession.SessionOptions();
        opts.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.BASIC_OPT);
        opts.setIntraOpNumThreads(intraOpThreads());
        return opts;
    }

    /** Nombre de threads intra-op effectif. */
    public static int intraOpThreads() {
        return Math.min(MAX_INTRA_OP_THREADS, Math.max(1, Runtime.getRuntime().availableProcessors()));
    }

    /**
     * Charge un modèle ONNX bundlé sous {@code assets/basarunaa/<name>} et
     * crée une session avec les opts par défaut.
     *
     * <p>Bloquant — appeler depuis {@code BasarunaaEngine.PIPELINE_EXEC} ou
     * un autre worker thread, jamais depuis l'UI thread.
     *
     * @param assetName ex. {@code "yolo11n-pose.onnx"}
     */
    public static OrtSession loadModel(String assetName) throws OrtException, IOException {
        return loadModel(assetName, defaultOptions());
    }

    /** Comme {@link #loadModel(String)} mais avec des opts custom. */
    public static OrtSession loadModel(String assetName, OrtSession.SessionOptions opts)
            throws OrtException, IOException {
        final long t0 = System.nanoTime();
        final byte[] bytes = readAsset(ASSET_DIR + "/" + assetName);
        final OrtSession session = env().createSession(bytes, opts);
        final double loadMs = (System.nanoTime() - t0) / 1_000_000.0;
        Log.i(TAG, "[Ort] loaded %s in %.1fms (%.1f MB)", assetName, loadMs,
                bytes.length / (1024.0 * 1024.0));
        return session;
    }

    /**
     * Taille en octets du modèle bundlé {@code assets/basarunaa/<name>}.
     * Sans uncompress puisque les .onnx sont marqués {@code disable_compression}
     * dans le BUILD.gn android_assets. Utile pour les rapports de bench.
     */
    public static long assetSizeBytes(String assetName) throws IOException {
        final Context ctx = ContextUtils.getApplicationContext();
        try (AssetFileDescriptor afd = ctx.getAssets().openFd(ASSET_DIR + "/" + assetName)) {
            return afd.getLength();
        }
    }

    private static byte[] readAsset(String path) throws IOException {
        final Context ctx = ContextUtils.getApplicationContext();
        try (InputStream is = ctx.getAssets().open(path);
                ByteArrayOutputStream baos = new ByteArrayOutputStream(16 * 1024 * 1024)) {
            final byte[] buf = new byte[64 * 1024];
            int n;
            while ((n = is.read(buf)) > 0) {
                baos.write(buf, 0, n);
            }
            return baos.toByteArray();
        }
    }
}
