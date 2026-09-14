/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_intro;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PorterDuff;
import android.graphics.PorterDuffXfermode;
import android.graphics.Rect;
import android.graphics.RectF;
import android.os.Handler;
import android.os.Looper;
import android.view.View;

import java.util.List;

/**
 * La vignette « image » : la photo nette, et par-dessus <b>la même photo floutée</b>, découpée par
 * le contour du corps.
 *
 * <p>C'est la composition du moteur ({@code blur-compositor.ts}) : le flou est un vrai gaussien
 * posé dans les pixels de la photo. ⛔ Jamais un matériau translucide, qui n'est pas un flou mais une
 * matière claire rendant un voile laiteux uniforme (erreur refusée sur iOS). La version floutée est
 * calculée une seule fois ; seul le masque change avec la cible, en fondu.
 */
final class BrowtherIntroPhotoTile extends View {
    /** Réduction de travail du flou : un gaussien de 48 px du média se calcule en quart. */
    private static final int BLUR_DOWNSCALE = 4;

    private final List<BrowtherIntroMedia.Person> mPersons;
    private final Paint mBitmapPaint = new Paint(Paint.FILTER_BITMAP_FLAG);
    private final Paint mMaskPaint = new Paint(Paint.FILTER_BITMAP_FLAG);
    private final Paint mDrawPaint = new Paint();
    private final Path mPath = new Path();
    private final Rect mSource = new Rect();
    private final Rect mBlurredSource = new Rect();
    private final RectF mDestination = new RectF();
    private final Handler mMainHandler = new Handler(Looper.getMainLooper());

    private Bitmap mSharp;
    private Bitmap mBlurred;
    private Bitmap mMask;
    private Bitmap mPreviousMask;
    private BrowtherIntroMedia.Veil mVeil;
    private float mMix = 1f;
    private ValueAnimator mAnimator;
    private boolean mLoading;

    BrowtherIntroPhotoTile(Context context, List<BrowtherIntroMedia.Person> persons) {
        super(context);
        mPersons = persons;
        mMaskPaint.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.DST_IN));
        setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
    }

    void setVeil(BrowtherIntroMedia.Veil veil) {
        if (veil.equals(mVeil)) return;
        boolean animated = mVeil != null && mMask != null;
        mVeil = veil;
        if (mMask == null) {
            invalidate();
            return;
        }
        Bitmap previous = mPreviousMask;
        mPreviousMask = mMask;
        mMask = previous != null ? previous : Bitmap.createBitmap(
                mMask.getWidth(), mMask.getHeight(), Bitmap.Config.ARGB_8888);
        renderMask(mMask);
        if (mAnimator != null) mAnimator.cancel();
        if (!animated) {
            mMix = 1f;
            invalidate();
            return;
        }
        mMix = 0f;
        mAnimator = ValueAnimator.ofFloat(0f, 1f);
        mAnimator.setDuration(300);
        mAnimator.setInterpolator(BrowtherIntroUi.EASE_OUT);
        mAnimator.addUpdateListener(
                animation -> {
                    mMix = (float) animation.getAnimatedValue();
                    invalidate();
                });
        mAnimator.start();
    }

    private void renderMask(Bitmap mask) {
        float feather = 10f * mask.getWidth() / BrowtherIntroMedia.PHOTO_WIDTH;
        BrowtherIntroMedia.drawMask(mask, mPersons, mVeil, feather, mDrawPaint, mPath);
    }

    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
        if (w <= 0 || h <= 0 || mLoading || mSharp != null) return;
        mLoading = true;
        final Context context = getContext();
        final int width = w;
        // Décodage et flou hors du fil principal : l'écran arrive sans à-coup.
        new Thread(
                        () -> {
                            Bitmap sharp =
                                    BrowtherIntroUi.decodeAsset(
                                            context, BrowtherIntroMedia.PHOTO, width);
                            if (sharp == null) return;
                            float scale = (float) sharp.getWidth() / BrowtherIntroMedia.PHOTO_WIDTH;
                            Bitmap small =
                                    Bitmap.createScaledBitmap(
                                            sharp,
                                            Math.max(1, sharp.getWidth() / BLUR_DOWNSCALE),
                                            Math.max(1, sharp.getHeight() / BLUR_DOWNSCALE),
                                            true);
                            float sigma =
                                    BrowtherIntroMedia.blurRadius(
                                                    BrowtherIntroMedia.PHOTO_WIDTH, 676)
                                            * scale
                                            / BLUR_DOWNSCALE;
                            Bitmap blurred = BrowtherIntroMedia.gaussianBlur(small, sigma);
                            small.recycle();
                            mMainHandler.post(() -> onLoaded(sharp, blurred));
                        },
                        "BrowtherIntroPhoto")
                .start();
    }

    private void onLoaded(Bitmap sharp, Bitmap blurred) {
        mSharp = sharp;
        mBlurred = blurred;
        // Le masque à mi-résolution de la vignette : il est adouci, rien ne se perd.
        int maskWidth = Math.max(1, getWidth() / 2);
        int maskHeight = Math.max(1, getHeight() / 2);
        mMask = Bitmap.createBitmap(maskWidth, maskHeight, Bitmap.Config.ARGB_8888);
        if (mVeil != null) renderMask(mMask);
        mMix = 1f;
        invalidate();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        canvas.drawColor(BrowtherIntroUi.SURFACE);
        if (mSharp == null) return;
        mDestination.set(0, 0, getWidth(), getHeight());
        fillSource(mSharp, mSource);
        canvas.drawBitmap(mSharp, mSource, mDestination, mBitmapPaint);
        if (mBlurred == null || mMask == null || mVeil == null) return;
        if (mMix < 1f && mPreviousMask != null) {
            drawVeil(canvas, mPreviousMask, 1f - mMix);
        }
        drawVeil(canvas, mMask, mMix);
    }

    private void drawVeil(Canvas canvas, Bitmap mask, float alpha) {
        if (alpha <= 0f) return;
        int layer = canvas.saveLayerAlpha(mDestination, Math.round(alpha * 255));
        fillSource(mBlurred, mBlurredSource);
        canvas.drawBitmap(mBlurred, mBlurredSource, mDestination, mBitmapPaint);
        canvas.drawBitmap(mask, null, mDestination, mMaskPaint);
        canvas.restoreToCount(layer);
    }

    /** Rognage « remplir » : la photo couvre la vignette 16:9 sans se déformer. */
    private void fillSource(Bitmap bitmap, Rect source) {
        float viewRatio = (float) getWidth() / Math.max(1, getHeight());
        float bitmapRatio = (float) bitmap.getWidth() / bitmap.getHeight();
        if (bitmapRatio > viewRatio) {
            int width = Math.round(bitmap.getHeight() * viewRatio);
            int left = (bitmap.getWidth() - width) / 2;
            source.set(left, 0, left + width, bitmap.getHeight());
        } else {
            int height = Math.round(bitmap.getWidth() / viewRatio);
            int top = (bitmap.getHeight() - height) / 2;
            source.set(0, top, bitmap.getWidth(), top + height);
        }
    }
}
