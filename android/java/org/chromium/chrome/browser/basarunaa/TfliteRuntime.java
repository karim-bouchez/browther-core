/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import android.content.Context;
import android.content.res.AssetFileDescriptor;

import org.chromium.base.ContextUtils;
import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;

import org.tensorflow.lite.Interpreter;
import org.tensorflow.lite.gpu.GpuDelegate;

import java.io.FileInputStream;
import java.io.IOException;
import java.nio.MappedByteBuffer;
import java.nio.channels.FileChannel;

/**
 * Helper partagé TFLite pour le pipeline Basarunaa Android — pendant de {@link
 * OrtRuntime}.
 *
 * <p>Sert de point unique pour : (1) résolution du nom d'asset bundlé selon la
 * précision retenue (fp32/fp16), (2) mmap d'un asset bundlé {@code
 * assets/basarunaa/<name>.<precision>.tflite} et création d'un {@link
 * Interpreter} pré-configuré, (3) configuration des delegates (GPU) selon le
 * {@link BasarunaaBackend}.
 *
 * <p><b>NNAPI :</b> volontairement non exposé — sur Huawei UBV0218815000852
 * NNAPI est 5-23× plus lent que CPU pur (driver NPU Kirin absent). Cf. memory
 * {@code feedback_basarunaa_android_nnapi_useless}.
 *
 * <p><b>Threading :</b> {@link Interpreter#run} n'est pas thread-safe — en
 * pratique on appelle toutes les sessions depuis le single-thread executor
 * {@code BasarunaaEngine.PIPELINE_EXEC} (parité {@link OrtRuntime}).
 *
 * <p><b>Lifecycle GPU :</b> chaque {@link Interpreter} possède son propre
 * {@link GpuDelegate} pour pouvoir le {@code close()} indépendamment ; un
 * delegate ne peut pas être partagé entre plusieurs interpreters TFLite
 * (contrat documenté).
 */
@NullMarked
public final class TfliteRuntime {
    private static final String TAG = "Basarunaa";
    private static final String ASSET_DIR = "basarunaa";

    private TfliteRuntime() {}

    /**
     * Wrapper Interpreter + delegate. Ferme les deux ressources lors du
     * {@link #close()} dans l'ordre inverse de leur création.
     */
    public static final class LoadedModel implements AutoCloseable {
        public final Interpreter interpreter;
        @Nullable public final GpuDelegate gpuDelegate;

        LoadedModel(Interpreter interpreter, @Nullable GpuDelegate gpuDelegate) {
            this.interpreter = interpreter;
            this.gpuDelegate = gpuDelegate;
        }

        @Override
        public void close() {
            interpreter.close();
            if (gpuDelegate != null) gpuDelegate.close();
        }
    }

    /**
     * Convention de nommage Browther : {@code <baseName>.<precision>.tflite}
     * conformément au script {@code private/scripts/convert-onnx-to-tflite.py}.
     *
     * @param baseName ex. {@code "yolo11n-pose"} (sans extension)
     * @param backend le {@link BasarunaaBackend} cible — détermine si on prend
     *     la variante {@code fp16} (GPU FP16 uniquement) ou {@code fp32}.
     */
    public static String assetNameFor(String baseName, BasarunaaBackend backend) {
        final String precision = backend.isFp16() ? "fp16" : "fp32";
        return baseName + "." + precision + ".tflite";
    }

    /**
     * Charge un modèle TFLite bundlé sous {@code assets/basarunaa/<name>} et
     * crée un {@link Interpreter} avec les opts adaptées au {@code backend}.
     *
     * <p>Bloquant — appeler depuis {@code BasarunaaEngine.PIPELINE_EXEC} ou un
     * autre worker thread, jamais depuis l'UI thread.
     *
     * @param assetName ex. {@code "yolo11n-pose.fp32.tflite"} (path complet
     *     dans {@code assets/basarunaa/})
     */
    public static LoadedModel loadModel(String assetName, BasarunaaBackend backend)
            throws IOException {
        final long t0 = System.nanoTime();
        final MappedByteBuffer model = mmapAsset(assetName);

        final Interpreter.Options opts = new Interpreter.Options();
        opts.setNumThreads(OrtRuntime.intraOpThreads());

        @Nullable GpuDelegate gpuDelegate = null;
        if (backend.isGpu()) {
            try {
                final GpuDelegate.Options gpuOpts = new GpuDelegate.Options()
                        .setPrecisionLossAllowed(backend.isFp16())
                        .setInferencePreference(
                                GpuDelegate.Options.INFERENCE_PREFERENCE_SUSTAINED_SPEED);
                gpuDelegate = new GpuDelegate(gpuOpts);
                opts.addDelegate(gpuDelegate);
            } catch (Throwable t) {
                Log.w(TAG, "[Tflite] GPU delegate init failed for %s, falling back to CPU",
                        assetName, t);
                gpuDelegate = null;
            }
        }

        final Interpreter interpreter = new Interpreter(model, opts);
        final double loadMs = (System.nanoTime() - t0) / 1_000_000.0;
        Log.i(TAG, "[Tflite] loaded %s in %.1fms (%.1f MB, backend=%s, gpu=%s)",
                assetName, loadMs, model.capacity() / (1024.0 * 1024.0),
                backend.name(), gpuDelegate != null);
        return new LoadedModel(interpreter, gpuDelegate);
    }

    /**
     * Taille en octets du modèle bundlé {@code assets/basarunaa/<name>}. Sans
     * uncompress puisque les .tflite sont marqués {@code disable_compression}
     * dans le BUILD.gn android_assets. Utile pour les rapports de bench.
     */
    public static long assetSizeBytes(String assetName) throws IOException {
        final Context ctx = ContextUtils.getApplicationContext();
        try (AssetFileDescriptor afd = ctx.getAssets().openFd(ASSET_DIR + "/" + assetName)) {
            return afd.getLength();
        }
    }

    /**
     * mmap d'un asset .tflite (bundlé non compressé, donc le fd a un offset et
     * une length explicites — {@code FileChannel#map} respecte ces deux).
     */
    private static MappedByteBuffer mmapAsset(String assetName) throws IOException {
        final Context ctx = ContextUtils.getApplicationContext();
        try (AssetFileDescriptor afd = ctx.getAssets().openFd(ASSET_DIR + "/" + assetName);
                FileInputStream fis = new FileInputStream(afd.getFileDescriptor());
                FileChannel channel = fis.getChannel()) {
            return channel.map(FileChannel.MapMode.READ_ONLY,
                    afd.getStartOffset(), afd.getDeclaredLength());
        }
    }
}
