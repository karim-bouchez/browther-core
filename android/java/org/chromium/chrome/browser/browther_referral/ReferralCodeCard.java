/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.animation.ValueAnimator;
import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.os.Handler;
import android.os.Looper;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.Nullable;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_referral.core.ReferralShare;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatus;

import java.util.Locale;

/**
 * Le code : une carte qu'on tient (§ 12.3, § 12.24) — port de {@code ReferralCodeCard} iOS.
 *
 * <p>⭐ Le code se DICTE à un proche : il se lit comme un objet qu'on montre, ⛔ pas comme un
 * encadré en pointillés. Format carte bancaire (85,6 × 54 mm), or brossé, puce, guillochis, le nom
 * du produit en encre SOMBRE.
 *
 * <ul>
 *   <li>⚠️ Couleurs FIXES dans les deux thèmes : une carte n'a pas de thème.
 *   <li>⚠️ « Copier » est une pastille SOMBRE sur l'or (contraste). Il copie le MESSAGE complet, et
 *       c'est un partage ABOUTI (§ 12.20) : {@code onCopied} le dit.
 *   <li>⚠️ Toujours de gauche à droite, même en arabe : un code se lit dans ce sens.
 * </ul>
 */
public class ReferralCodeCard extends FrameLayout {
    private static final float RATIO = 1.586f;
    private static final float MAX_WIDTH_DP = 320;
    private static final int INK = ReferralUi.Palette.INK;

    private final ReferralStatus mStatus;
    private final @Nullable Runnable mOnCopied;
    private final Paint mPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path mClip = new Path();
    private final RectF mRect = new RectF();
    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private final TextView mCopyLabel;
    private final ImageView mCopyIcon;
    private float mShine = -0.4f;
    private boolean mSweptOnce;

    public ReferralCodeCard(Context context, ReferralStatus status, @Nullable Runnable onCopied) {
        super(context);
        mStatus = status;
        mOnCopied = onCopied;
        setWillNotDraw(false);
        setLayoutDirection(LAYOUT_DIRECTION_LTR);
        setClipToOutline(false);

        String code = code();
        String link = ReferralShare.link(code, status.referral.url).replace("https://", "");

        LinearLayout content = ReferralUi.column(context);
        int pad = ReferralUi.dp(context, 16);
        content.setPadding(pad, pad, pad, pad);

        TextView brand = ReferralUi.text(context, "Browther", 17, ReferralUi.BOLD, INK);
        content.addView(brand);
        content.addView(new View(context), new LinearLayout.LayoutParams(1, 0, 1));

        TextView head =
                ReferralUi.text(
                        context,
                        ReferralStrings.get(context, "card.codeHead").toUpperCase(
                                ReferralFormat.locale(context)),
                        10,
                        ReferralUi.SEMIBOLD,
                        ReferralUi.withAlpha(INK, 0.6f));
        head.setLetterSpacing(0.18f);
        content.addView(head);

        TextView codeView = ReferralUi.text(context, code, 28, ReferralUi.SEMIBOLD, INK);
        codeView.setTypeface(Typeface.create(Typeface.MONOSPACE, Typeface.BOLD));
        codeView.setLetterSpacing(0.25f);
        codeView.setShadowLayer(0.01f, 0, ReferralUi.dp(context, 1), 0x8CFFFFFF);
        codeView.setTextIsSelectable(true);
        codeView.setContentDescription(spaced(code));
        codeView.setSingleLine(true);
        content.addView(codeView);
        content.addView(new View(context), new LinearLayout.LayoutParams(1, 0, 1));

        LinearLayout bottom = ReferralUi.row(context);
        // ⚠️ Coupé AU MILIEU s'il déborde : la fin du lien porte le code.
        TextView linkView =
                ReferralUi.text(context, link, 10.5f, ReferralUi.REGULAR, ReferralUi.withAlpha(INK, 0.65f));
        linkView.setSingleLine(true);
        linkView.setEllipsize(TextUtils.TruncateAt.MIDDLE);
        LinearLayout.LayoutParams linkParams = new LinearLayout.LayoutParams(0, ReferralUi.WRAP, 1);
        linkParams.setMarginEnd(ReferralUi.dp(context, 8));
        bottom.addView(linkView, linkParams);

        LinearLayout copy = ReferralUi.row(context);
        copy.setGravity(Gravity.CENTER);
        int copyPad = ReferralUi.dp(context, 12);
        copy.setPadding(copyPad, 0, copyPad, 0);
        copy.setBackground(
                ReferralUi.pressable(
                        ReferralUi.rounded(INK, ReferralUi.dp(context, 100)),
                        0x33FFFFFF,
                        ReferralUi.dp(context, 100)));
        mCopyIcon = ReferralUi.glyph(context, R.drawable.browther_referral_glyph_copy, 13, 0xFFFBE6AD);
        copy.addView(mCopyIcon);
        mCopyLabel = ReferralUi.text(context, 13, ReferralUi.SEMIBOLD, 0xFFFBE6AD);
        mCopyLabel.setText(ReferralStrings.get(context, "card.copy"));
        LinearLayout.LayoutParams labelParams =
                new LinearLayout.LayoutParams(ReferralUi.WRAP, ReferralUi.WRAP);
        labelParams.setMarginStart(ReferralUi.dp(context, 6));
        copy.addView(mCopyLabel, labelParams);
        copy.setClickable(true);
        copy.setFocusable(true);
        copy.setContentDescription(ReferralStrings.get(context, "card.copy"));
        copy.setOnClickListener(v -> copy());
        bottom.addView(copy, new LinearLayout.LayoutParams(ReferralUi.WRAP, ReferralUi.dp(context, 32)));
        content.addView(bottom, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));

        addView(content, new LayoutParams(ReferralUi.MATCH, ReferralUi.MATCH));

        LinearLayout.LayoutParams params =
                new LinearLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.WRAP);
        params.gravity = Gravity.CENTER_HORIZONTAL;
        setLayoutParams(params);
    }

    private String code() {
        String code = mStatus.referral.code == null ? "" : mStatus.referral.code;
        return code.toUpperCase(Locale.ROOT);
    }

    private static String spaced(String code) {
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < code.length(); i++) {
            if (i > 0) out.append(' ');
            out.append(code.charAt(i));
        }
        return out.toString();
    }

    // -------------------- Mesure : le ratio de la carte, plafonnée --------------------

    @Override
    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
        int available = MeasureSpec.getSize(widthMeasureSpec);
        int max = ReferralUi.dp(getContext(), MAX_WIDTH_DP);
        int width = MeasureSpec.getMode(widthMeasureSpec) == MeasureSpec.UNSPECIFIED
                ? max
                : Math.min(available, max);
        int height = Math.round(width / RATIO);
        super.onMeasure(
                MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY));
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        if (!mSweptOnce) {
            mSweptOnce = true;
            sweep(250);
        }
    }

    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        mHandler.removeCallbacksAndMessages(null);
    }

    // -------------------- Dessin --------------------

    @Override
    protected void onDraw(Canvas canvas) {
        float w = getWidth();
        float h = getHeight();
        if (w == 0) return;
        Context context = getContext();
        float radius = ReferralUi.dp(context, 18);
        mRect.set(0, 0, w, h);
        mClip.reset();
        mClip.addRoundRect(mRect, radius, radius, Path.Direction.CW);
        canvas.save();
        canvas.clipPath(mClip);

        // L'or brossé. ⚠️ Opacité remise à 100 % AVANT chaque dégradé : un shader hérite de
        // l'alpha de la peinture, et le liseré (12 %) de l'image précédente peignait sinon l'or
        // à 12 % — une carte beige dès le premier redessin (aperçu émulateur, 2026-09-24).
        mPaint.setColor(0xFFFFFFFF);
        mPaint.setStyle(Paint.Style.FILL);
        mPaint.setShader(
                new LinearGradient(
                        0, 0, w, h,
                        new int[] {0xFFF8DC97, 0xFFE9B551, 0xFFCF922F, 0xFFA86B17},
                        new float[] {0f, 0.36f, 0.68f, 1f},
                        Shader.TileMode.CLAMP));
        canvas.drawRect(mRect, mPaint);
        mPaint.setShader(
                new LinearGradient(
                        0, 0, w * 0.4f, h * 0.45f,
                        0x66FFFFFF, 0x00FFFFFF,
                        Shader.TileMode.CLAMP));
        canvas.drawRect(mRect, mPaint);
        mPaint.setShader(null);

        // Le guillochis : le centre est DANS la carte (60 dp du bord droit, 42 dp du bas) —
        // centré sur le coin, il n'en montrait que des quarts de cercle décalés.
        mPaint.setStyle(Paint.Style.STROKE);
        mPaint.setStrokeWidth(ReferralUi.dp(context, 1.8f));
        mPaint.setColor(ReferralUi.withAlpha(INK, 0.3f));
        float cx = w - ReferralUi.dp(context, 60);
        float cy = h - ReferralUi.dp(context, 42);
        for (int r : new int[] {20, 36, 52, 68, 84, 100}) {
            canvas.drawCircle(cx, cy, ReferralUi.dp(context, r * 1.2f), mPaint);
        }

        drawChip(canvas, w - ReferralUi.dp(context, 16 + 38), ReferralUi.dp(context, 16));
        canvas.restore();

        mPaint.setStyle(Paint.Style.STROKE);
        mPaint.setStrokeWidth(1);
        mPaint.setColor(0x1F000000);
        canvas.drawRoundRect(mRect, radius, radius, mPaint);
    }

    /** La puce : ce qui fait lire « carte » au premier coup d'œil. */
    private void drawChip(Canvas canvas, float left, float top) {
        Context context = getContext();
        float unit = ReferralUi.dp(context, 1);
        float w = 38 * unit;
        float h = 29 * unit;
        RectF chip = new RectF(left, top, left + w, top + h);
        mPaint.setColor(0xFFFFFFFF);
        mPaint.setStyle(Paint.Style.FILL);
        mPaint.setShader(
                new LinearGradient(
                        left, top, left + w, top + h,
                        new int[] {0xFFFFF4D3, 0xFFE2B457, 0xFFB98124},
                        null,
                        Shader.TileMode.CLAMP));
        canvas.drawRoundRect(chip, 5 * unit, 5 * unit, mPaint);
        mPaint.setShader(null);
        mPaint.setStyle(Paint.Style.STROKE);
        mPaint.setStrokeWidth(unit);
        mPaint.setColor(ReferralUi.withAlpha(INK, 0.35f));
        for (float y : new float[] {9.5f, 18.5f}) {
            canvas.drawLine(left, top + y * unit, left + 12.5f * unit, top + y * unit, mPaint);
            canvas.drawLine(left + 25.5f * unit, top + y * unit, left + w, top + y * unit, mPaint);
        }
        for (float x : new float[] {12.5f, 25.5f}) {
            canvas.drawLine(left + x * unit, top, left + x * unit, top + h, mPaint);
        }
        canvas.drawLine(left + 12.5f * unit, top + 14.5f * unit, left + 25.5f * unit,
                top + 14.5f * unit, mPaint);
        mPaint.setColor(0x33000000);
        canvas.drawRoundRect(chip, 5 * unit, 5 * unit, mPaint);
    }

    /** Un reflet la balaie à l'arrivée et à la copie. */
    @Override
    protected void dispatchDraw(Canvas canvas) {
        super.dispatchDraw(canvas);
        if (mShine <= -0.4f || mShine >= 1f || getWidth() == 0) return;
        float w = getWidth();
        float h = getHeight();
        float band = w * 0.35f;
        float x = mShine * w * 1.8f - w * 0.2f;
        canvas.save();
        canvas.clipPath(mClip);
        canvas.rotate(18, x + band / 2, h / 2);
        mPaint.setColor(0xFFFFFFFF);
        mPaint.setStyle(Paint.Style.FILL);
        mPaint.setShader(
                new LinearGradient(
                        x, 0, x + band, 0,
                        new int[] {0x00FFFFFF, 0x8CFFFFFF, 0x00FFFFFF},
                        null,
                        Shader.TileMode.CLAMP));
        canvas.drawRect(x, -h, x + band, h * 2, mPaint);
        mPaint.setShader(null);
        canvas.restore();
    }

    private void sweep(long delayMs) {
        if (ReferralUi.reduceMotion(getContext())) return;
        ValueAnimator animator = ValueAnimator.ofFloat(-0.4f, 1f);
        animator.setDuration(900);
        animator.setStartDelay(delayMs);
        animator.setInterpolator(ReferralUi.EASE_OUT);
        animator.addUpdateListener(
                a -> {
                    mShine = (float) a.getAnimatedValue();
                    invalidate();
                });
        animator.start();
    }

    // -------------------- Copier --------------------

    private void copy() {
        ReferralSharing.copy(getContext(), mStatus);
        ReferralUi.success(this);
        mCopyLabel.setText(ReferralStrings.get(getContext(), "card.copied"));
        mCopyIcon.setImageResource(R.drawable.browther_intro_glyph_check);
        mCopyIcon.setImageTintList(ColorStateList.valueOf(0xFFFBE6AD));
        sweep(0);
        if (mOnCopied != null) mOnCopied.run();
        mHandler.removeCallbacksAndMessages(null);
        mHandler.postDelayed(
                () -> {
                    mCopyLabel.setText(ReferralStrings.get(getContext(), "card.copy"));
                    mCopyIcon.setImageResource(R.drawable.browther_referral_glyph_copy);
                },
                2_000);
    }
}
