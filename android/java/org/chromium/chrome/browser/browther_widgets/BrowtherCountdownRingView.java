/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_widgets;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.util.AttributeSet;
import android.view.View;

import androidx.annotation.Nullable;

import org.chromium.build.annotations.NullMarked;

/**
 * Anneau de compte à rebours « 2 min » de Sawtunaa (2026-10-01, port de l'iOS
 * {@code BrowtherBadgedToolbarButton.setCountdown}). Posé par-dessus le bouton de la barre d'outils,
 * il remplace la pastille d'état pendant le compte à rebours ; sa couleur est celle de l'état ACTUEL
 * (rouge coupé, ambre/vert allumé).
 *
 * <p>Pas d'animation continue : la barre d'outils le met à jour ~1×/s (chaque mise à jour force une
 * nouvelle capture de la barre, qui coûte). {@link #drawRing} sert aussi au bouton rond de {@link
 * BrowtherBigToggleView}.
 *
 * <p>Mode « chargement » ({@link #setSpinner}) : un arc de ~28 % qui tourne, prioritaire sur
 * l'anneau — port de l'iOS {@code BrowtherBadgedToolbarButton.setLoading}. La barre le fait avancer
 * par pas de 36° toutes les 100 ms (~10 i/s) : assez pour lire « ça charge », et borné en captures
 * de barre (l'état dure ~1-2 s).
 */
@NullMarked
public class BrowtherCountdownRingView extends View {
    private static final int TRACK_COLOR = 0x33888888;

    private final Paint mPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF mOval = new RectF();
    private float mFraction = -1f;
    private int mColor;
    private boolean mSpinner;
    private float mSpinnerAngle;
    private int mSpinnerColor;

    public BrowtherCountdownRingView(Context context) {
        this(context, null);
    }

    public BrowtherCountdownRingView(Context context, @Nullable AttributeSet attrs) {
        super(context, attrs);
        setWillNotDraw(false);
    }

    /** {@code fraction} < 0 : rien n'est dessiné. */
    public void setCountdown(float fraction, int color) {
        if (fraction == mFraction && color == mColor) return;
        mFraction = fraction;
        mColor = color;
        invalidate();
    }

    public void setSpinner(boolean on, int color) {
        if (on == mSpinner && color == mSpinnerColor) return;
        mSpinner = on;
        mSpinnerColor = color;
        invalidate();
    }

    /** Fait tourner l'arc d'un pas (appelé par la barre d'outils, ~10×/s). */
    public void advanceSpinner() {
        if (!mSpinner) return;
        mSpinnerAngle = (mSpinnerAngle + 36f) % 360f;
        invalidate();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        float density = getResources().getDisplayMetrics().density;
        float stroke = 2f * density;
        float radius = Math.min(getWidth(), getHeight()) * 0.5f - stroke * 0.5f;
        if (mSpinner) {
            mPaint.setStyle(Paint.Style.STROKE);
            mPaint.setStrokeWidth(stroke);
            mPaint.setStrokeCap(Paint.Cap.ROUND);
            mPaint.setColor(mSpinnerColor);
            float cx = getWidth() * 0.5f;
            float cy = getHeight() * 0.5f;
            mOval.set(cx - radius, cy - radius, cx + radius, cy + radius);
            canvas.drawArc(mOval, mSpinnerAngle - 90f, 360f * 0.28f, false, mPaint);
            mPaint.setStyle(Paint.Style.FILL);
            return;
        }
        if (mFraction < 0f) return;
        drawRing(
                canvas, mPaint, mOval, getWidth() * 0.5f, getHeight() * 0.5f, radius, stroke,
                mFraction, mColor);
    }

    /** Piste discrète + arc de {@code fraction} tour, partant de midi, dans le sens horaire. */
    public static void drawRing(
            Canvas canvas,
            Paint paint,
            RectF oval,
            float cx,
            float cy,
            float radius,
            float stroke,
            float fraction,
            int color) {
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(stroke);
        paint.setStrokeCap(Paint.Cap.ROUND);
        oval.set(cx - radius, cy - radius, cx + radius, cy + radius);
        paint.setColor(TRACK_COLOR);
        canvas.drawOval(oval, paint);
        paint.setColor(color);
        float clamped = Math.max(0f, Math.min(1f, fraction));
        canvas.drawArc(oval, -90f, 360f * clamped, false, paint);
        paint.setStyle(Paint.Style.FILL);
    }

    /**
     * Flèche de retour (demi-tour) centrée en ({@code cx}, {@code cy}) : dit que l'interrupteur
     * reviendra tout seul.
     */
    public static void drawBackArrow(
            Canvas canvas, Paint paint, Path path, RectF oval, float cx, float cy, float size,
            int color) {
        float r = size * 0.32f;
        float stroke = size * 0.11f;
        paint.setColor(color);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(stroke);
        paint.setStrokeCap(Paint.Cap.ROUND);
        paint.setStrokeJoin(Paint.Join.ROUND);
        // Arc ouvert en haut à gauche, terminé par une pointe.
        oval.set(cx - r, cy - r, cx + r, cy + r);
        canvas.drawArc(oval, 200f, 270f, false, paint);
        double end = Math.toRadians(200f);
        float ex = cx + (float) (r * Math.cos(end));
        float ey = cy + (float) (r * Math.sin(end));
        float head = size * 0.16f;
        path.reset();
        path.moveTo(ex - head, ey - head * 0.2f);
        path.lineTo(ex, ey);
        path.lineTo(ex + head * 0.3f, ey - head);
        canvas.drawPath(path, paint);
        paint.setStyle(Paint.Style.FILL);
    }
}
