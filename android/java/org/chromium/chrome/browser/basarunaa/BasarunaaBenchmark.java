/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import ai.onnxruntime.NodeInfo;
import ai.onnxruntime.OnnxTensor;
import ai.onnxruntime.OrtEnvironment;
import ai.onnxruntime.OrtException;
import ai.onnxruntime.OrtSession;
import ai.onnxruntime.TensorInfo;

import org.chromium.base.Log;
import org.chromium.base.ThreadUtils;
import org.chromium.base.task.PostTask;
import org.chromium.base.task.TaskTraits;
import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;

import org.tensorflow.lite.Tensor;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import java.util.Random;

/**
 * Benchmark ORT inference latency on-device pour les 6 modèles Basarunaa —
 * Jalon 1 du port natif Android.
 *
 * <p>Charge le modèle ONNX depuis les assets bundlés ({@code assets/basarunaa/
 * <name>.onnx}, cf. {@code components/basarunaa/android_assets/BUILD.gn}) via
 * {@link OrtRuntime#loadModel}, exécute 5 warmups + N itérations sur des
 * entrées random, et rapporte {@code avg / p50 / p95 / max} en millisecondes
 * par inférence.
 *
 * <p>Générique : la shape d'entrée est découverte à l'exécution via
 * {@link OrtSession#getInputInfo}, donc on ajoute un modèle sans le
 * hardcoder ici. Les entrées dynamiques (dim = -1 ou 0) sont substituées
 * avec leur valeur réelle ({@link #DEFAULT_BATCH} pour la batch dim) avant
 * allocation du tenseur.
 *
 * <p>Run sur un thread {@link TaskTraits#USER_BLOCKING} pour ne pas bloquer
 * l'UI thread. Résultat logué sous le tag {@code Basarunaa} et retourné au
 * callback UI thread.
 *
 * <p><b>Budget temps réel</b> : Mac POC tape 64 ms YOLO + ~12 ms NanoDet
 * sentinel. Sur Android sans WebGPU, viser {@code < 200 ms YOLO} et
 * {@code < 30 ms sentinel} pour rester sous les seuils du POC vidéo
 * two-tier (YOLO_INTERVAL_TRACKING_MS=1000, sentinel toutes les 100 ms).
 */
@NullMarked
public final class BasarunaaBenchmark {
    private static final String TAG = "Basarunaa";

    /** Modèles bundlés sous {@code assets/basarunaa/} de l'APK. */
    public enum Model {
        // Le 3e arg est le nom de base TFLite (sans .fp32/.fp16/.tflite) — null
        // si pas de variante TFLite (yolov8n-face, nudenet-320 KO conversion).
        YOLO_POSE("yolo11n-pose.onnx", "yolo-pose", "yolo11n-pose"),
        YOLO_FACE("yolov8n-face.onnx", "yolo-face", null),
        GENDERAGE("genderage.onnx", "genderage", "genderage"),
        NANODET("nanodet-plus-m_320.onnx", "nanodet", "nanodet-plus-m_320"),
        PPLCNET("pplcnet_pedestrian_attribute.onnx", "pplcnet", "pplcnet_pedestrian_attribute"),
        NUDENET("nudenet-320.onnx", "nudenet", null);

        final String assetFilename;
        final String shortName;
        @Nullable final String tfliteBaseName;

        Model(String assetFilename, String shortName, @Nullable String tfliteBaseName) {
            this.assetFilename = assetFilename;
            this.shortName = shortName;
            this.tfliteBaseName = tfliteBaseName;
        }

        boolean hasTflite() {
            return tfliteBaseName != null;
        }
    }

    /** Backend à utiliser pour la session — ORT (CPU/NNAPI) ou TFLite (CPU/GPU). */
    public enum Backend {
        CPU,
        NNAPI,
        TFLITE_CPU,
        TFLITE_GPU_FP32,
        TFLITE_GPU_FP16;

        boolean isTflite() {
            return this == TFLITE_CPU
                    || this == TFLITE_GPU_FP32
                    || this == TFLITE_GPU_FP16;
        }

        BasarunaaBackend toRuntime() {
            switch (this) {
                case TFLITE_CPU:
                    return BasarunaaBackend.TFLITE_CPU;
                case TFLITE_GPU_FP32:
                    return BasarunaaBackend.TFLITE_GPU_FP32;
                case TFLITE_GPU_FP16:
                    return BasarunaaBackend.TFLITE_GPU_FP16;
                default:
                    return BasarunaaBackend.ORT_CPU;
            }
        }
    }

    private static final int WARMUP_ITERS = 5;
    private static final int DEFAULT_ITERS = 50;
    // Valeur par défaut pour les dim batch dynamiques (genderage = [N,3,96,96]).
    private static final long DEFAULT_BATCH = 1L;

    public interface Callback {
        /** Called on the UI thread when the benchmark completes (success or failure). */
        void onComplete(@Nullable Result result, @Nullable String error);
    }

    public static final class Result {
        public final Model model;
        public final Backend backend;
        public final int iters;
        public final double avgMs;
        public final double p50Ms;
        public final double p95Ms;
        public final double maxMs;
        public final int intraOpThreads;
        public final long modelSizeBytes;

        Result(
                Model model,
                Backend backend,
                int iters,
                double avgMs,
                double p50Ms,
                double p95Ms,
                double maxMs,
                int intraOpThreads,
                long modelSizeBytes) {
            this.model = model;
            this.backend = backend;
            this.iters = iters;
            this.avgMs = avgMs;
            this.p50Ms = p50Ms;
            this.p95Ms = p95Ms;
            this.maxMs = maxMs;
            this.intraOpThreads = intraOpThreads;
            this.modelSizeBytes = modelSizeBytes;
        }

        public String formatted() {
            return String.format(
                    java.util.Locale.US,
                    "%s [%s] avg=%.1fms p50=%.1fms p95=%.1fms max=%.1fms (n=%d, threads=%d,"
                            + " size=%.1fMB)",
                    model.shortName,
                    backend.name(),
                    avgMs,
                    p50Ms,
                    p95Ms,
                    maxMs,
                    iters,
                    intraOpThreads,
                    modelSizeBytes / (1024.0 * 1024.0));
        }
    }

    private BasarunaaBenchmark() {}

    /** Bench un modèle, default iters. */
    public static void run(Model model, Backend backend, Callback callback) {
        run(model, backend, DEFAULT_ITERS, callback);
    }

    public static void run(Model model, Backend backend, int iters, Callback callback) {
        ThreadUtils.assertOnUiThread();
        Log.i(TAG, "Bench start: %s [%s] iters=%d", model.shortName, backend, iters);
        PostTask.postTask(
                TaskTraits.USER_BLOCKING,
                () -> {
                    try {
                        Result r = runBlocking(model, backend, iters);
                        Log.i(TAG, "Bench OK: %s", r.formatted());
                        ThreadUtils.runOnUiThread(() -> callback.onComplete(r, null));
                    } catch (Throwable t) {
                        Log.e(TAG, "Bench failed: " + model.shortName, t);
                        final String err = t.getClass().getSimpleName() + ": " + t.getMessage();
                        ThreadUtils.runOnUiThread(() -> callback.onComplete(null, err));
                    }
                });
    }

    private static Result runBlocking(Model model, Backend backend, int iters)
            throws OrtException, IOException {
        if (backend.isTflite()) {
            return runBlockingTflite(model, backend, iters);
        }
        final OrtEnvironment env = OrtRuntime.env();
        final OrtSession.SessionOptions opts = OrtRuntime.defaultOptions();
        final int threads = OrtRuntime.intraOpThreads();

        if (backend == Backend.NNAPI) {
            // Falls back to CPU internally if ops aren't supported.
            opts.addNnapi();
        }

        final long modelSizeBytes = OrtRuntime.assetSizeBytes(model.assetFilename);

        try (OrtSession session = OrtRuntime.loadModel(model.assetFilename, opts)) {
            Log.i(
                    TAG,
                    "Session ready %s [%s] threads=%d inputs=%s outputs=%s",
                    model.shortName,
                    backend,
                    threads,
                    session.getInputNames(),
                    session.getOutputNames());

            // Alloue le(s) tenseur(s) d'entrée selon la shape découverte.
            final Map<String, OnnxTensor> inputs =
                    allocateRandomInputs(env, session, new Random(42));
            try {
                // Warmup — JIT, allocator warmup, NNAPI plan compilation.
                for (int i = 0; i < WARMUP_ITERS; i++) {
                    try (OrtSession.Result r = session.run(inputs)) {
                        // Drop output.
                    }
                }

                final long[] nanos = new long[iters];
                for (int i = 0; i < iters; i++) {
                    final long t0 = System.nanoTime();
                    try (OrtSession.Result r = session.run(inputs)) {
                        // Drop output.
                    }
                    nanos[i] = System.nanoTime() - t0;
                }

                Arrays.sort(nanos);
                long sum = 0L;
                for (long n : nanos) sum += n;
                final double avgMs = (sum / (double) iters) / 1_000_000.0;
                final double p50Ms = nanos[(int) (iters * 0.5)] / 1_000_000.0;
                final double p95Ms = nanos[(int) (iters * 0.95)] / 1_000_000.0;
                final double maxMs = nanos[iters - 1] / 1_000_000.0;
                return new Result(
                        model, backend, iters, avgMs, p50Ms, p95Ms, maxMs, threads,
                        modelSizeBytes);
            } finally {
                for (OnnxTensor t : inputs.values()) {
                    t.close();
                }
            }
        }
    }

    /**
     * Variante TFLite — pendant de {@link #runBlocking} pour les backends
     * {@code TFLITE_*}. Génère des inputs random à partir des shapes
     * découvertes via {@link Tensor#shape()}, run warmup + N iters,
     * rapporte les mêmes statistiques avg/p50/p95/max.
     */
    private static Result runBlockingTflite(Model model, Backend backend, int iters)
            throws IOException {
        if (!model.hasTflite()) {
            throw new IllegalArgumentException(
                    "Model " + model.shortName + " has no TFLite variant (onnx2tf KO)");
        }
        final BasarunaaBackend runtime = backend.toRuntime();
        final String assetName = TfliteRuntime.assetNameFor(model.tfliteBaseName, runtime);
        final long modelSizeBytes = TfliteRuntime.assetSizeBytes(assetName);
        final int threads = OrtRuntime.intraOpThreads();

        try (TfliteRuntime.LoadedModel loaded = TfliteRuntime.loadModel(assetName, runtime)) {
            // Allocation directe (native order) — TFLite exige ByteBuffer direct.
            // Utiliser Tensor.numBytes() au lieu de calculer shape × 4 : ça gère
            // les tensors fp16 (2 bytes/elem), int8, etc. et les shapes déjà
            // résolues par allocateTensors().
            final int numInputs = loaded.interpreter.getInputTensorCount();
            final int numOutputs = loaded.interpreter.getOutputTensorCount();
            final Random rnd = new Random(42);
            final ByteBuffer[] inputs = new ByteBuffer[numInputs];
            for (int i = 0; i < numInputs; i++) {
                final Tensor tensor = loaded.interpreter.getInputTensor(i);
                final int numBytes = tensor.numBytes();
                final ByteBuffer buf = ByteBuffer.allocateDirect(numBytes)
                        .order(ByteOrder.nativeOrder());
                // Remplit avec du random float32 — tous les inputs du POC sont
                // float32 (cf. POC JS detectors). Si jamais un futur modèle a
                // un input fp16, le buf est dimensionné en bytes donc OK, mais
                // les .put() vont consommer 2× plus de slots qu'attendu.
                // Pour la V1 bench, on assume float32 input.
                final FloatBuffer fb = buf.asFloatBuffer();
                final int floatCount = numBytes / 4;
                for (int j = 0; j < floatCount; j++) {
                    fb.put(rnd.nextFloat() * 2f - 1f);
                }
                inputs[i] = buf;
            }
            final Map<Integer, Object> outputs = new HashMap<>();
            for (int o = 0; o < numOutputs; o++) {
                final Tensor tensor = loaded.interpreter.getOutputTensor(o);
                // BufferOverflowException observée même après allocateTensors :
                // certains backends (GPU delegate) resize les tensors entre
                // l'init et le run, ou copyTo écrit plus que numBytes() rapporte
                // pour les quantized outputs. Pour le bench où on jette le
                // résultat, oversize 8× le buffer (~16 MB max) garantit qu'il
                // fit + n'a aucun impact sur la mesure latency (alloc one-shot
                // hors timer). Ne PAS reprendre ce pattern en prod détecteur :
                // utiliser un float[] primitif et laisser TFLite allouer.
                final int paddedBytes = Math.max(tensor.numBytes() * 8, 64 * 1024);
                final ByteBuffer outBuf = ByteBuffer.allocateDirect(paddedBytes)
                        .order(ByteOrder.nativeOrder());
                outputs.put(o, outBuf);
            }

            Log.i(TAG, "Session ready %s [%s] threads=%d delegateGpu=%s",
                    model.shortName, backend, threads, loaded.gpuDelegate != null);

            // Warmup — GPU delegate compile shaders au 1er run, ne pas
            // compter dans les iters.
            for (int i = 0; i < WARMUP_ITERS; i++) {
                loaded.interpreter.runForMultipleInputsOutputs(inputs, outputs);
            }

            final long[] nanos = new long[iters];
            for (int i = 0; i < iters; i++) {
                final long t0 = System.nanoTime();
                loaded.interpreter.runForMultipleInputsOutputs(inputs, outputs);
                nanos[i] = System.nanoTime() - t0;
            }

            Arrays.sort(nanos);
            long sum = 0L;
            for (long n : nanos) sum += n;
            final double avgMs = (sum / (double) iters) / 1_000_000.0;
            final double p50Ms = nanos[(int) (iters * 0.5)] / 1_000_000.0;
            final double p95Ms = nanos[(int) (iters * 0.95)] / 1_000_000.0;
            final double maxMs = nanos[iters - 1] / 1_000_000.0;
            return new Result(
                    model, backend, iters, avgMs, p50Ms, p95Ms, maxMs, threads, modelSizeBytes);
        }
    }

    /**
     * Alloue un tenseur float32 random pour chaque entrée du modèle. Les
     * dimensions dynamiques (dim &lt;= 0) sont substituées par
     * {@link #DEFAULT_BATCH}.
     */
    private static Map<String, OnnxTensor> allocateRandomInputs(
            OrtEnvironment env, OrtSession session, Random rnd) throws OrtException {
        final Map<String, OnnxTensor> result = new HashMap<>();
        for (Map.Entry<String, NodeInfo> e : session.getInputInfo().entrySet()) {
            final String name = e.getKey();
            final NodeInfo info = e.getValue();
            if (!(info.getInfo() instanceof TensorInfo)) {
                throw new IllegalStateException(
                        "Unsupported non-tensor input: " + name + " (" + info.getInfo() + ")");
            }
            final TensorInfo tInfo = (TensorInfo) info.getInfo();
            final long[] rawShape = tInfo.getShape();
            final long[] shape = new long[rawShape.length];
            int totalElements = 1;
            for (int i = 0; i < rawShape.length; i++) {
                shape[i] = rawShape[i] <= 0 ? DEFAULT_BATCH : rawShape[i];
                if (shape[i] > Integer.MAX_VALUE / Math.max(1, totalElements)) {
                    throw new IllegalStateException(
                            "Input " + name + " too large: shape=" + Arrays.toString(shape));
                }
                totalElements *= (int) shape[i];
            }
            // Tous les modèles Basarunaa attendent float32 (cf. POC JS detectors).
            final FloatBuffer buf = FloatBuffer.allocate(totalElements);
            for (int i = 0; i < totalElements; i++) {
                // Range [-1, 1] suffit pour le bench latency (pas de classification).
                buf.put(rnd.nextFloat() * 2f - 1f);
            }
            buf.flip();
            result.put(name, OnnxTensor.createTensor(env, buf, shape));
        }
        return result;
    }

}
