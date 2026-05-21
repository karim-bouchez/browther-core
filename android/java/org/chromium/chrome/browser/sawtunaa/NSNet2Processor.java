/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.sawtunaa;

import ai.onnxruntime.OnnxTensor;
import ai.onnxruntime.OnnxValue;
import ai.onnxruntime.OrtEnvironment;
import ai.onnxruntime.OrtException;
import ai.onnxruntime.OrtSession;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;

import java.nio.FloatBuffer;
import java.util.Arrays;
import java.util.HashMap;

/**
 * NSNet2 stateful processor — Java port of NSNet2Processor.swift.
 *
 * <p>Pipeline: STFT (sqrt-hann window, 960 / 512 hop) → log-power spectrum →
 * ONNX inference (gain mask + GRU states) → masked spectrum → ISTFT (canonical
 * dual synthesis window) → overlap-add.
 *
 * <p>Stateful: GRU hidden states are persisted across frames for streaming.
 * Auto-reset every {@link #GRU_RESET_PERIOD} samples (30s @ 48kHz) to avoid
 * unbounded drift, and explicit {@link #reset()} on seek / page-reset.
 *
 * <p>Single-threaded — not safe to call {@link #process} from multiple threads
 * concurrently. The audio pipeline owner (Sawtunaa background thread) is
 * responsible for serialization.
 */
@NullMarked
public final class NSNet2Processor implements AutoCloseable {
    private static final String TAG = "Sawtunaa";

    public static final int SAMPLE_RATE = 48000;
    public static final int N_WIN = 960;
    public static final int N_FFT = 1024;
    public static final int N_HOP = 512;
    public static final int N_OVERLAP = N_WIN - N_HOP; // 448
    public static final int N_BINS = N_FFT / 2 + 1; // 513
    public static final int GRU_HIDDEN = 600;
    public static final int GRU_RESET_PERIOD = 30 * SAMPLE_RATE;

    private static final long[] INPUT_SHAPE = {1, 1, N_BINS};
    private static final long[] GRU_SHAPE = {1, 1, GRU_HIDDEN};

    private final OrtEnvironment mEnv;
    private final OrtSession mSession;
    private final boolean mUsedNnapi;
    private final int mIntraOpThreads;

    // STFT analysis + synthesis windows.
    private final float[] mWin = new float[N_WIN];
    private final float[] mAwin = new float[N_WIN];

    // Persistent GRU hidden states (carried across frames).
    private final float[] mH1 = new float[GRU_HIDDEN];
    private final float[] mH2 = new float[GRU_HIDDEN];
    private final FloatBuffer mH1Buf = FloatBuffer.allocate(GRU_HIDDEN);
    private final FloatBuffer mH2Buf = FloatBuffer.allocate(GRU_HIDDEN);

    // Overlap-add tail (carried across frames).
    private final float[] mSynthesisOverlap = new float[N_OVERLAP];

    // Input accumulation. Sized to absorb at least one full chunk (1s @ 48kHz =
    // 48000 samples) without realloc.
    private final float[] mInputRing = new float[N_FFT + SAMPLE_RATE];
    private int mInputRingLen;
    private int mSamplesSinceReset;

    // Per-frame work buffers (reused).
    private final float[] mWindowed = new float[N_FFT];
    private final float[] mSpecReal = new float[N_BINS];
    private final float[] mSpecImag = new float[N_BINS];
    private final float[] mFeatures = new float[N_BINS];
    private final FloatBuffer mFeaturesBuf = FloatBuffer.allocate(N_BINS);
    private final float[] mMaskedReal = new float[N_BINS];
    private final float[] mMaskedImag = new float[N_BINS];
    private final float[] mSynthesized = new float[N_FFT];

    // Complex FFT buffers (N_FFT-point in-place radix-2).
    private final float[] mFftReal = new float[N_FFT];
    private final float[] mFftImag = new float[N_FFT];
    private final int[] mBitReverse = new int[N_FFT];
    private final float[] mCos = new float[N_FFT];
    private final float[] mSin = new float[N_FFT];

    /** Builder result returned by {@link #create}. */
    public static final class InitResult {
        public final NSNet2Processor processor;
        public final boolean usedNnapi;
        public final int intraOpThreads;

        InitResult(NSNet2Processor p, boolean nnapi, int threads) {
            this.processor = p;
            this.usedNnapi = nnapi;
            this.intraOpThreads = threads;
        }
    }

    /**
     * Build a processor from raw NSNet2 model bytes. Tries NNAPI EP first, falls back to CPU.
     */
    public static InitResult create(byte[] modelBytes) throws OrtException {
        final OrtEnvironment env = OrtEnvironment.getEnvironment();
        final OrtSession.SessionOptions opts = new OrtSession.SessionOptions();
        opts.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.BASIC_OPT);
        final int threads = Math.min(4, Math.max(1, Runtime.getRuntime().availableProcessors()));
        opts.setIntraOpNumThreads(threads);

        boolean nnapi = false;
        try {
            opts.addNnapi();
            nnapi = true;
        } catch (OrtException e) {
            Log.w(TAG, "NNAPI EP unavailable: %s — falling back to CPU", e.getMessage());
        }

        final OrtSession session = env.createSession(modelBytes, opts);
        return new InitResult(new NSNet2Processor(env, session, nnapi, threads), nnapi, threads);
    }

    private NSNet2Processor(
            OrtEnvironment env, OrtSession session, boolean nnapi, int intraOpThreads) {
        mEnv = env;
        mSession = session;
        mUsedNnapi = nnapi;
        mIntraOpThreads = intraOpThreads;
        setupWindows();
        precomputeFft();
    }

    public boolean usedNnapi() {
        return mUsedNnapi;
    }

    public int intraOpThreads() {
        return mIntraOpThreads;
    }

    @Override
    public void close() throws OrtException {
        mSession.close();
    }

    /**
     * Reset all streaming state — GRU hidden, overlap-add tail, input ring,
     * elapsed-samples counter. Call on seek or SPA page-reset.
     */
    public void reset() {
        Arrays.fill(mH1, 0f);
        Arrays.fill(mH2, 0f);
        Arrays.fill(mSynthesisOverlap, 0f);
        mInputRingLen = 0;
        mSamplesSinceReset = 0;
    }

    /**
     * Process a chunk of mono PCM samples at 48 kHz. Returns exactly the same
     * number of samples — leading zeros are inserted if the internal ring is
     * still warming up (first {@link #N_OVERLAP} samples after reset).
     */
    public float[] process(float[] newSamples) throws OrtException {
        final int n = newSamples.length;
        if (n == 0) return new float[0];

        mSamplesSinceReset += n;
        if (mSamplesSinceReset >= GRU_RESET_PERIOD) {
            Arrays.fill(mH1, 0f);
            Arrays.fill(mH2, 0f);
            mSamplesSinceReset = 0;
        }

        // Append to ring (grow-then-drop-front safety, should not happen in
        // steady state since each chunk is fully drained by the loop below).
        if (mInputRingLen + n > mInputRing.length) {
            final int drop = mInputRingLen + n - mInputRing.length;
            System.arraycopy(mInputRing, drop, mInputRing, 0, mInputRingLen - drop);
            mInputRingLen -= drop;
        }
        System.arraycopy(newSamples, 0, mInputRing, mInputRingLen, n);
        mInputRingLen += n;

        // Drain frames. Each emits N_HOP samples.
        final int maxFrames = (mInputRingLen - N_OVERLAP) / N_HOP;
        if (maxFrames <= 0) {
            // Not enough data yet — output is all zeros (warmup).
            return new float[n];
        }
        final float[] produced = new float[maxFrames * N_HOP];
        int outIdx = 0;
        for (int f = 0; f < maxFrames; f++) {
            processFrame(mInputRing, 0, produced, outIdx);
            outIdx += N_HOP;
            // Slide ring by N_HOP.
            System.arraycopy(mInputRing, N_HOP, mInputRing, 0, mInputRingLen - N_HOP);
            mInputRingLen -= N_HOP;
        }

        // Pad front with zeros if we produced fewer samples than the input.
        if (outIdx == n) return produced;
        if (outIdx < n) {
            final float[] padded = new float[n];
            System.arraycopy(produced, 0, padded, n - outIdx, outIdx);
            return padded;
        }
        // outIdx > n (overproduced) — trim from front to keep latest.
        final float[] trimmed = new float[n];
        System.arraycopy(produced, outIdx - n, trimmed, 0, n);
        return trimmed;
    }

    // --- Internals ---

    private void setupWindows() {
        // sqrt(hann), periodic (sym=False).
        for (int i = 0; i < N_WIN; i++) {
            final double hann = 0.5 * (1.0 - Math.cos(2.0 * Math.PI * i / (double) N_WIN));
            mWin[i] = (float) Math.sqrt(hann);
        }
        // Canonical dual synthesis window for perfect reconstruction.
        // awin[i] = win[i] / sum_k win[i + k*HOP]^2 over k such that i+k*HOP in [0, N_WIN).
        for (int k = 0; k < N_HOP; k++) {
            float sumSq = 0f;
            for (int idx = k; idx < N_WIN; idx += N_HOP) {
                sumSq += mWin[idx] * mWin[idx];
            }
            if (sumSq > 0f) {
                for (int idx = k; idx < N_WIN; idx += N_HOP) {
                    mAwin[idx] = mWin[idx] / sumSq;
                }
            }
        }
    }

    private void precomputeFft() {
        // Bit-reverse permutation table for N_FFT.
        final int bits = Integer.numberOfTrailingZeros(N_FFT);
        for (int i = 0; i < N_FFT; i++) {
            mBitReverse[i] = Integer.reverse(i) >>> (32 - bits);
        }
        // Forward twiddle factors: W_N^k = exp(-2πi*k/N).
        for (int i = 0; i < N_FFT; i++) {
            mCos[i] = (float) Math.cos(-2.0 * Math.PI * i / (double) N_FFT);
            mSin[i] = (float) Math.sin(-2.0 * Math.PI * i / (double) N_FFT);
        }
    }

    private void processFrame(float[] buf, int off, float[] outBuf, int outOff)
            throws OrtException {
        // 1. Windowed input, zero-pad to N_FFT.
        for (int i = 0; i < N_WIN; i++) mWindowed[i] = buf[off + i] * mWin[i];
        for (int i = N_WIN; i < N_FFT; i++) mWindowed[i] = 0f;

        // 2. Forward FFT → 513 complex bins.
        rfft(mWindowed, mSpecReal, mSpecImag);

        // 3. Log-power feature.
        for (int i = 0; i < N_BINS; i++) {
            final float r = mSpecReal[i];
            final float im = mSpecImag[i];
            final double power = (double) r * r + (double) im * im;
            mFeatures[i] = (float) Math.log10(Math.max(power, 1e-12));
        }

        // 4. ONNX inference (gain mask + new GRU states).
        loadFloatBuffer(mFeaturesBuf, mFeatures, N_BINS);
        loadFloatBuffer(mH1Buf, mH1, GRU_HIDDEN);
        loadFloatBuffer(mH2Buf, mH2, GRU_HIDDEN);
        try (OnnxTensor inT = OnnxTensor.createTensor(mEnv, mFeaturesBuf, INPUT_SHAPE);
                OnnxTensor h1T = OnnxTensor.createTensor(mEnv, mH1Buf, GRU_SHAPE);
                OnnxTensor h2T = OnnxTensor.createTensor(mEnv, mH2Buf, GRU_SHAPE)) {
            final HashMap<String, OnnxTensor> inputs = new HashMap<>(3);
            inputs.put("input", inT);
            inputs.put("gru1_h_in", h1T);
            inputs.put("gru2_h_in", h2T);
            try (OrtSession.Result r = mSession.run(inputs)) {
                // Mask: [1, 1, 513]
                final OnnxValue maskVal =
                        r.get("output")
                                .orElseThrow(
                                        () ->
                                                new IllegalStateException(
                                                        "NSNet2: missing 'output' tensor"));
                final float[][][] maskArr = (float[][][]) maskVal.getValue();
                final float[] mask = maskArr[0][0];
                for (int i = 0; i < N_BINS; i++) {
                    mMaskedReal[i] = mSpecReal[i] * mask[i];
                    mMaskedImag[i] = mSpecImag[i] * mask[i];
                }
                // GRU outputs: [1, 1, 600]
                final OnnxValue h1Val =
                        r.get("gru1_h_out")
                                .orElseThrow(
                                        () ->
                                                new IllegalStateException(
                                                        "NSNet2: missing 'gru1_h_out' tensor"));
                final OnnxValue h2Val =
                        r.get("gru2_h_out")
                                .orElseThrow(
                                        () ->
                                                new IllegalStateException(
                                                        "NSNet2: missing 'gru2_h_out' tensor"));
                final float[][][] h1Out = (float[][][]) h1Val.getValue();
                final float[][][] h2Out = (float[][][]) h2Val.getValue();
                System.arraycopy(h1Out[0][0], 0, mH1, 0, GRU_HIDDEN);
                System.arraycopy(h2Out[0][0], 0, mH2, 0, GRU_HIDDEN);
            }
        }

        // 5. Inverse FFT → time-domain.
        irfft(mMaskedReal, mMaskedImag, mSynthesized);

        // 6. Synthesis window + overlap-add.
        for (int i = 0; i < N_WIN; i++) mSynthesized[i] *= mAwin[i];
        for (int i = 0; i < N_OVERLAP; i++) mSynthesized[i] += mSynthesisOverlap[i];

        // 7. Emit N_HOP samples, stash tail for next frame.
        System.arraycopy(mSynthesized, 0, outBuf, outOff, N_HOP);
        System.arraycopy(mSynthesized, N_HOP, mSynthesisOverlap, 0, N_OVERLAP);
    }

    private static void loadFloatBuffer(FloatBuffer buf, float[] src, int len) {
        buf.clear();
        buf.put(src, 0, len);
        buf.flip();
    }

    // --- Real-to-complex FFT (radix-2 iterative Cooley-Tukey, N_FFT = 1024) ---

    private void rfft(float[] input, float[] outReal, float[] outImag) {
        // Copy real input into complex buffers (imag = 0), bit-reverse permuted.
        for (int i = 0; i < N_FFT; i++) {
            mFftReal[mBitReverse[i]] = input[i];
            mFftImag[mBitReverse[i]] = 0f;
        }
        fftButterflies(mFftReal, mFftImag, false);
        // Real signal → output has Hermitian symmetry. Keep bins [0, N/2].
        System.arraycopy(mFftReal, 0, outReal, 0, N_BINS);
        System.arraycopy(mFftImag, 0, outImag, 0, N_BINS);
    }

    private void irfft(float[] inReal, float[] inImag, float[] output) {
        // Reconstruct full Hermitian spectrum into bit-reversed complex buffers.
        // Forward bin k → mFftReal[bitrev[k]] = inReal[k], mFftImag = inImag[k]
        // Mirror bin (N-k) for k in [1, N/2-1] → conjugate.
        mFftReal[mBitReverse[0]] = inReal[0];
        mFftImag[mBitReverse[0]] = 0f;
        mFftReal[mBitReverse[N_FFT / 2]] = inReal[N_FFT / 2];
        mFftImag[mBitReverse[N_FFT / 2]] = 0f;
        for (int k = 1; k < N_FFT / 2; k++) {
            mFftReal[mBitReverse[k]] = inReal[k];
            mFftImag[mBitReverse[k]] = inImag[k];
            mFftReal[mBitReverse[N_FFT - k]] = inReal[k];
            mFftImag[mBitReverse[N_FFT - k]] = -inImag[k];
        }
        fftButterflies(mFftReal, mFftImag, true);
        // Inverse scaling: divide by N.
        final float scale = 1f / (float) N_FFT;
        for (int i = 0; i < N_FFT; i++) output[i] = mFftReal[i] * scale;
    }

    /**
     * In-place radix-2 butterflies on bit-reverse-permuted input. Forward by default,
     * pass {@code inverse=true} for the inverse transform (conjugate twiddles, caller
     * handles the 1/N scaling).
     */
    private void fftButterflies(float[] re, float[] im, boolean inverse) {
        for (int size = 2; size <= N_FFT; size <<= 1) {
            final int half = size >> 1;
            final int step = N_FFT / size;
            for (int i = 0; i < N_FFT; i += size) {
                int twiddleIdx = 0;
                for (int j = 0; j < half; j++) {
                    final int a = i + j;
                    final int b = a + half;
                    final float wRe = mCos[twiddleIdx];
                    final float wIm = inverse ? -mSin[twiddleIdx] : mSin[twiddleIdx];
                    final float tRe = wRe * re[b] - wIm * im[b];
                    final float tIm = wRe * im[b] + wIm * re[b];
                    re[b] = re[a] - tRe;
                    im[b] = im[a] - tIm;
                    re[a] += tRe;
                    im[a] += tIm;
                    twiddleIdx += step;
                }
            }
        }
    }
}
