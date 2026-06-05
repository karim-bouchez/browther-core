/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Matrix;
import android.graphics.Paint;

import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;

import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Bbox;
import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Keypoint;

/**
 * Alignement face pour le classifier InsightFace genderage — port natif
 * de {@code private/extensions/basarunaa/src/utils/face_align.js}.
 *
 * <p><b>⚠️ Reproduit fidèlement la logique du POC.</b> L'incident iOS du
 * 2026-05-16 (mère + fils mal classés sur photo TF1 famille-repas) a montré
 * qu'un simple crop carré au lieu de la rotation pour aligner les yeux
 * horizontalement crée des classifications inversées (softmax). Le crop
 * naïf marche quand les yeux sont déjà horizontaux, échoue sinon. La
 * rotation est l'aspect le plus impactant de la SimilarityTransform
 * InsightFace.
 *
 * <p><b>Stratégie en cascade (parité POC) :</b>
 * <ol>
 *   <li>Si keypoints COCO avec leftEye (idx 1) + rightEye (idx 2) visibles
 *       (conf > 0.3) + eyeDist ≥ 5px + faceW ≥ 35px → rotation pour aligner
 *       les yeux horizontalement + crop centré sur faceBbox.</li>
 *   <li>Sinon → crop carré direct depuis faceBbox + padding 15%.</li>
 *   <li>Si rien d'utilisable → null.</li>
 * </ol>
 *
 * <p>Centre de rotation : centre de la {@code faceBbox} (précis), pas le
 * midpoint des yeux (offset bug en JS POC). Si la faceBbox manque, fallback
 * sur le midpoint des yeux ajusté de +0.15 × eyeDist en y (parité POC).
 */
@NullMarked
public final class FaceAlign {
    private static final float EYE_CONF_MIN = 0.3f;
    private static final float MIN_EYE_DIST_PX = 5f;
    private static final float MIN_FACE_WIDTH_PX = 35f;
    private static final float FACE_SIZE_PADDING = 1.1f; // faceSize = max(W, H) × 1.1
    private static final float FALLBACK_EYE_DIST_TO_FACE = 2.8f;
    private static final float FALLBACK_EYE_Y_OFFSET = 0.15f;
    private static final float CROP_PADDING_RATIO = 0.15f;

    private FaceAlign() {}

    /**
     * Aligne + crop un visage depuis {@code src}. Retourne un Bitmap
     * {@code outputSize × outputSize} ARGB_8888 (à recycler par l'appelant),
     * ou null si pas alignable.
     *
     * @param src image source complète
     * @param keypoints 17 keypoints COCO (peut être null si on a juste la
     *     faceBbox)
     * @param faceBbox bbox face (peut être null si on a juste les keypoints
     *     pour rotation)
     * @param outputSize côté du carré sortie (96 pour InsightFace genderage)
     */
    @Nullable
    public static Bitmap align(
            Bitmap src,
            @Nullable Keypoint[] keypoints,
            @Nullable Bbox faceBbox,
            int outputSize) {
        // Tente la rotation si on a les 2 yeux visibles.
        final boolean hasEyes =
                keypoints != null
                        && keypoints.length >= 3
                        && keypoints[1].confidence > EYE_CONF_MIN
                        && keypoints[2].confidence > EYE_CONF_MIN;

        if (hasEyes) {
            final Keypoint leftEye = keypoints[1];
            final Keypoint rightEye = keypoints[2];
            final float dx = rightEye.x - leftEye.x;
            final float dy = rightEye.y - leftEye.y;
            final float eyeDist = (float) Math.hypot(dx, dy);

            if (eyeDist < MIN_EYE_DIST_PX) {
                return cropFromBbox(src, faceBbox, outputSize);
            }
            final float faceW =
                    faceBbox != null ? faceBbox.width() : eyeDist * FALLBACK_EYE_DIST_TO_FACE;
            if (faceW < MIN_FACE_WIDTH_PX) {
                return cropFromBbox(src, faceBbox, outputSize);
            }

            // Angle pour aligner les yeux horizontalement.
            final float angleRad = (float) Math.atan2(dy, dx);
            final float angleDeg = (float) Math.toDegrees(angleRad);

            // Centre : faceBbox center si dispo, sinon midpoint yeux ajusté.
            final float cx;
            final float cy;
            final float faceSize;
            if (faceBbox != null) {
                cx = (faceBbox.x1 + faceBbox.x2) / 2f;
                cy = (faceBbox.y1 + faceBbox.y2) / 2f;
                faceSize = Math.max(faceBbox.width(), faceBbox.height()) * FACE_SIZE_PADDING;
            } else {
                cx = (leftEye.x + rightEye.x) / 2f;
                cy = (leftEye.y + rightEye.y) / 2f + eyeDist * FALLBACK_EYE_Y_OFFSET;
                faceSize = eyeDist * FALLBACK_EYE_DIST_TO_FACE;
            }

            // Transform : T2 (centre face → origine) → S (zoom) → R (-angle) →
            // T1 (centre output). En Matrix Android, postX append à droite donc
            // l'ordre `postTranslate(-cx,-cy) → postScale → postRotate →
            // postTranslate(out/2,out/2)` est équivalent à l'enchaînement JS
            // canvas `translate(out/2,out/2) ∘ rotate(-angle) ∘ scale ∘
            // translate(-cx,-cy)`.
            final float scale = (float) outputSize / faceSize;
            final Matrix m = new Matrix();
            m.postTranslate(-cx, -cy);
            m.postScale(scale, scale);
            m.postRotate(-angleDeg);
            m.postTranslate(outputSize / 2f, outputSize / 2f);

            return renderWithMatrix(src, m, outputSize);
        }

        // Fallback : crop carré.
        return cropFromBbox(src, faceBbox, outputSize);
    }

    @Nullable
    private static Bitmap cropFromBbox(Bitmap src, @Nullable Bbox faceBbox, int outputSize) {
        if (faceBbox == null) return null;
        final float fw = faceBbox.width();
        final float fh = faceBbox.height();
        final float maxDim = Math.max(fw, fh);
        final float padding = maxDim * CROP_PADDING_RATIO;
        final float faceSize = maxDim + padding * 2f;
        final float cx = (faceBbox.x1 + faceBbox.x2) / 2f;
        final float cy = (faceBbox.y1 + faceBbox.y2) / 2f;
        final float sx = cx - faceSize / 2f;
        final float sy = cy - faceSize / 2f;
        final float scale = outputSize / faceSize;

        final Matrix m = new Matrix();
        m.postTranslate(-sx, -sy);
        m.postScale(scale, scale);
        return renderWithMatrix(src, m, outputSize);
    }

    private static Bitmap renderWithMatrix(Bitmap src, Matrix m, int outputSize) {
        final Bitmap target = Bitmap.createBitmap(outputSize, outputSize, Bitmap.Config.ARGB_8888);
        final Canvas canvas = new Canvas(target);
        final Paint paint = new Paint(Paint.FILTER_BITMAP_FLAG | Paint.ANTI_ALIAS_FLAG);
        canvas.drawBitmap(src, m, paint);
        return target;
    }
}
