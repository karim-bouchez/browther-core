/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_intro;

import android.content.Context;
import android.content.res.AssetFileDescriptor;
import android.database.ContentObserver;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;

import org.chromium.base.Log;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.ShortBuffer;

/**
 * L'extrait réel et sa version passée dans Sawtunaa, joués <b>en parallèle</b> et à la même
 * position : l'interrupteur ne relance rien, il <b>change de canal</b>. ⛔ Sans ça, la comparaison
 * porterait sur deux instants différents du morceau et ne prouverait rien.
 *
 * <p>Les deux pistes sont décodées une fois en PCM puis mélangées dans une seule {@link AudioTrack}
 * : deux lecteurs lancés l'un après l'autre se décaleraient de quelques dizaines de millisecondes,
 * et la bascule s'entendrait comme un saut. Ici le canal change à l'échantillon près, par un fondu
 * de 40 ms qui évite le clic.
 *
 * <p>⚠️ Le décodage se fait <b>à l'ouverture de l'introduction</b>, hors du fil principal : le
 * préparer au premier geste figerait l'interrupteur au milieu de sa course (piège payé sur desktop
 * avec le premier {@code AudioContext}, ONBOARDING-SPEC.md § 11.3).
 */
final class BrowtherIntroAudio {
    private static final String TAG = "BrowtherIntro";
    private static final int FADE_MS = 40;
    private static final int CHUNK_FRAMES = 1024;

    /** Écoute l'état de lecture et le niveau du son de l'appareil. */
    interface Listener {
        void onAudioStateChanged();
    }

    private final Context mContext;
    private final AudioManager mAudioManager;
    private final Handler mMain = new Handler(Looper.getMainLooper());
    private final Object mLock = new Object();
    private Listener mListener;

    // Décodé : échantillons 16 bits entrelacés, mêmes longueurs.
    private short[] mBefore;
    private short[] mAfter;
    private int mChannels = 2;
    private int mSampleRate = 48000;
    private boolean mDecoding;

    // État partagé avec le fil d'écriture (sous mLock).
    private int mFrame;
    private boolean mPlaying;
    private boolean mMusicRemoved;
    private float mMix;
    private boolean mWantPlay;

    private AudioTrack mTrack;
    private Thread mWriter;
    private AudioFocusRequest mFocusRequest;
    private ContentObserver mVolumeObserver;

    BrowtherIntroAudio(Context context) {
        mContext = context;
        mAudioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
    }

    void setListener(Listener listener) {
        mListener = listener;
    }

    // -------------------- Préparation --------------------

    /** Décode les deux extraits, hors du fil principal. Idempotent. */
    void prepare() {
        synchronized (mLock) {
            if (mDecoding || mBefore != null) return;
            mDecoding = true;
        }
        new Thread(
                        () -> {
                            short[] before = decode(BrowtherIntroMedia.AUDIO_BEFORE);
                            short[] after = decode(BrowtherIntroMedia.AUDIO_AFTER);
                            boolean start;
                            synchronized (mLock) {
                                mDecoding = false;
                                if (before == null || after == null) return;
                                int length = Math.min(before.length, after.length);
                                length -= length % mChannels;
                                mBefore = before;
                                mAfter = after;
                                mTotalSamples = length;
                                start = mWantPlay;
                            }
                            if (start) mMain.post(this::play);
                        },
                        "BrowtherIntroAudioDecode")
                .start();
    }

    private int mTotalSamples;

    private short[] decode(String asset) {
        MediaExtractor extractor = new MediaExtractor();
        MediaCodec codec = null;
        try (AssetFileDescriptor fd = BrowtherIntroUi.openFd(mContext, asset)) {
            extractor.setDataSource(fd.getFileDescriptor(), fd.getStartOffset(), fd.getLength());
            MediaFormat format = extractor.getTrackFormat(0);
            extractor.selectTrack(0);
            long durationUs =
                    format.containsKey(MediaFormat.KEY_DURATION)
                            ? format.getLong(MediaFormat.KEY_DURATION)
                            : 30_000_000L;
            int sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE);
            int channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
            codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME));
            codec.configure(format, null, null, 0);
            codec.start();

            short[] out = new short[(int) (durationUs * sampleRate / 1_000_000L) * channels + 8192];
            int written = 0;
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            boolean inputDone = false;
            while (true) {
                if (!inputDone) {
                    int input = codec.dequeueInputBuffer(10_000);
                    if (input >= 0) {
                        ByteBuffer buffer = codec.getInputBuffer(input);
                        int size = buffer == null ? -1 : extractor.readSampleData(buffer, 0);
                        if (size < 0) {
                            codec.queueInputBuffer(
                                    input, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputDone = true;
                        } else {
                            codec.queueInputBuffer(input, 0, size, extractor.getSampleTime(), 0);
                            extractor.advance();
                        }
                    }
                }
                int output = codec.dequeueOutputBuffer(info, 10_000);
                if (output == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    MediaFormat outputFormat = codec.getOutputFormat();
                    sampleRate = outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE);
                    channels = outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
                    continue;
                }
                if (output < 0) continue;
                ByteBuffer buffer = codec.getOutputBuffer(output);
                if (buffer != null && info.size > 0) {
                    buffer.position(info.offset);
                    buffer.limit(info.offset + info.size);
                    ShortBuffer samples = buffer.order(ByteOrder.nativeOrder()).asShortBuffer();
                    int count = samples.remaining();
                    if (written + count > out.length) {
                        short[] grown = new short[(written + count) * 5 / 4];
                        System.arraycopy(out, 0, grown, 0, written);
                        out = grown;
                    }
                    samples.get(out, written, count);
                    written += count;
                }
                codec.releaseOutputBuffer(output, false);
                if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break;
            }
            synchronized (mLock) {
                mSampleRate = sampleRate;
                mChannels = channels;
            }
            short[] result = new short[written];
            System.arraycopy(out, 0, result, 0, written);
            return result;
        } catch (IOException | RuntimeException e) {
            Log.e(TAG, "Extrait audio illisible : %s", asset, e);
            return null;
        } finally {
            if (codec != null) {
                try {
                    codec.stop();
                } catch (RuntimeException e) {
                    // Déjà arrêté.
                }
                codec.release();
            }
            extractor.release();
        }
    }

    // -------------------- Lecture --------------------

    boolean isPlaying() {
        synchronized (mLock) {
            return mPlaying || mWantPlay;
        }
    }

    /** Position de lecture, 0…1. */
    float progress() {
        synchronized (mLock) {
            if (mTotalSamples <= 0) return 0f;
            int played = mFrame * mChannels;
            if (mTrack != null && mPlaying) {
                // Ce qui a été écrit n'est pas encore entendu : la tête de lecture de la piste
                // est en retard sur le fil d'écriture d'un tampon.
                played -= Math.max(0, mWrittenFrames - mTrack.getPlaybackHeadPosition()) * mChannels;
            }
            played = ((played % mTotalSamples) + mTotalSamples) % mTotalSamples;
            return (float) played / mTotalSamples;
        }
    }

    private int mWrittenFrames;

    /**
     * Lecture. Rien ne démarre tout seul : l'extrait part au geste de la personne — le bouton, ou
     * l'interrupteur de l'écran.
     */
    void play() {
        synchronized (mLock) {
            if (mPlaying) return;
            if (mBefore == null) {
                mWantPlay = true;
                prepare();
                notifyListener();
                return;
            }
            mWantPlay = false;
        }
        requestFocus();
        int channelMask =
                mChannels == 1 ? AudioFormat.CHANNEL_OUT_MONO : AudioFormat.CHANNEL_OUT_STEREO;
        int minBuffer =
                AudioTrack.getMinBufferSize(mSampleRate, channelMask, AudioFormat.ENCODING_PCM_16BIT);
        AudioTrack track =
                new AudioTrack.Builder()
                        .setAudioAttributes(
                                new AudioAttributes.Builder()
                                        .setUsage(AudioAttributes.USAGE_MEDIA)
                                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                        .build())
                        .setAudioFormat(
                                new AudioFormat.Builder()
                                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                                        .setSampleRate(mSampleRate)
                                        .setChannelMask(channelMask)
                                        .build())
                        .setBufferSizeInBytes(Math.max(minBuffer, CHUNK_FRAMES * 4 * mChannels))
                        .setTransferMode(AudioTrack.MODE_STREAM)
                        .build();
        synchronized (mLock) {
            mTrack = track;
            mPlaying = true;
            mWrittenFrames = 0;
            // Le canal de départ est celui de l'interrupteur, sans fondu.
            mMix = mMusicRemoved ? 1f : 0f;
        }
        track.play();
        Thread writer = new Thread(() -> writeLoop(track), "BrowtherIntroAudio");
        mWriter = writer;
        writer.start();
        startTicker();
        notifyListener();
    }

    void pause() {
        Thread writer;
        AudioTrack track;
        synchronized (mLock) {
            mWantPlay = false;
            if (!mPlaying) {
                notifyListener();
                return;
            }
            // La tête de lecture recule sur ce qui a vraiment été entendu.
            int heard = mTrack == null ? 0 : mTrack.getPlaybackHeadPosition();
            int behind = Math.max(0, mWrittenFrames - heard);
            int frames = mTotalSamples / mChannels;
            mFrame = frames > 0 ? ((mFrame - behind) % frames + frames) % frames : 0;
            mPlaying = false;
            writer = mWriter;
            track = mTrack;
            mTrack = null;
            mWriter = null;
            mLock.notifyAll();
        }
        joinQuietly(writer);
        if (track != null) {
            track.pause();
            track.flush();
            track.release();
        }
        abandonFocus();
        notifyListener();
    }

    void toggle() {
        if (isPlaying()) {
            pause();
        } else {
            play();
        }
    }

    /**
     * Arrêt complet : appelé au « Continuer » et en quittant l'écran. ⛔ Le son s'arrête au
     * « Continuer », pas seulement en quittant l'écran : la feuille de l'accès anticipé garde
     * l'écran monté et l'extrait continuerait derrière elle.
     */
    void stop() {
        pause();
        synchronized (mLock) {
            mFrame = 0;
        }
        notifyListener();
    }

    /**
     * Déplacer la tête de lecture — sur les <b>deux</b> pistes à la fois, sinon la comparaison perd
     * son sens. Appelé une seule fois, au relâcher.
     */
    void seek(float fraction) {
        boolean wasPlaying;
        synchronized (mLock) {
            wasPlaying = mPlaying;
        }
        if (wasPlaying) pause();
        synchronized (mLock) {
            int frames = mTotalSamples / Math.max(1, mChannels);
            mFrame = Math.round(Math.max(0f, Math.min(0.999f, fraction)) * frames);
        }
        if (wasPlaying) play();
        notifyListener();
    }

    /**
     * ⚠️ L'état de l'interrupteur est gardé ici et survit au décodage différé : la préparation ne
     * doit pas remettre le canal sur « avec musique » juste après que l'interrupteur a demandé
     * « sans » (bug de la recette iOS).
     */
    void setMusicRemoved(boolean removed) {
        synchronized (mLock) {
            mMusicRemoved = removed;
        }
    }

    private void writeLoop(AudioTrack track) {
        short[] chunk = new short[CHUNK_FRAMES * mChannels];
        float step = 1000f / (FADE_MS * mSampleRate);
        while (true) {
            synchronized (mLock) {
                if (!mPlaying || mTrack != track) return;
                int channels = mChannels;
                int total = mTotalSamples;
                float target = mMusicRemoved ? 1f : 0f;
                int position = mFrame * channels;
                for (int i = 0; i < chunk.length; i += channels) {
                    if (mMix < target) mMix = Math.min(target, mMix + step);
                    if (mMix > target) mMix = Math.max(target, mMix - step);
                    int index = (position + i) % total;
                    for (int c = 0; c < channels; c++) {
                        float sample =
                                mBefore[index + c] * (1f - mMix) + mAfter[index + c] * mMix;
                        chunk[i + c] = (short) Math.max(-32768, Math.min(32767, Math.round(sample)));
                    }
                }
                mFrame = ((position + chunk.length) % total) / channels;
                mWrittenFrames += CHUNK_FRAMES;
            }
            // Bloquant : l'écriture suit le rythme de la carte son.
            int result = track.write(chunk, 0, chunk.length);
            if (result < 0) return;
        }
    }

    // -------------------- Focus audio --------------------

    /** On veut que la musique de la personne se taise pendant la démonstration. */
    private void requestFocus() {
        mFocusRequest =
                new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                        .setAudioAttributes(
                                new AudioAttributes.Builder()
                                        .setUsage(AudioAttributes.USAGE_MEDIA)
                                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                        .build())
                        .setOnAudioFocusChangeListener(
                                change -> {
                                    if (change < 0) mMain.post(this::pause);
                                },
                                mMain)
                        .build();
        mAudioManager.requestAudioFocus(mFocusRequest);
    }

    private void abandonFocus() {
        if (mFocusRequest == null) return;
        mAudioManager.abandonAudioFocusRequest(mFocusRequest);
        mFocusRequest = null;
    }

    // -------------------- Son de l'appareil --------------------

    /** Niveau du son média de l'appareil, 0…1. */
    float systemVolume() {
        int max = mAudioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
        if (max <= 0) return 0f;
        return (float) mAudioManager.getStreamVolume(AudioManager.STREAM_MUSIC) / max;
    }

    int systemVolumeSteps() {
        return mAudioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
    }

    int systemVolumeStep() {
        return mAudioManager.getStreamVolume(AudioManager.STREAM_MUSIC);
    }

    /** Android permet de régler le son média depuis l'app : on le fait depuis l'écran. */
    void setSystemVolumeStep(int step) {
        try {
            mAudioManager.setStreamVolume(AudioManager.STREAM_MUSIC, step, 0);
        } catch (SecurityException e) {
            // Mode « Ne pas déranger » : le système refuse, les touches restent.
            Log.w(TAG, "Réglage du volume refusé", e);
        }
    }

    /** Suit le volume, touches physiques comprises. */
    void observeSystemVolume(boolean observe) {
        if (observe && mVolumeObserver == null) {
            mVolumeObserver =
                    new ContentObserver(mMain) {
                        @Override
                        public void onChange(boolean selfChange) {
                            notifyListener();
                        }
                    };
            mContext.getContentResolver()
                    .registerContentObserver(Settings.System.CONTENT_URI, true, mVolumeObserver);
        } else if (!observe && mVolumeObserver != null) {
            mContext.getContentResolver().unregisterContentObserver(mVolumeObserver);
            mVolumeObserver = null;
        }
    }

    /** Libère la mémoire des extraits décodés (fin de l'introduction). */
    void release() {
        stop();
        observeSystemVolume(false);
        stopTicker();
        synchronized (mLock) {
            mBefore = null;
            mAfter = null;
            mTotalSamples = 0;
        }
    }

    // -------------------- Rafraîchissement --------------------

    private final Runnable mTick =
            new Runnable() {
                @Override
                public void run() {
                    notifyListener();
                    boolean playing;
                    synchronized (mLock) {
                        playing = mPlaying;
                    }
                    if (playing) mMain.postDelayed(this, 50);
                }
            };

    private void startTicker() {
        mMain.removeCallbacks(mTick);
        mMain.post(mTick);
    }

    private void stopTicker() {
        mMain.removeCallbacks(mTick);
    }

    private void notifyListener() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mMain.post(this::notifyListener);
            return;
        }
        if (mListener != null) mListener.onAudioStateChanged();
    }

    private static void joinQuietly(Thread thread) {
        if (thread == null) return;
        try {
            thread.join(500);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
