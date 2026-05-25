/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_widgets;

import android.animation.ValueAnimator;
import android.annotation.SuppressLint;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RadialGradient;
import android.graphics.RectF;
import android.graphics.Shader;
import android.os.Build;
import android.util.AttributeSet;
import android.util.TypedValue;
import android.view.View;
import android.view.animation.PathInterpolator;

import androidx.annotation.Nullable;

import org.chromium.build.annotations.NullMarked;

/**
 * Big animated toggle used in Browther feature panels (Sawtunaa, Basarunaa,
 * Bouclier). Custom Canvas view; no Compose dependency (the Brave Android
 * codebase is 100% Java).
 *
 * <p>Spec from {@code private/docs/UI_UX_FEATURES.md}:
 *
 * <ul>
 *   <li>Track 96x52 dp, pill (radius 26 dp).
 *   <li>Thumb 40 dp circle, inset 6 dp from track. Translation ON = +44 dp.
 *   <li>ON state: radial gradient centered bottom-right, 6 keyframes cycling
 *       4.5 s linear forever.
 *   <li>OFF state: track #555555, thumb white with subtle shadow.
 *   <li>Thumb spring animation cubic-bezier(0.34, 1.56, 0.64, 1) 250 ms.
 * </ul>
 */
@NullMarked
public class BrowtherBigToggleView extends View {

    /** Listener for checked-state changes. */
    public interface OnCheckedChangeListener {
        void onCheckedChanged(BrowtherBigToggleView view, boolean isChecked);
    }

    // Track / thumb dimensions in dp.
    private static final float TRACK_WIDTH_DP = 96f;
    private static final float TRACK_HEIGHT_DP = 52f;
    private static final float THUMB_DIAMETER_DP = 40f;
    private static final float THUMB_INSET_DP = 6f;

    // Animation timings.
    private static final long THUMB_DURATION_MS = 250L;
    private static final long GRADIENT_CYCLE_MS = 4500L;

    // 6 keyframes for the ON-state gradient (inner, outer). Source: iOS
    // ShieldsSwitch.swift::steps. Order matches the macOS BrowtherBigToggle.
    private static final int[][] GRADIENT_KEYFRAMES =
            new int[][] {
                {0xFF86EFAC, 0xFF4ADE80},
                {0xFF4ADE80, 0xFF22C55E},
                {0xFF22C55E, 0xFF16A34A},
                {0xFF16A34A, 0xFF10B981},
                {0xFF10B981, 0xFF34D399},
                {0xFF34D399, 0xFF86EFAC},
            };

    private static final int TRACK_OFF_COLOR = 0xFF555555;
    private static final int THUMB_COLOR = 0xFFFFFFFF;
    private static final int THUMB_SHADOW_COLOR = 0x4D000000; // ~30% black

    private final float mDensity;
    private final Paint mTrackPaint;
    private final Paint mThumbPaint;
    private final Paint mThumbShadowPaint;
    private final RectF mTrackRect = new RectF();

    // Preallocated to keep onDraw() allocation-free where possible. The
    // RadialGradient itself still needs to be reconstructed each frame since
    // its color stops change with the gradient cycle and RadialGradient has
    // no setter for them; that single allocation is OK and the lint
    // DrawAllocation warning is silenced via @SuppressLint on onDraw().
    private final int[] mGradientColorsBuf = new int[2];
    private final float[] mGradientStops = new float[] {0f, 1f};

    private boolean mChecked;
    private float mThumbProgress; // 0 = off, 1 = on, interpolated.
    @Nullable private ValueAnimator mThumbAnimator;
    @Nullable private ValueAnimator mGradientAnimator;
    private float mGradientPhase;
    @Nullable private OnCheckedChangeListener mListener;

    public BrowtherBigToggleView(Context context) {
        this(context, null);
    }

    public BrowtherBigToggleView(Context context, @Nullable AttributeSet attrs) {
        super(context, attrs);
        mDensity = context.getResources().getDisplayMetrics().density;
        mTrackPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        mThumbPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        mThumbPaint.setColor(THUMB_COLOR);
        mThumbShadowPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        mThumbShadowPaint.setColor(THUMB_SHADOW_COLOR);
        mThumbShadowPaint.setMaskFilter(null);
        setClickable(true);
    }

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        int desiredW = dp(TRACK_WIDTH_DP);
        int desiredH = dp(TRACK_HEIGHT_DP);
        setMeasuredDimension(
                resolveSize(desiredW, widthMeasureSpec),
                resolveSize(desiredH, heightMeasureSpec));
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        if (mChecked) startGradientAnimation();
    }

    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        stopGradientAnimation();
        if (mThumbAnimator != null) {
            mThumbAnimator.cancel();
            mThumbAnimator = null;
        }
    }

    @Override
    public boolean performClick() {
        // Note: lint expects performClick() to be invoked from onTouchEvent. We
        // rely on the default View.onTouchEvent (via setClickable(true) in the
        // constructor) which already calls performClick() on ACTION_UP — no
        // custom onTouchEvent needed, no DragInteraction here.
        super.performClick();
        toggle();
        return true;
    }

    /** Sets the listener invoked when the user toggles the switch. */
    public void setOnCheckedChangeListener(@Nullable OnCheckedChangeListener listener) {
        mListener = listener;
    }

    /** Sets the checked state programmatically (no listener fire, no animation). */
    public void setCheckedSilently(boolean checked) {
        mChecked = checked;
        mThumbProgress = checked ? 1f : 0f;
        if (checked && isAttachedToWindow()) {
            startGradientAnimation();
        } else {
            stopGradientAnimation();
        }
        invalidate();
    }

    /** Returns the current checked state. */
    public boolean isChecked() {
        return mChecked;
    }

    /** Toggles the state with animation and fires the listener. */
    public void toggle() {
        setCheckedAnimated(!mChecked, /* fireListener= */ true);
    }

    private void setCheckedAnimated(boolean checked, boolean fireListener) {
        if (mChecked == checked) return;
        mChecked = checked;
        if (mThumbAnimator != null) mThumbAnimator.cancel();
        float from = mThumbProgress;
        float to = checked ? 1f : 0f;
        mThumbAnimator = ValueAnimator.ofFloat(from, to);
        mThumbAnimator.setDuration(THUMB_DURATION_MS);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            mThumbAnimator.setInterpolator(new PathInterpolator(0.34f, 1.56f, 0.64f, 1f));
        }
        mThumbAnimator.addUpdateListener(
                animation -> {
                    mThumbProgress = (float) animation.getAnimatedValue();
                    invalidate();
                });
        mThumbAnimator.start();

        if (checked) {
            startGradientAnimation();
        } else {
            // Keep the gradient anim until the thumb crosses below the visible
            // track area — for simplicity, stop immediately and rely on
            // thumbProgress to fade the gradient via alpha.
            stopGradientAnimation();
        }

        if (fireListener && mListener != null) {
            mListener.onCheckedChanged(this, checked);
        }
    }

    private void startGradientAnimation() {
        if (mGradientAnimator != null) return;
        mGradientAnimator = ValueAnimator.ofFloat(0f, GRADIENT_KEYFRAMES.length);
        mGradientAnimator.setDuration(GRADIENT_CYCLE_MS);
        mGradientAnimator.setRepeatCount(ValueAnimator.INFINITE);
        mGradientAnimator.setRepeatMode(ValueAnimator.RESTART);
        mGradientAnimator.addUpdateListener(
                animation -> {
                    mGradientPhase = (float) animation.getAnimatedValue();
                    invalidate();
                });
        mGradientAnimator.start();
    }

    private void stopGradientAnimation() {
        if (mGradientAnimator != null) {
            mGradientAnimator.cancel();
            mGradientAnimator = null;
        }
    }

    @SuppressLint("DrawAllocation") // RadialGradient must be reconstructed each frame.
    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        float w = getWidth();
        float h = getHeight();
        float radius = h * 0.5f;
        mTrackRect.set(0f, 0f, w, h);

        // 1) Track. OFF state = solid grey; ON = radial gradient (interpolated
        // between 2 consecutive keyframes based on mGradientPhase).
        if (mThumbProgress < 1f) {
            // Paint the OFF base unconditionally; the ON state will be painted
            // over with alpha based on thumbProgress.
            mTrackPaint.setShader(null);
            mTrackPaint.setColor(TRACK_OFF_COLOR);
            mTrackPaint.setAlpha(255);
            canvas.drawRoundRect(mTrackRect, radius, radius, mTrackPaint);
        }
        if (mThumbProgress > 0f) {
            int phaseFloor = (int) Math.floor(mGradientPhase);
            float t = mGradientPhase - phaseFloor;
            int[] from = GRADIENT_KEYFRAMES[phaseFloor % GRADIENT_KEYFRAMES.length];
            int[] to = GRADIENT_KEYFRAMES[(phaseFloor + 1) % GRADIENT_KEYFRAMES.length];
            mGradientColorsBuf[0] = lerpColor(from[0], to[0], t);
            mGradientColorsBuf[1] = lerpColor(from[1], to[1], t);
            // Center bottom-right, spans toward top-left. radius ~= width.
            RadialGradient gradient =
                    new RadialGradient(
                            w * 0.9f,
                            h * 0.85f,
                            w * 1.1f,
                            mGradientColorsBuf,
                            mGradientStops,
                            Shader.TileMode.CLAMP);
            mTrackPaint.setShader(gradient);
            int alpha = (int) (mThumbProgress * 255f);
            mTrackPaint.setAlpha(alpha);
            canvas.drawRoundRect(mTrackRect, radius, radius, mTrackPaint);
            mTrackPaint.setShader(null);
            mTrackPaint.setAlpha(255);
        }

        // 2) Thumb. Inset 6 dp, translation ON = +44 dp.
        float inset = mDensity * THUMB_INSET_DP;
        float diameter = mDensity * THUMB_DIAMETER_DP;
        float thumbRadius = diameter * 0.5f;
        float thumbY = h * 0.5f;
        float thumbStartX = inset + thumbRadius;
        float thumbEndX = w - inset - thumbRadius;
        float thumbX = thumbStartX + (thumbEndX - thumbStartX) * mThumbProgress;

        // Subtle shadow under thumb (1dp drop).
        canvas.drawCircle(thumbX, thumbY + mDensity, thumbRadius, mThumbShadowPaint);
        canvas.drawCircle(thumbX, thumbY, thumbRadius, mThumbPaint);
    }

    private int dp(float v) {
        return (int)
                TypedValue.applyDimension(
                        TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics());
    }

    private static int lerpColor(int a, int b, float t) {
        int aA = (a >>> 24) & 0xFF;
        int aR = (a >> 16) & 0xFF;
        int aG = (a >> 8) & 0xFF;
        int aB = a & 0xFF;
        int bA = (b >>> 24) & 0xFF;
        int bR = (b >> 16) & 0xFF;
        int bG = (b >> 8) & 0xFF;
        int bB = b & 0xFF;
        int alpha = (int) (aA + (bA - aA) * t);
        int red = (int) (aR + (bR - aR) * t);
        int green = (int) (aG + (bG - aG) * t);
        int blue = (int) (aB + (bB - aB) * t);
        return Color.argb(alpha, red, green, blue);
    }
}
