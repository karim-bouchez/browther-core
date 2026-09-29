/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Outline;
import android.graphics.RectF;
import android.graphics.drawable.ColorDrawable;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.widget.FrameLayout;
import android.widget.LinearLayout;

import androidx.annotation.Nullable;

import org.chromium.chrome.browser.browther_referral.core.ReferralShare;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatus;

import java.util.Locale;

/**
 * Le code : une carte qu'on tient (§ 12.3, § 12.24) — port de {@code ReferralCodeCard} iOS.
 *
 * <p>⭐ Le code se DICTE à un proche : il se lit comme un objet qu'on montre, ⛔ pas comme un
 * encadré en pointillés. Format carte bancaire (85,6 × 54 mm). Depuis le 2026-09-28, <b>une carte
 * par produit</b> : celle de Browther est la <b>B9 « Onglets + barre »</b> ({@link
 * ReferralCardFace}), l'or commun a disparu.
 *
 * <ul>
 *   <li>Le lien est dans la barre d'adresse, EN ENTIER : la face est cotée en 330 × 208 et mise à
 *       l'échelle de la largeur disponible (plafonnée à 340 dp, comme iOS).
 *   <li>« Copier » à sa droite copie le MESSAGE complet, et c'est un partage ABOUTI (§ 12.20) :
 *       {@code onCopied} le dit.
 *   <li>⚠️ Couleurs FIXES dans les deux thèmes ; en arabe, la face se dessine en miroir (le code et
 *       le lien restent de gauche à droite).
 * </ul>
 */
public class ReferralCodeCard extends FrameLayout {
    private static final float MAX_WIDTH_DP = 340;

    private final ReferralStatus mStatus;
    private final @Nullable Runnable mOnCopied;
    private final ReferralCardFace mFace;
    private final View mCopyTarget;
    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private float mShine = -0.4f;
    private boolean mSweptOnce;

    public ReferralCodeCard(Context context, ReferralStatus status, @Nullable Runnable onCopied) {
        super(context);
        mStatus = status;
        mOnCopied = onCopied;
        setWillNotDraw(false);
        // ⚠️ La face gère elle-même son miroir : la vue reste de gauche à droite.
        setLayoutDirection(LAYOUT_DIRECTION_LTR);

        String code = code();
        String link = ReferralShare.link(code, status.referral.url).replace("https://", "");
        boolean rtl =
                context.getResources().getConfiguration().getLayoutDirection()
                        == View.LAYOUT_DIRECTION_RTL;
        mFace =
                ReferralCardFace.app(
                        context,
                        code,
                        link,
                        ReferralStrings.get(context, "card.copy"),
                        ReferralStrings.get(context, "home.title"),
                        ReferralStrings.get(context, "card.codeHead"),
                        ReferralStrings.get(context, "card.tag"),
                        rtl);

        setContentDescription(
                ReferralStrings.get(context, "card.codeHead") + " " + spaced(code) + ". " + link);

        // « Copier » est dessiné par la face ; une vue transparente posée dessus le rend touchable
        // et lisible par TalkBack.
        mCopyTarget = new View(context);
        mCopyTarget.setClickable(true);
        mCopyTarget.setFocusable(true);
        mCopyTarget.setContentDescription(ReferralStrings.get(context, "card.copy"));
        mCopyTarget.setBackground(
                ReferralUi.pressable(new ColorDrawable(Color.TRANSPARENT), 0x33FFFFFF, ReferralUi.dp(context, 100)));
        mCopyTarget.setOnClickListener(v -> copy());
        addView(mCopyTarget, new LayoutParams(0, 0));

        // L'ombre portée d'iOS (noir 35 %, rayon 16, 10 vers le bas) : une élévation sur le contour
        // arrondi de la carte.
        setOutlineProvider(
                new ViewOutlineProvider() {
                    @Override
                    public void getOutline(View view, Outline outline) {
                        float radius = 18f * view.getWidth() / ReferralCardFace.WIDTH;
                        outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), radius);
                    }
                });
        setElevation(ReferralUi.dp(context, 8));

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
        int width =
                MeasureSpec.getMode(widthMeasureSpec) == MeasureSpec.UNSPECIFIED
                        ? max
                        : Math.min(available, max);
        int height = Math.round(width * ReferralCardFace.HEIGHT / ReferralCardFace.WIDTH);
        placeCopyTarget(width);
        super.onMeasure(
                MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY));
    }

    /** La zone touchable de « Copier » : son rectangle dessiné, agrandi à 44 dp de haut. */
    private void placeCopyTarget(int width) {
        float scale = width / ReferralCardFace.WIDTH;
        RectF rect = mFace.copyRect();
        int minHeight = ReferralUi.dp(getContext(), 44);
        int h = Math.max(minHeight, Math.round(rect.height() * scale));
        LayoutParams params = (LayoutParams) mCopyTarget.getLayoutParams();
        params.width = Math.round(rect.width() * scale);
        params.height = h;
        params.leftMargin = Math.round(rect.left * scale);
        params.topMargin = Math.round(rect.centerY() * scale - h / 2f);
        // ⚠️ Pendant la mesure : on modifie les paramètres sans `setLayoutParams` (pas de nouvelle
        // demande de mise en page), `super.onMeasure` les lit juste après.
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
        if (w == 0) return;
        canvas.save();
        float scale = w / ReferralCardFace.WIDTH;
        canvas.scale(scale, scale);
        mFace.draw(canvas, mShine);
        canvas.restore();
    }

    /** Un reflet la balaie à l'arrivée et à la copie. */
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
        Context context = getContext();
        ReferralSharing.copy(context, mStatus);
        ReferralUi.success(this);
        mFace.setCopied(true, ReferralStrings.get(context, "card.copied"));
        requestLayout();
        invalidate();
        sweep(0);
        if (mOnCopied != null) mOnCopied.run();
        mHandler.removeCallbacksAndMessages(null);
        mHandler.postDelayed(
                () -> {
                    mFace.setCopied(false, ReferralStrings.get(getContext(), "card.copy"));
                    requestLayout();
                    invalidate();
                },
                2_000);
    }
}
