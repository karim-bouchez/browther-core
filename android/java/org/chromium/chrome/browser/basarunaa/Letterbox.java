/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;

import org.chromium.build.annotations.NullMarked;

import java.nio.FloatBuffer;

/**
 * Letterbox + CHW float32 normalize pour les détecteurs YOLO (port natif
 * de {@code preprocessForDetection} dans {@code private/extensions/basarunaa/
 * src/utils/preprocessing.js}).
 *
 * <p>Pipeline :
 * <ol>
 *   <li>Calcule {@code scale = min(target/W, target/H)}, dimensions de l'image
 *       redimensionnée, et padding {@code padX/padY} gris (#808080).</li>
 *   <li>Trace l'image redimensionnée sur un canvas {@code targetSize×targetSize}
 *       avec fond gris.</li>
 *   <li>Lit les pixels ARGB et les convertit en tenseur CHW float32 normalisé
 *       [0, 1] (R puis G puis B).</li>
 * </ol>
 *
 * <p>Le retour {@code scale/padX/padY} permet aux post-processeurs de
 * remapper les bbox/keypoints du repère letterboxé vers le repère image
 * source.
 *
 * <p><b>Cohérence POC :</b> garde le même ordre des canaux (R, G, B), même
 * couleur de fond (#808080), même normalisation /255. Toute divergence est
 * une dette qui finit par se voir au test régression.
 */
@NullMarked
public final class Letterbox {
    private Letterbox() {}

    /** Résultat du letterbox : tenseur CHW + params remapping inverse. */
    public static final class Result {
        public final FloatBuffer tensor; // shape [3 * target * target], normalized [0,1]
        public final int targetSize;
        public final float scale; // image_source → letterboxed
        public final float padX;
        public final float padY;

        Result(FloatBuffer tensor, int targetSize, float scale, float padX, float padY) {
            this.tensor = tensor;
            this.targetSize = targetSize;
            this.scale = scale;
            this.padX = padX;
            this.padY = padY;
        }
    }

    /**
     * Applique le letterbox + normalize sur {@code src}. Le bitmap source
     * n'est pas modifié.
     *
     * @param src bitmap source (taille arbitraire)
     * @param targetSize côté du carré cible (typiquement 640 pour YOLO)
     * @return tenseur CHW float32 + params scale/padX/padY
     */
    public static Result apply(Bitmap src, int targetSize) {
        final int srcW = src.getWidth();
        final int srcH = src.getHeight();
        final float scale = Math.min((float) targetSize / srcW, (float) targetSize / srcH);
        final int newW = Math.round(srcW * scale);
        final int newH = Math.round(srcH * scale);
        final float padX = (targetSize - newW) / 2f;
        final float padY = (targetSize - newH) / 2f;

        // Canvas + fond gris #808080.
        final Bitmap target = Bitmap.createBitmap(targetSize, targetSize, Bitmap.Config.ARGB_8888);
        final Canvas canvas = new Canvas(target);
        canvas.drawColor(Color.rgb(0x80, 0x80, 0x80));

        final Paint paint = new Paint(Paint.FILTER_BITMAP_FLAG | Paint.ANTI_ALIAS_FLAG);
        final Rect srcRect = new Rect(0, 0, srcW, srcH);
        final Rect dstRect = new Rect(
                Math.round(padX),
                Math.round(padY),
                Math.round(padX) + newW,
                Math.round(padY) + newH);
        canvas.drawBitmap(src, srcRect, dstRect, paint);

        // Extraction ARGB → CHW float32 normalisé.
        final int area = targetSize * targetSize;
        final int[] argb = new int[area];
        target.getPixels(argb, 0, targetSize, 0, 0, targetSize, targetSize);
        target.recycle();

        final FloatBuffer chw = FloatBuffer.allocate(3 * area);
        final float[] r = new float[area];
        final float[] g = new float[area];
        final float[] b = new float[area];
        for (int i = 0; i < area; i++) {
            final int px = argb[i];
            r[i] = ((px >> 16) & 0xFF) / 255f;
            g[i] = ((px >> 8) & 0xFF) / 255f;
            b[i] = (px & 0xFF) / 255f;
        }
        chw.put(r);
        chw.put(g);
        chw.put(b);
        chw.flip();

        return new Result(chw, targetSize, scale, padX, padY);
    }
}
