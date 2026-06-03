/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.sawtunaa;

import android.content.Context;
import android.content.res.AssetManager;
import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import android.os.SystemClock;

import org.jni_zero.CalledByNative;

import org.chromium.base.ContextUtils;
import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;
import org.chromium.chrome.browser.browther_analytics.BrowtherAnalyticsBridge;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Iterator;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.LinkedBlockingDeque;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

/**
 * SawtunaaPlayer — port Java de SawtunaaAudioPlayer.swift (Jalon 2.D).
 *
 * <p>Reçoit des chunks PCM 48 kHz mono float depuis le JS (via Mojo →
 * SawtunaaTabHelper → JNI → {@link SawtunaaBridge}), les passe au
 * {@link NSNet2Processor} sur un thread dédié, met le résultat en cache,
 * puis joue depuis ce cache au rythme de la vidéo via AudioTrack.
 *
 * <p>Équivalences avec le Swift (référence) :
 * <ul>
 *   <li>{@code AVAudioEngine + AVAudioPlayerNode} → {@link AudioTrack} en
 *       MODE_STREAM, ENCODING_PCM_FLOAT 48 kHz mono, buffer ~6 s pour
 *       absorber le lookahead.</li>
 *   <li>{@code playerNode.scheduleBuffer(buf)} → enqueue dans
 *       {@link #mWriteQueue} ; thread "writer" consomme et {@code write()}
 *       à AudioTrack en streaming (bloque naturellement si plein → throttle).</li>
 *   <li>{@code playerTime.sampleTime} → {@link AudioTrack#getPlaybackHeadPosition()}
 *       (32-bit, wraps après 24h @ 48 kHz — non-issue pour ancrage relatif).</li>
 *   <li>{@code preprocessQueue.async} → single-thread {@link ExecutorService}
 *       (sérialise les chunks dans l'ordre d'arrivée, comme le Swift).</li>
 * </ul>
 *
 * <p>Le pattern d'instance suit le contract Chromium {@code WebContentsUserData} :
 * une instance Java par {@code WebContents}, créée par le {@link SawtunaaTabHelper}
 * C++ via {@link #create(int)}. Le TabHelper garde un global ref Java et appelle
 * les méthodes {@code @CalledByNative} de cette instance.
 */
@NullMarked
public final class SawtunaaPlayer {
    private static final String TAG = "Sawtunaa";

    // Audio format constants — alignés sur le Swift / pipeline NSNet2.
    public static final int SAMPLE_RATE = 48000;
    public static final int CHANNELS = 1;
    public static final int BYTES_PER_SAMPLE = 4; // float32

    /** Asset path du modèle NSNet2 packagé par {@code browther_nsnet2_android_assets}. */
    private static final String MODEL_ASSET_PATH = "sawtunaa/nsnet2-stateful.onnx";

    // Lookahead/skip/trim/gap — copies des constantes Swift.
    private static final double LOOKAHEAD_MS = 5000.0;
    private static final double SKIP_OLD_THRESHOLD_MS = 200.0;
    private static final double TRIM_THRESHOLD_MS = 100.0;
    private static final double GAP_MIN_MS = 30.0;
    private static final double GAP_MAX_MS = 30_000.0;
    private static final double SILENCE_LEAD_MAX_MS = 2000.0;

    // Audio cache cap (Swift = 600 ≈ 10 min @ ~1 s/chunk).
    private static final int CACHE_MAX = 600;

    // Session start (CFAbsoluteTimeGetCurrent equiv) pour timestamps métriques.
    private final long mSessionStartMs = SystemClock.elapsedRealtime();

    // --- Audio state ---

    @Nullable private AudioTrack mAudioTrack;
    // Le buffer minimum réel d'AudioTrack (renseigné à create()).
    private int mTrackBufferBytes;
    // Sample position à laquelle on a anchored la timeline source (en frames
    // depuis le démarrage — provient de getPlaybackHeadPosition()).
    @Nullable private Long mAnchorAudioFrame;
    private double mAnchorSourceMs;
    private double mLastVideoUpToMs;

    // --- Writer thread (joue depuis mWriteQueue vers AudioTrack) ---

    private final LinkedBlockingDeque<float[]> mWriteQueue = new LinkedBlockingDeque<>();
    @Nullable private Thread mWriterThread;
    private final AtomicBoolean mWriterRunning = new AtomicBoolean(false);

    // --- NSNet2 preprocess ---

    @Nullable private NSNet2Processor mNsnet2;
    // ExecutorService factory : on nomme les threads pour le debug logcat ;
    // pas de setPriority (Chromium ThreadPriorityCheck errorprone discourage).
    private final ExecutorService mPreprocessExec =
            Executors.newSingleThreadExecutor(r -> new Thread(r, "Sawtunaa-NSNet2"));
    // Single-thread main-mirror executor pour cohérence d'état (= main queue
    // Swift). Toutes les mutations d'audioCache/cursors/anchors passent ici.
    private final ExecutorService mMainExec =
            Executors.newSingleThreadExecutor(r -> new Thread(r, "Sawtunaa-State"));

    // --- Cache + cursors (mutés uniquement sur mMainExec) ---

    /** PCM cache sorted by timestampMs ; aligné sur audioCache Swift. */
    private static final class PcmChunk {
        final double timestampMs;
        final double durationMs;
        final float[] samples;
        PcmChunk(double t, double d, float[] s) {
            timestampMs = t;
            durationMs = d;
            samples = s;
        }
    }

    private final ArrayList<PcmChunk> mAudioCache = new ArrayList<>(CACHE_MAX);
    private int mPreprocessCount;
    private int mPlayedChunkCount;
    private int mSkippedChunkCount;
    private int mTrimmedChunkCount;
    private int mGapFillCount;
    private long mStatsAccumulatedSamples;
    // Cursor au sens Swift : seul un chunk avec timestampMs > scheduledCursorTsMs
    // est éligible au scheduling. Reset à -1 par defaut / seek.
    private double mScheduledCursorTsMs = -1.0;
    private double mLastScheduledEndMs;
    private boolean mIsPaused;
    @Nullable private Long mFirstChunkPlayedAtMs;
    // Epoch counter — atomic car peut être lu depuis preprocess thread.
    private final AtomicLong mEpoch = new AtomicLong(0);

    // --- Lifecycle ---

    /** Créé depuis JNI par SawtunaaTabHelper (1 instance par WebContents). */
    @CalledByNative
    public static SawtunaaPlayer create(int instanceId) {
        Log.i(TAG, "[Player#%d] created", instanceId);
        return new SawtunaaPlayer(instanceId);
    }

    private final int mInstanceId;

    private SawtunaaPlayer(int instanceId) {
        mInstanceId = instanceId;
        emit("player_init",
                "sample_rate", SAMPLE_RATE,
                "channels", CHANNELS);
        // Auto-load NSNet2 depuis les assets — pas besoin de marshalling C++ :
        // le pattern SawtunaaBenchmark (Jalon 1) lit déjà ce path. Le warmup
        // (~1.2 s sur device) tourne sur le preprocess thread, n'impacte pas
        // l'UI ; preprocessChunk drop les chunks reçus avant le warmup avec
        // {@code reason: nsnet2_not_ready}, ce qui matche le comportement
        // Swift quand l'utilisateur active Sawtunaa au démarrage.
        loadModelAsync();
    }

    /** Lit l'asset puis bootstrap NSNet2 sur le preprocess thread (warmup inclus). */
    private void loadModelAsync() {
        final long t0 = SystemClock.elapsedRealtimeNanos();
        mPreprocessExec.execute(() -> {
            try {
                Context ctx = ContextUtils.getApplicationContext();
                if (ctx == null) {
                    emit("model_load_done", "available", false, "reason", "no_context");
                    return;
                }
                byte[] modelBytes = readAsset(ctx.getAssets(), MODEL_ASSET_PATH);
                long readMs = (SystemClock.elapsedRealtimeNanos() - t0) / 1_000_000L;
                long initT0 = SystemClock.elapsedRealtimeNanos();
                NSNet2Processor.InitResult res = NSNet2Processor.create(modelBytes);
                long loadMs = (SystemClock.elapsedRealtimeNanos() - initT0) / 1_000_000L;
                // Warmup 1 s de silence — primer ORT/GRU buffers (Swift =idem).
                long warmT0 = SystemClock.elapsedRealtimeNanos();
                float[] silence = new float[SAMPLE_RATE];
                res.processor.process(silence);
                long warmMs = (SystemClock.elapsedRealtimeNanos() - warmT0) / 1_000_000L;
                res.processor.reset();
                mMainExec.execute(() -> {
                    mNsnet2 = res.processor;
                    emit("model_load_done",
                            "available", true,
                            "read_ms", readMs,
                            "load_ms", loadMs,
                            "warmup_ms", warmMs,
                            "used_nnapi", res.usedNnapi,
                            "intra_op_threads", res.intraOpThreads);
                });
            } catch (Throwable e) {
                Log.e(TAG, "NSNet2 load failed", e);
                emit("model_load_done",
                        "available", false,
                        "error", String.valueOf(e.getMessage()));
            }
        });
    }

    private static byte[] readAsset(AssetManager assets, String path) throws Exception {
        try (InputStream is = assets.open(path);
                ByteArrayOutputStream bos = new ByteArrayOutputStream(2 * 1024 * 1024)) {
            byte[] buf = new byte[64 * 1024];
            int n;
            while ((n = is.read(buf)) > 0) {
                bos.write(buf, 0, n);
            }
            return bos.toByteArray();
        }
    }

    @CalledByNative
    public void destroy() {
        Log.i(TAG, "[Player#%d] destroyed", mInstanceId);
        stop();
        mPreprocessExec.shutdownNow();
        mMainExec.shutdownNow();
        if (mNsnet2 != null) {
            try {
                mNsnet2.close();
            } catch (Throwable ignore) {
                // best-effort
            }
            mNsnet2 = null;
        }
    }

    // --- Engine start/stop ---

    private void ensureStarted() {
        if (mAudioTrack != null) {
            return;
        }
        try {
            int minBuf = AudioTrack.getMinBufferSize(
                    SAMPLE_RATE,
                    AudioFormat.CHANNEL_OUT_MONO,
                    AudioFormat.ENCODING_PCM_FLOAT);
            // Buffer ~6 s pour absorber le lookahead (5 s) + marge.
            int desiredBytes = 6 * SAMPLE_RATE * BYTES_PER_SAMPLE;
            mTrackBufferBytes = Math.max(minBuf, desiredBytes);

            AudioAttributes attrs = new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build();
            AudioFormat fmt = new AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build();

            mAudioTrack = new AudioTrack.Builder()
                    .setAudioAttributes(attrs)
                    .setAudioFormat(fmt)
                    .setBufferSizeInBytes(mTrackBufferBytes)
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .build();

            if (mAudioTrack.getState() != AudioTrack.STATE_INITIALIZED) {
                emit("engine_start", "success", false, "reason", "track_not_initialized");
                mAudioTrack.release();
                mAudioTrack = null;
                return;
            }
            mAudioTrack.play();

            mWriterRunning.set(true);
            mWriterThread = new Thread(this::writerLoop, "Sawtunaa-Writer");
            // setPriority retiré (ThreadPriorityCheck errorprone). Le scheduler
            // Android est suffisant pour ce thread qui write à AudioTrack.
            mWriterThread.start();

            emit("engine_start",
                    "success", true,
                    "nsnet2_available", mNsnet2 != null,
                    "track_buffer_bytes", mTrackBufferBytes);
            startStatePolling();
        } catch (Throwable e) {
            Log.e(TAG, "AudioTrack start failed", e);
            emit("engine_start", "success", false, "error", String.valueOf(e.getMessage()));
            mAudioTrack = null;
        }
    }

    private void stop() {
        stopStatePolling();
        mWriterRunning.set(false);
        mWriteQueue.clear();
        // Réveille le writer pour qu'il sorte de take().
        mWriteQueue.offer(new float[0]);
        Thread t = mWriterThread;
        if (t != null) {
            try {
                t.join(500);
            } catch (InterruptedException ignored) {
                Thread.currentThread().interrupt();
            }
            mWriterThread = null;
        }
        if (mAudioTrack != null) {
            try {
                mAudioTrack.pause();
                mAudioTrack.flush();
                mAudioTrack.stop();
            } catch (Throwable ignore) {
                // best-effort
            }
            mAudioTrack.release();
            mAudioTrack = null;
        }
        emit("engine_stop");
    }

    private void writerLoop() {
        AudioTrack track = mAudioTrack;
        if (track == null) {
            return;
        }
        while (mWriterRunning.get()) {
            float[] buf;
            try {
                buf = mWriteQueue.take();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            }
            if (buf == null || buf.length == 0) {
                continue; // sentinel ou réveil de stop()
            }
            int written = 0;
            while (written < buf.length && mWriterRunning.get()) {
                int n = track.write(
                        buf, written, buf.length - written,
                        AudioTrack.WRITE_BLOCKING);
                if (n <= 0) {
                    // ERROR_DEAD_OBJECT / ERROR_INVALID_OPERATION — abandonne ce buffer.
                    emit("audiotrack_write_err", "code", n);
                    break;
                }
                written += n;
            }
        }
    }

    // --- State polling (équivalent du Timer Swift, 1 Hz) ---

    @Nullable private Thread mStatePollThread;

    private void startStatePolling() {
        stopStatePolling();
        mStatePollThread = new Thread(() -> {
            while (mAudioTrack != null && Thread.currentThread() == mStatePollThread) {
                try {
                    Thread.sleep(1000);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    return;
                }
                mMainExec.execute(this::emitStateSnapshot);
            }
        }, "Sawtunaa-State-Poll");
        mStatePollThread.setDaemon(true);
        mStatePollThread.start();
    }

    private void stopStatePolling() {
        Thread t = mStatePollThread;
        mStatePollThread = null;
        if (t != null) {
            t.interrupt();
        }
    }

    private void emitStateSnapshot() {
        AudioTrack track = mAudioTrack;
        double audioSrcMs = currentAudioSourceMs();
        double videoSrcMs = mLastVideoUpToMs - 100;
        int driftMs = (audioSrcMs >= 0) ? (int) (videoSrcMs - audioSrcMs) : -99999;

        int holes = 0;
        long holeMs = 0;
        long cacheFirstTs = -1;
        long cacheLastEnd = -1;
        if (!mAudioCache.isEmpty()) {
            cacheFirstTs = (long) mAudioCache.get(0).timestampMs;
            PcmChunk last = mAudioCache.get(mAudioCache.size() - 1);
            cacheLastEnd = (long) (last.timestampMs + last.durationMs);
            for (int i = 1; i < mAudioCache.size(); i++) {
                double prevEnd = mAudioCache.get(i - 1).timestampMs
                        + mAudioCache.get(i - 1).durationMs;
                double gap = mAudioCache.get(i).timestampMs - prevEnd;
                if (gap > 100) {
                    holes++;
                    holeMs += (long) gap;
                }
            }
        }

        emit("engine_state",
                "engine_running", track != null,
                "player_playing", track != null
                        && track.getPlayState() == AudioTrack.PLAYSTATE_PLAYING,
                "cache_size", mAudioCache.size(),
                "cache_first_ts", cacheFirstTs,
                "cache_last_end", cacheLastEnd,
                "cache_holes", holes,
                "cache_hole_ms", holeMs,
                "audio_src_ms", (audioSrcMs >= 0) ? (long) audioSrcMs : -1L,
                "video_src_ms", (long) videoSrcMs,
                "drift_ms", driftMs,
                "played_total", mPlayedChunkCount,
                "skipped_total", mSkippedChunkCount,
                "trimmed_total", mTrimmedChunkCount,
                "preprocessed_total", mPreprocessCount);
    }

    // --- Anchor / drift ---

    /** Anchors the audio playback timeline against a source-time origin. */
    private void anchorPlayback(double sourceMs) {
        if (mAnchorAudioFrame != null) {
            return;
        }
        AudioTrack track = mAudioTrack;
        if (track == null) {
            return;
        }
        // getPlaybackHeadPosition() = frames played since AudioTrack creation.
        // 32-bit wrap après ~24h @ 48 kHz — non issue pour ancrage relatif.
        long pos = unsignedHead(track.getPlaybackHeadPosition());
        mAnchorAudioFrame = pos;
        mAnchorSourceMs = sourceMs;
    }

    /** Position source-time (ms) du sample en train d'être rendu, ou -1. */
    private double currentAudioSourceMs() {
        Long anchor = mAnchorAudioFrame;
        AudioTrack track = mAudioTrack;
        if (anchor == null || track == null) {
            return -1;
        }
        long head = unsignedHead(track.getPlaybackHeadPosition());
        long elapsedSamples = head - anchor;
        return mAnchorSourceMs + (double) elapsedSamples / (SAMPLE_RATE / 1000.0);
    }

    private static long unsignedHead(int v) {
        return ((long) v) & 0xFFFFFFFFL;
    }

    // --- preprocessChunk ---

    /** Appelé depuis JNI / SawtunaaBridge. */
    @CalledByNative
    public void preprocessChunk(double timestampMs, float[] samples) {
        if (mIsPaused) {
            emit("preprocess_drop_paused", "chunk_ts", (long) timestampMs);
            return;
        }
        final long receivedNs = SystemClock.elapsedRealtimeNanos();
        final long chunkEpoch = mEpoch.get();
        mPreprocessExec.execute(() -> {
            NSNet2Processor nsnet2 = mNsnet2;
            if (nsnet2 == null) {
                emit("chunk_preprocess_drop",
                        "chunk_ts", (long) timestampMs,
                        "reason", "nsnet2_not_ready");
                return;
            }
            // Early-exit si pageReset/clearChunks pendant qu'on attendait.
            if (chunkEpoch != mEpoch.get()) {
                emit("chunk_preprocess_drop",
                        "chunk_ts", (long) timestampMs,
                        "reason", "stale_epoch_pre",
                        "chunk_epoch", chunkEpoch,
                        "current_epoch", mEpoch.get());
                return;
            }
            long t0 = SystemClock.elapsedRealtimeNanos();
            float[] processed;
            try {
                processed = nsnet2.process(samples);
            } catch (Throwable e) {
                Log.e(TAG, "NSNet2 process error", e);
                emit("chunk_preprocess_drop",
                        "chunk_ts", (long) timestampMs,
                        "reason", "nsnet2_throw",
                        "error", String.valueOf(e.getMessage()));
                return;
            }
            long nsnet2Ms = (SystemClock.elapsedRealtimeNanos() - t0) / 1_000_000L;

            // Stats music_seconds — Browther stats publiques. À 48 kHz on émet
            // 1 s dès qu'on dépasse 48000 samples accumulés (parité iOS
            // BrowtherStatsReporter.flushSawtunaaSeconds). Le bridge JNI route
            // vers `BrowtherAnalyticsService::IncrementMusicSeconds` qui
            // accumule dans la pref `kStatsMusicSecondsPending` et flush
            // périodiquement via POST `/api/stats/ingest`. No-op si consent
            // stats OFF (gating côté service C++).
            mStatsAccumulatedSamples += processed.length;
            if (mStatsAccumulatedSamples >= SAMPLE_RATE) {
                int secondsToReport = (int) (mStatsAccumulatedSamples / SAMPLE_RATE);
                mStatsAccumulatedSamples -= (long) secondsToReport * SAMPLE_RATE;
                BrowtherAnalyticsBridge.incrementMusicSeconds(secondsToReport);
                emit("music_seconds", "delta", secondsToReport);
            }

            final long totalMs =
                    (SystemClock.elapsedRealtimeNanos() - receivedNs) / 1_000_000L;
            final double durationMs = processed.length / 48.0;
            final float[] processedFinal = processed;
            mMainExec.execute(() -> {
                if (chunkEpoch != mEpoch.get()) {
                    emit("chunk_preprocess_drop",
                            "chunk_ts", (long) timestampMs,
                            "reason", "stale_epoch",
                            "chunk_epoch", chunkEpoch,
                            "current_epoch", mEpoch.get());
                    return;
                }
                PcmChunk entry = new PcmChunk(timestampMs, durationMs, processedFinal);
                insertSorted(entry);
                if (mAudioCache.size() > CACHE_MAX) {
                    int drop = mAudioCache.size() - CACHE_MAX;
                    for (int i = 0; i < drop; i++) {
                        mAudioCache.remove(0);
                    }
                }
                mPreprocessCount++;
                emit("chunk_preprocess_done",
                        "chunk_ts", (long) timestampMs,
                        "nsnet2_ms", nsnet2Ms,
                        "total_ms", totalMs,
                        "frames", processedFinal.length,
                        "cache_size", mAudioCache.size(),
                        "preprocess_idx", mPreprocessCount,
                        "epoch", chunkEpoch);
            });
        });
    }

    private void insertSorted(PcmChunk entry) {
        // Recherche dichotomique sur timestampMs. Le cache est petit (≤600)
        // mais des chunks peuvent arriver hors ordre suite à NSNet2 sur thread.
        int lo = 0;
        int hi = mAudioCache.size();
        while (lo < hi) {
            int mid = (lo + hi) >>> 1;
            PcmChunk midChunk = mAudioCache.get(mid);
            if (midChunk.timestampMs < entry.timestampMs) {
                lo = mid + 1;
            } else if (midChunk.timestampMs > entry.timestampMs) {
                hi = mid;
            } else {
                // Dedup : remplace l'entrée existante.
                mAudioCache.set(mid, entry);
                return;
            }
        }
        mAudioCache.add(lo, entry);
    }

    // --- playChunksUpTo ---

    @CalledByNative
    public void playChunksUpTo(double upToMs) {
        mMainExec.execute(() -> playChunksUpToOnMain(upToMs));
    }

    private void playChunksUpToOnMain(double upToMs) {
        ensureStarted();
        if (mAudioTrack == null) {
            emit("play_chunks_engine_failed", "upTo_ms", (long) upToMs);
            return;
        }
        mLastVideoUpToMs = upToMs;

        while (true) {
            int nextIdx = -1;
            for (int i = 0; i < mAudioCache.size(); i++) {
                if (mAudioCache.get(i).timestampMs > mScheduledCursorTsMs) {
                    nextIdx = i;
                    break;
                }
            }
            if (nextIdx < 0) {
                return;
            }
            PcmChunk next = mAudioCache.get(nextIdx);
            double nextTs = next.timestampMs;
            double nextEnd = nextTs + next.durationMs;

            // Lookahead cap : on attend si trop loin dans le futur.
            if (nextTs > upToMs + LOOKAHEAD_MS) {
                return;
            }

            boolean isFirstChunk = (mPlayedChunkCount == 0);

            // First-chunk silence-lead : si le chunk est dans le futur, injecte
            // du silence pour aligner audio_start avec video.currentTime.
            if (isFirstChunk && nextTs > upToMs + 100) {
                double silentMs = nextTs - upToMs;
                if (silentMs > SILENCE_LEAD_MAX_MS) {
                    return;
                }
                int silentFrames = (int) (silentMs * 48);
                if (silentFrames > 0) {
                    float[] silence = new float[silentFrames];
                    mWriteQueue.add(silence);
                    anchorPlayback(upToMs);
                    mLastScheduledEndMs = nextTs;
                    emit("first_chunk_silence_lead",
                            "silent_ms", (long) silentMs,
                            "video_ms", (long) upToMs,
                            "next_ts", (long) nextTs);
                    // Fall through pour scheduler le chunk dans la même itération.
                }
            }

            // Skip si entièrement dans le passé.
            if (nextEnd < upToMs - SKIP_OLD_THRESHOLD_MS) {
                mSkippedChunkCount++;
                emit("chunk_skip_old",
                        "chunk_ts", (long) nextTs,
                        "video_ms", (long) upToMs,
                        "lag_ms", (long) (upToMs - nextEnd));
                mScheduledCursorTsMs = nextTs;
                continue;
            }

            // Trim si chunk démarre significativement avant video time.
            if (nextTs < upToMs - TRIM_THRESHOLD_MS) {
                double skipMs = upToMs - nextTs;
                int skipSamples = (int) (skipMs * 48);
                int totalFrames = next.samples.length;
                if (skipSamples > 0 && skipSamples < totalFrames) {
                    int remaining = totalFrames - skipSamples;
                    float[] trimmed = Arrays.copyOfRange(
                            next.samples, skipSamples, skipSamples + remaining);
                    mWriteQueue.add(trimmed);
                    mPlayedChunkCount++;
                    mTrimmedChunkCount++;
                    mLastScheduledEndMs = nextEnd;
                    mScheduledCursorTsMs = nextTs;
                    if (mFirstChunkPlayedAtMs == null) {
                        mFirstChunkPlayedAtMs = SystemClock.elapsedRealtime();
                        anchorPlayback(upToMs);
                        emit("first_chunk_played",
                                "chunk_ts", (long) nextTs,
                                "video_ms", (long) upToMs,
                                "trimmed", true,
                                "skip_ms", (long) skipMs);
                    } else {
                        emit("chunk_play_trim",
                                "chunk_ts", (long) nextTs,
                                "video_ms", (long) upToMs,
                                "skip_ms", (long) skipMs);
                    }
                    continue;
                }
            }

            // Gap-fill silence (seulement après le premier chunk).
            if (mPlayedChunkCount > 0) {
                double gapMs = nextTs - mLastScheduledEndMs;
                if (gapMs > GAP_MIN_MS && gapMs < GAP_MAX_MS) {
                    int silenceFrames = (int) (gapMs * 48);
                    if (silenceFrames > 0) {
                        float[] silence = new float[silenceFrames];
                        mWriteQueue.add(silence);
                        mGapFillCount++;
                        emit("gap_fill",
                                "gap_ms", (long) gapMs,
                                "next_ts", (long) nextTs,
                                "last_end_ms", (long) mLastScheduledEndMs,
                                "fill_count", mGapFillCount);
                        mLastScheduledEndMs = nextTs;
                    }
                }
            }

            // Schedule le chunk (full).
            mWriteQueue.add(next.samples);
            mPlayedChunkCount++;
            mLastScheduledEndMs = nextEnd;
            mScheduledCursorTsMs = nextTs;
            if (mFirstChunkPlayedAtMs == null) {
                mFirstChunkPlayedAtMs = SystemClock.elapsedRealtime();
                anchorPlayback(nextTs);
                emit("first_chunk_played",
                        "chunk_ts", (long) nextTs,
                        "video_ms", (long) upToMs,
                        "trimmed", false);
            } else {
                emit("chunk_play_full",
                        "chunk_ts", (long) nextTs,
                        "video_ms", (long) upToMs,
                        "frames", next.samples.length,
                        "play_idx", mPlayedChunkCount);
            }
        }
    }

    // --- pause / resume / seek / clear / evict / sync ---

    @CalledByNative
    public void pauseAudio() {
        mMainExec.execute(() -> {
            AudioTrack track = mAudioTrack;
            if (track == null) {
                return;
            }
            try {
                track.pause();
            } catch (Throwable e) {
                Log.w(TAG, "pause failed", e);
            }
            mIsPaused = true;
            emit("pause_audio");
        });
    }

    @CalledByNative
    public void resumeAudio() {
        mMainExec.execute(() -> {
            AudioTrack track = mAudioTrack;
            if (track == null) {
                return;
            }
            mIsPaused = false;
            try {
                track.play();
            } catch (Throwable e) {
                Log.w(TAG, "resume failed", e);
            }
            emit("resume_audio");
        });
    }

    @CalledByNative
    public void clearChunks() {
        mMainExec.execute(() -> {
            int prev = mAudioCache.size();
            mEpoch.incrementAndGet();
            mAudioCache.clear();
            // Flush AudioTrack pour drop la queue audio en cours.
            AudioTrack track = mAudioTrack;
            if (track != null) {
                try {
                    track.pause();
                    track.flush();
                    if (!mIsPaused) {
                        track.play();
                    }
                } catch (Throwable e) {
                    Log.w(TAG, "flush failed", e);
                }
            }
            mWriteQueue.clear();
            mPreprocessCount = 0;
            mPlayedChunkCount = 0;
            mSkippedChunkCount = 0;
            mTrimmedChunkCount = 0;
            mGapFillCount = 0;
            mLastScheduledEndMs = 0;
            mScheduledCursorTsMs = -1;
            mFirstChunkPlayedAtMs = null;
            mAnchorAudioFrame = null;
            mAnchorSourceMs = 0;
            mIsPaused = false;
            mLastVideoUpToMs = 0;
            // Reset NSNet2 GRU state sur le preprocess thread.
            mPreprocessExec.execute(() -> {
                if (mNsnet2 != null) {
                    mNsnet2.reset();
                }
            });
            emit("clear_chunks", "dropped_cache", prev, "epoch", mEpoch.get());
        });
    }

    @CalledByNative
    public void pageReset(String url) {
        emit("page_reset", "url", url);
        clearChunks();
    }

    @CalledByNative
    public void seekTo(double toMs) {
        mMainExec.execute(() -> {
            AudioTrack track = mAudioTrack;
            if (track != null) {
                try {
                    track.pause();
                    track.flush();
                    if (!mIsPaused) {
                        track.play();
                    }
                } catch (Throwable e) {
                    Log.w(TAG, "seek flush failed", e);
                }
            }
            mWriteQueue.clear();
            mPlayedChunkCount = 0;
            mSkippedChunkCount = 0;
            mTrimmedChunkCount = 0;
            mGapFillCount = 0;
            mFirstChunkPlayedAtMs = null;
            mAnchorAudioFrame = null;
            mAnchorSourceMs = 0;
            mLastScheduledEndMs = Math.max(0, toMs - 100);
            mScheduledCursorTsMs = Math.max(-1, toMs - 1);
            mPreprocessExec.execute(() -> {
                if (mNsnet2 != null) {
                    mNsnet2.reset();
                }
            });
            int chunksAvailable = 0;
            for (PcmChunk c : mAudioCache) {
                if (c.timestampMs + c.durationMs > toMs - 200
                        && c.timestampMs < toMs + LOOKAHEAD_MS) {
                    chunksAvailable++;
                }
            }
            emit("seek_to",
                    "target_ms", (long) toMs,
                    "cache_size", mAudioCache.size(),
                    "available", chunksAvailable);
        });
    }

    @CalledByNative
    public void evictRange(double startMs, double endMs) {
        mMainExec.execute(() -> {
            int before = mAudioCache.size();
            Iterator<PcmChunk> it = mAudioCache.iterator();
            while (it.hasNext()) {
                PcmChunk c = it.next();
                if (c.timestampMs >= startMs && c.timestampMs < endMs) {
                    it.remove();
                }
            }
            int removed = before - mAudioCache.size();
            if (removed > 0) {
                emit("cache_evict_range",
                        "start_ms", (long) startMs,
                        "end_ms", (long) endMs,
                        "removed", removed);
            }
        });
    }

    /** Reçoit un flat double[] {s0, e0, s1, e1, ...} encodé par le bridge. */
    @CalledByNative
    public void syncRanges(double[] flatRanges) {
        mMainExec.execute(() -> {
            int before = mAudioCache.size();
            int rangeCount = flatRanges.length / 2;
            Iterator<PcmChunk> it = mAudioCache.iterator();
            while (it.hasNext()) {
                PcmChunk c = it.next();
                boolean keep = false;
                for (int i = 0; i < rangeCount; i++) {
                    double s = flatRanges[i * 2];
                    double e = flatRanges[i * 2 + 1];
                    if (c.timestampMs >= s && c.timestampMs < e) {
                        keep = true;
                        break;
                    }
                }
                if (!keep) {
                    it.remove();
                }
            }
            int removed = before - mAudioCache.size();
            if (removed > 0) {
                emit("cache_sync_cleanup",
                        "removed", removed,
                        "kept", mAudioCache.size(),
                        "ranges", rangeCount);
            }
        });
    }

    // --- Metric logging ---

    /**
     * Émet une métrique sous format `[METRIC] {"t":..,"event":"name",...}`
     * (parity avec SawtunaaMetric Swift). Le parser
     * {@code analyze_sawtunaa_metrics.py} consomme les deux indistinctement.
     */
    private void emit(String event, Object... kvs) {
        long t = SystemClock.elapsedRealtime() - mSessionStartMs;
        StringBuilder sb = new StringBuilder(96);
        sb.append("[METRIC] {\"t\":").append(t)
                .append(",\"event\":\"").append(event).append('"');
        for (int i = 0; i + 1 < kvs.length; i += 2) {
            sb.append(",\"").append(kvs[i]).append("\":");
            Object v = kvs[i + 1];
            if (v instanceof Number || v instanceof Boolean) {
                sb.append(v);
            } else {
                sb.append('"').append(v).append('"');
            }
        }
        sb.append('}');
        Log.i(TAG, sb.toString());
    }
}
