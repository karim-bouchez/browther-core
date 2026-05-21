/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.sawtunaa;

import android.content.Context;

import ai.onnxruntime.OnnxTensor;
import ai.onnxruntime.OrtEnvironment;
import ai.onnxruntime.OrtException;
import ai.onnxruntime.OrtSession;

import org.chromium.base.ContextUtils;
import org.chromium.base.Log;
import org.chromium.base.ThreadUtils;
import org.chromium.base.task.PostTask;
import org.chromium.base.task.TaskTraits;
import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.FloatBuffer;
import java.util.Arrays;
import java.util.Random;

/**
 * Benchmark NSNet2 inference latency on-device.
 *
 * <p>Sawtunaa Voie B — Jalon 1. Charge {@code assets/sawtunaa/nsnet2-stateful.onnx}
 * (bundlé via {@code brave/components/sawtunaa/android_assets/BUILD.gn}) dans une
 * {@link OrtSession}, exécute 10 warmups + N itérations, et rapporte
 * {@code avg / p50 / p95 / max} en millisecondes par chunk.
 *
 * <p>L'objectif est de répondre à la question bloquante du spike "Voie B perf ?"
 * avant d'investir dans le pipeline audio temps réel (TabHelper + AudioPlayer).
 * Real-time budget par chunk 512 samples @ 48 kHz = 10.67 ms — la Voie B est
 * viable si avg < 12 ms ET p95 < 18 ms sur device mid-range.
 *
 * <p>Le benchmark tourne sur un thread {@link TaskTraits#USER_BLOCKING} (priorité
 * équivalente à un user gesture) pour ne pas bloquer l'UI thread, et écrit son
 * résultat dans logcat sous le tag {@code Sawtunaa}.
 */
@NullMarked
public final class SawtunaaBenchmark {
    private static final String TAG = "Sawtunaa";
    private static final String MODEL_ASSET_PATH = "sawtunaa/nsnet2-stateful.onnx";

    // NSNet2 shapes — must match the ONNX graph signature.
    private static final long[] INPUT_SHAPE = {1, 1, 513};
    private static final long[] GRU_SHAPE = {1, 1, 600};
    private static final int N_BINS = 513;
    private static final int GRU_HIDDEN = 600;

    private static final int WARMUP_ITERS = 10;
    private static final int DEFAULT_ITERS = 200;

    public interface Callback {
        /** Called on the UI thread when the benchmark completes (success or failure). */
        void onComplete(@Nullable Result result, @Nullable String error);
    }

    public static final class Result {
        public final int iters;
        public final double avgMs;
        public final double p50Ms;
        public final double p95Ms;
        public final double maxMs;
        public final boolean usedNnapi;
        public final int intraOpThreads;

        Result(int iters, double avgMs, double p50Ms, double p95Ms, double maxMs,
                boolean usedNnapi, int intraOpThreads) {
            this.iters = iters;
            this.avgMs = avgMs;
            this.p50Ms = p50Ms;
            this.p95Ms = p95Ms;
            this.maxMs = maxMs;
            this.usedNnapi = usedNnapi;
            this.intraOpThreads = intraOpThreads;
        }

        public String formatted() {
            return String.format(
                    java.util.Locale.US,
                    "iters=%d avg=%.2fms p50=%.2fms p95=%.2fms max=%.2fms (nnapi=%b, threads=%d)",
                    iters, avgMs, p50Ms, p95Ms, maxMs, usedNnapi, intraOpThreads);
        }
    }

    private SawtunaaBenchmark() {}

    public static void run(Callback callback) {
        run(DEFAULT_ITERS, callback);
    }

    public static void runFullPipeline(Callback callback) {
        runFullPipeline(DEFAULT_ITERS, callback);
    }

    public static void run(int iters, Callback callback) {
        ThreadUtils.assertOnUiThread();
        Log.i(TAG, "Bench start (iters=%d)", iters);
        PostTask.postTask(
                TaskTraits.USER_BLOCKING,
                () -> {
                    try {
                        Result r = runBlocking(iters);
                        Log.i(TAG, "Bench OK: %s", r.formatted());
                        ThreadUtils.runOnUiThread(() -> callback.onComplete(r, null));
                    } catch (Throwable t) {
                        Log.e(TAG, "Bench failed", t);
                        final String err = t.getClass().getSimpleName() + ": " + t.getMessage();
                        ThreadUtils.runOnUiThread(() -> callback.onComplete(null, err));
                    }
                });
    }

    /**
     * Bench the full pipeline: STFT → ORT inference → ISTFT → overlap-add.
     *
     * <p>Each iteration calls {@link NSNet2Processor#process} with one hop's worth of
     * samples ({@value NSNet2Processor#N_HOP} = ~10.67 ms of audio @ 48 kHz). After
     * the input ring is primed (first frame absorbs N_OVERLAP samples), each iter
     * runs exactly one STFT frame end-to-end — so the reported latency is directly
     * comparable to the real-time budget of {@code N_HOP/SAMPLE_RATE} = 10.67 ms.
     */
    public static void runFullPipeline(int iters, Callback callback) {
        ThreadUtils.assertOnUiThread();
        Log.i(TAG, "Full-pipeline bench start (iters=%d)", iters);
        PostTask.postTask(
                TaskTraits.USER_BLOCKING,
                () -> {
                    try {
                        Result r = runFullPipelineBlocking(iters);
                        Log.i(TAG, "Full-pipeline bench OK: %s", r.formatted());
                        ThreadUtils.runOnUiThread(() -> callback.onComplete(r, null));
                    } catch (Throwable t) {
                        Log.e(TAG, "Full-pipeline bench failed", t);
                        final String err = t.getClass().getSimpleName() + ": " + t.getMessage();
                        ThreadUtils.runOnUiThread(() -> callback.onComplete(null, err));
                    }
                });
    }

    private static Result runBlocking(int iters) throws OrtException, IOException {
        final Context ctx = ContextUtils.getApplicationContext();
        final byte[] modelBytes = loadAsset(ctx, MODEL_ASSET_PATH);
        Log.i(TAG, "Loaded NSNet2 model: %d bytes", modelBytes.length);

        final OrtEnvironment env = OrtEnvironment.getEnvironment();
        final OrtSession.SessionOptions opts = new OrtSession.SessionOptions();
        opts.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.BASIC_OPT);
        final int threads =
                Math.min(4, Math.max(1, Runtime.getRuntime().availableProcessors()));
        opts.setIntraOpNumThreads(threads);

        // Try NNAPI execution provider first — best perf on Android 8.1+ with NPU.
        // Falls back to CPU if not available or model has unsupported ops.
        boolean nnapiOk = false;
        try {
            opts.addNnapi();
            nnapiOk = true;
        } catch (OrtException e) {
            Log.w(TAG, "NNAPI EP unavailable: %s — falling back to CPU", e.getMessage());
        }

        try (OrtSession session = env.createSession(modelBytes, opts)) {
            Log.i(
                    TAG,
                    "Session ready (nnapi=%b, threads=%d, inputs=%s, outputs=%s)",
                    nnapiOk,
                    threads,
                    session.getInputNames(),
                    session.getOutputNames());

            final Random rnd = new Random(42);
            // Reusable input buffers (refilled with random data each iter).
            final FloatBuffer inputBuf = FloatBuffer.allocate(N_BINS);
            final FloatBuffer h1Buf = FloatBuffer.allocate(GRU_HIDDEN);
            final FloatBuffer h2Buf = FloatBuffer.allocate(GRU_HIDDEN);

            // Warmup — JIT, allocator warmup, NNAPI plan compilation.
            for (int i = 0; i < WARMUP_ITERS; i++) {
                runOnce(env, session, inputBuf, h1Buf, h2Buf, rnd);
            }

            // Measure.
            final long[] nanos = new long[iters];
            for (int i = 0; i < iters; i++) {
                final long t0 = System.nanoTime();
                runOnce(env, session, inputBuf, h1Buf, h2Buf, rnd);
                nanos[i] = System.nanoTime() - t0;
            }

            Arrays.sort(nanos);
            long sum = 0L;
            for (long n : nanos) sum += n;
            final double avgMs = (sum / (double) iters) / 1_000_000.0;
            final double p50Ms = nanos[(int) (iters * 0.5)] / 1_000_000.0;
            final double p95Ms = nanos[(int) (iters * 0.95)] / 1_000_000.0;
            final double maxMs = nanos[iters - 1] / 1_000_000.0;
            return new Result(iters, avgMs, p50Ms, p95Ms, maxMs, nnapiOk, threads);
        }
    }

    private static Result runFullPipelineBlocking(int iters) throws OrtException, IOException {
        final Context ctx = ContextUtils.getApplicationContext();
        final byte[] modelBytes = loadAsset(ctx, MODEL_ASSET_PATH);
        Log.i(TAG, "Loaded NSNet2 model: %d bytes", modelBytes.length);

        final NSNet2Processor.InitResult init = NSNet2Processor.create(modelBytes);
        try (NSNet2Processor proc = init.processor) {
            Log.i(
                    TAG,
                    "Pipeline ready (nnapi=%b, threads=%d, hop=%d, win=%d, fft=%d, bins=%d)",
                    init.usedNnapi,
                    init.intraOpThreads,
                    NSNet2Processor.N_HOP,
                    NSNet2Processor.N_WIN,
                    NSNet2Processor.N_FFT,
                    NSNet2Processor.N_BINS);

            final Random rnd = new Random(42);
            final float[] chunk = new float[NSNet2Processor.N_HOP];

            // Warmup: prime the ring + JIT + NNAPI plan. Need at least
            // ceil(N_WIN / N_HOP) = 2 calls before steady state.
            for (int i = 0; i < WARMUP_ITERS; i++) {
                fillRandom(chunk, rnd);
                proc.process(chunk);
            }

            final long[] nanos = new long[iters];
            for (int i = 0; i < iters; i++) {
                fillRandom(chunk, rnd);
                final long t0 = System.nanoTime();
                proc.process(chunk);
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
                    iters, avgMs, p50Ms, p95Ms, maxMs, init.usedNnapi, init.intraOpThreads);
        }
    }

    private static void fillRandom(float[] buf, Random rnd) {
        for (int i = 0; i < buf.length; i++) {
            buf[i] = rnd.nextFloat() * 2f - 1f;
        }
    }

    private static void runOnce(
            OrtEnvironment env,
            OrtSession session,
            FloatBuffer inputBuf,
            FloatBuffer h1Buf,
            FloatBuffer h2Buf,
            Random rnd)
            throws OrtException {
        fillRandom(inputBuf, rnd);
        fillRandom(h1Buf, rnd);
        fillRandom(h2Buf, rnd);
        try (OnnxTensor in = OnnxTensor.createTensor(env, inputBuf, INPUT_SHAPE);
                OnnxTensor h1 = OnnxTensor.createTensor(env, h1Buf, GRU_SHAPE);
                OnnxTensor h2 = OnnxTensor.createTensor(env, h2Buf, GRU_SHAPE)) {
            final java.util.HashMap<String, OnnxTensor> inputs = new java.util.HashMap<>(3);
            inputs.put("input", in);
            inputs.put("gru1_h_in", h1);
            inputs.put("gru2_h_in", h2);
            try (OrtSession.Result r = session.run(inputs)) {
                // Drop outputs — we only measure end-to-end latency.
            }
        }
    }

    private static void fillRandom(FloatBuffer buf, Random rnd) {
        buf.clear();
        for (int i = 0; i < buf.capacity(); i++) {
            buf.put(rnd.nextFloat() * 2f - 1f);
        }
        buf.flip();
    }

    private static byte[] loadAsset(Context ctx, String path) throws IOException {
        try (InputStream is = ctx.getAssets().open(path);
                ByteArrayOutputStream baos = new ByteArrayOutputStream(32 * 1024 * 1024)) {
            final byte[] buf = new byte[64 * 1024];
            int n;
            while ((n = is.read(buf)) > 0) {
                baos.write(buf, 0, n);
            }
            return baos.toByteArray();
        }
    }
}
