/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.content.Context;
import android.graphics.Matrix;
import android.graphics.SurfaceTexture;
import android.media.MediaPlayer;
import android.view.Surface;
import android.view.TextureView;
import android.view.View;

import androidx.annotation.Nullable;

import java.io.File;
import java.io.IOException;

/**
 * L'aperçu de la vidéo du statut : elle joue, muette, en boucle, recadrée pour remplir sa vignette
 * — pendant de {@code ReferralStatusVideoPreview} (iOS, {@code ReferralStatusVideoStore.swift}),
 * private/docs/PARRAINAGE.md § 11.
 *
 * <p>🔴 <b>Elle ne demande JAMAIS le focus audio</b> : la musique ou la vidéo d'une autre app (et
 * celle d'un onglet de Browther) ne doit pas se couper parce qu'on ouvre une feuille de partage —
 * le défaut vécu sur iOS avec Sawtunaa le 2026-09-21. D'où un {@link MediaPlayer} nu sur une {@link
 * TextureView}, volume à zéro : ⛔ pas de {@code VideoView} (il demande le focus à l'ouverture), ⛔
 * aucun appel à {@code AudioManager.requestAudioFocus}.
 *
 * <p>⚠️ Une {@code TextureView}, pas une {@code SurfaceView} : la vignette a des coins arrondis et
 * une légende posée par-dessus, et seule une vue dessinée DANS la hiérarchie se laisse rogner.
 *
 * <p>Le lecteur vit le temps de sa surface : Android la détruit quand la vue quitte l'écran ou que
 * l'activité s'arrête (on est parti dans WhatsApp), et la rend au retour — la vidéo reprend alors
 * du début. ⛔ Rien ne joue en arrière-plan.
 */
final class ReferralStatusVideoPreview extends TextureView
        implements TextureView.SurfaceTextureListener {
    /** La durée de la vidéo, en secondes, dès qu'elle est connue. */
    interface DurationListener {
        void onDuration(int seconds);
    }

    private final File mFile;
    private final DurationListener mOnDuration;
    private @Nullable MediaPlayer mPlayer;
    private @Nullable Surface mSurface;
    private int mVideoWidth;
    private int mVideoHeight;

    ReferralStatusVideoPreview(Context context, File file, DurationListener onDuration) {
        super(context);
        mFile = file;
        mOnDuration = onDuration;
        // Le toucher est celui de la vignette, pas du lecteur.
        setClickable(false);
        setFocusable(false);
        setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        setSurfaceTextureListener(this);
    }

    @Override
    public void onSurfaceTextureAvailable(SurfaceTexture texture, int width, int height) {
        start(texture);
    }

    @Override
    public void onSurfaceTextureSizeChanged(SurfaceTexture texture, int width, int height) {
        applyCrop();
    }

    @Override
    public boolean onSurfaceTextureDestroyed(SurfaceTexture texture) {
        release();
        return true;
    }

    @Override
    public void onSurfaceTextureUpdated(SurfaceTexture texture) {}

    @Override
    protected void onDetachedFromWindow() {
        release();
        super.onDetachedFromWindow();
    }

    private void start(SurfaceTexture texture) {
        release();
        MediaPlayer player = new MediaPlayer();
        Surface surface = new Surface(texture);
        try {
            player.setDataSource(mFile.getPath());
            player.setSurface(surface);
            player.setLooping(true);
            // 🔴 Muette, et sans focus audio (voir l'en-tête).
            player.setVolume(0f, 0f);
            player.setOnVideoSizeChangedListener(
                    (p, width, height) -> {
                        mVideoWidth = width;
                        mVideoHeight = height;
                        applyCrop();
                    });
            player.setOnPreparedListener(
                    p -> {
                        // Libéré entre-temps (la vue est partie) : ce lecteur n'est plus le nôtre.
                        if (mPlayer != p) return;
                        mOnDuration.onDuration(Math.round(p.getDuration() / 1000f));
                        p.start();
                    });
            player.setOnErrorListener(
                    (p, what, extra) -> {
                        // Une vidéo illisible laisse la vignette noire, avec sa légende : rien à
                        // dire, le fichier part quand même tel quel.
                        if (mPlayer == p) release();
                        return true;
                    });
            mPlayer = player;
            mSurface = surface;
            player.prepareAsync();
        } catch (IOException | RuntimeException e) {
            mPlayer = null;
            mSurface = null;
            player.release();
            surface.release();
        }
    }

    private void release() {
        MediaPlayer player = mPlayer;
        Surface surface = mSurface;
        mPlayer = null;
        mSurface = null;
        if (player != null) {
            try {
                player.release();
            } catch (RuntimeException e) {
                // Déjà libéré.
            }
        }
        if (surface != null) surface.release();
    }

    /**
     * Recadrée pour REMPLIR (le pendant de {@code resizeAspectFill}) : une {@code TextureView}
     * étire l'image à ses bords, on défait cet étirement puis on agrandit autour du centre.
     */
    private void applyCrop() {
        int width = getWidth();
        int height = getHeight();
        if (width == 0 || height == 0 || mVideoWidth == 0 || mVideoHeight == 0) return;
        float scale = Math.max((float) width / mVideoWidth, (float) height / mVideoHeight);
        Matrix matrix = new Matrix();
        matrix.setScale(
                mVideoWidth * scale / width, mVideoHeight * scale / height, width / 2f, height / 2f);
        setTransform(matrix);
    }
}
