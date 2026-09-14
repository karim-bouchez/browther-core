/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_intro;

import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.dp;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.dpf;

import android.animation.ValueAnimator;
import android.annotation.SuppressLint;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;

/** Le lecteur de l'écran Musique : la barre de lecture et les deux pistes dessinées. */
final class BrowtherIntroPlayerViews {
    private BrowtherIntroPlayerViews() {}

    /**
     * La barre de lecture, déplaçable au doigt. Les deux pistes bougent ensemble — c'est ce qui fait
     * que l'interrupteur compare bien le même instant.
     *
     * <p>⛔ Ne pas déplacer la tête de lecture pendant le geste : le curseur suit le doigt <b>en
     * local</b>, le son ne bouge qu'au relâcher. Sinon la lecture re-tamponne et la barre saccade
     * (vu à la recette iOS).
     */
    static final class Scrubber extends View {
        interface Delegate {
            void onSeek(float fraction);
        }

        private final Paint mTrack = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint mFill = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint mKnob = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF mRect = new RectF();
        private final Delegate mDelegate;
        private float mProgress;
        private float mDragged = -1f;

        Scrubber(Context context, Delegate delegate) {
            super(context);
            mDelegate = delegate;
            mTrack.setColor(BrowtherIntroUi.withAlpha(Color.WHITE, 0.18f));
            mFill.setColor(BrowtherIntroUi.PLAYER_CREAM);
            mKnob.setColor(BrowtherIntroUi.PLAYER_CREAM);
            mKnob.setShadowLayer(dpf(context, 3), 0, dpf(context, 1), 0x4D000000);
            setLayerType(LAYER_TYPE_SOFTWARE, null);
        }

        void setProgress(float progress) {
            if (mDragged >= 0 || Math.abs(progress - mProgress) < 0.0005f) return;
            mProgress = progress;
            invalidate();
        }

        @Override
        protected void onDraw(Canvas canvas) {
            float knobMax = dpf(getContext(), 9);
            float left = knobMax;
            float width = getWidth() - 2 * knobMax;
            float cy = getHeight() / 2f;
            float bar = dpf(getContext(), 5);
            float shown = mDragged >= 0 ? mDragged : mProgress;
            boolean rtl = getLayoutDirection() == LAYOUT_DIRECTION_RTL;
            mRect.set(left, cy - bar / 2, left + width, cy + bar / 2);
            canvas.drawRoundRect(mRect, bar / 2, bar / 2, mTrack);
            float filled = Math.max(bar, width * shown);
            if (rtl) {
                mRect.set(left + width - filled, cy - bar / 2, left + width, cy + bar / 2);
            } else {
                mRect.set(left, cy - bar / 2, left + filled, cy + bar / 2);
            }
            canvas.drawRoundRect(mRect, bar / 2, bar / 2, mFill);
            float knob = dpf(getContext(), mDragged >= 0 ? 9 : 7);
            float x = rtl ? left + width - width * shown : left + width * shown;
            canvas.drawCircle(x, cy, knob, mKnob);
        }

        @SuppressLint("ClickableViewAccessibility")
        @Override
        public boolean onTouchEvent(MotionEvent event) {
            float knobMax = dpf(getContext(), 9);
            float width = Math.max(1f, getWidth() - 2 * knobMax);
            float fraction = Math.max(0f, Math.min(1f, (event.getX() - knobMax) / width));
            if (getLayoutDirection() == LAYOUT_DIRECTION_RTL) fraction = 1f - fraction;
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    getParent().requestDisallowInterceptTouchEvent(true);
                    mDragged = fraction;
                    invalidate();
                    return true;
                case MotionEvent.ACTION_MOVE:
                    mDragged = fraction;
                    invalidate();
                    return true;
                case MotionEvent.ACTION_UP:
                    mDragged = -1f;
                    mProgress = fraction;
                    invalidate();
                    mDelegate.onSeek(fraction);
                    return true;
                case MotionEvent.ACTION_CANCEL:
                    mDragged = -1f;
                    invalidate();
                    return true;
                default:
                    return false;
            }
        }
    }

    /**
     * Les deux pistes : la voix reste, la musique s'écrase à presque rien quand Browther est
     * allumé.
     */
    static final class Lane extends View {
        private static final int BARS = 34;

        private final Paint mPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF mRect = new RectF();
        private final double mSeed;
        private final long mEpoch = SystemClock.uptimeMillis();
        private float mScale = 1f;
        private ValueAnimator mAnimator;

        Lane(Context context, int color, double seed) {
            super(context);
            mSeed = seed;
            mPaint.setColor(color);
            setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        }

        void setFlattened(boolean flattened, boolean animated) {
            float target = flattened ? 0.04f : 1f;
            if (mAnimator != null) mAnimator.cancel();
            if (!animated) {
                mScale = target;
                invalidate();
                return;
            }
            mAnimator = ValueAnimator.ofFloat(mScale, target);
            mAnimator.setDuration(400);
            mAnimator.setInterpolator(BrowtherIntroUi.EASE_OUT);
            mAnimator.addUpdateListener(
                    animation -> {
                        mScale = (float) animation.getAnimatedValue();
                        invalidate();
                    });
            mAnimator.start();
        }

        @Override
        protected void onDraw(Canvas canvas) {
            double time = (SystemClock.uptimeMillis() - mEpoch) / 1000d;
            float gap = dpf(getContext(), 3);
            float width = (getWidth() - gap * (BARS - 1)) / BARS;
            float height = getHeight();
            float minHeight = dpf(getContext(), 3);
            float corner = Math.min(width / 2, dpf(getContext(), 3));
            for (int i = 0; i < BARS; i++) {
                double phase = time * 4.2 + i * mSeed * 0.3;
                float amplitude = (float) (0.35 + 0.65 * Math.abs(Math.sin(phase))) * mScale;
                float barHeight = Math.max(minHeight, height * amplitude);
                float x = i * (width + gap);
                mRect.set(x, (height - barHeight) / 2, x + width, (height + barHeight) / 2);
                canvas.drawRoundRect(mRect, corner, corner, mPaint);
            }
            // 20 images par seconde suffisent à ce mouvement.
            postInvalidateDelayed(50);
        }
    }

    static int laneHeight(Context context) {
        return dp(context, 28);
    }
}
