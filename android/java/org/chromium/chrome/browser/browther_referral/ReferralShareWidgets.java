/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Canvas;
import android.graphics.Outline;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.drawable.GradientDrawable;
import android.os.SystemClock;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

import androidx.annotation.Nullable;

import org.chromium.chrome.R;

import java.util.Locale;

/**
 * Les pièces communes de la feuille « Partager mon code » ({@link ReferralShareSheet}) — pendant
 * du bas de {@code ReferralShareSheet.swift} : le cadre d'un statut, la pastille d'une vidéo, la
 * coche, et le bouton à jauge. private/docs/PARRAINAGE.md § 11.
 */
final class ReferralShareWidgets {
    private ReferralShareWidgets() {}

    /** Le bleu d'un lien posé sur du noir (la légende d'un statut). */
    static final int CAPTION_LINK = 0xFF7DD3FC;

    /** Le lien tel que WhatsApp le montre : sans son {@code https://}. */
    static String bareLink(String link) {
        return link.startsWith("https://") ? link.substring("https://".length()) : link;
    }

    /** {@code 41} → {@code 0:41}. */
    static String clock(int seconds) {
        return String.format(Locale.ROOT, "%d:%02d", seconds / 60, seconds % 60);
    }

    /** Rogne une vue (et ce qu'elle contient, vidéo comprise) à des coins arrondis. */
    static void clipRounded(View view, float radiusPx) {
        view.setOutlineProvider(
                new ViewOutlineProvider() {
                    @Override
                    public void getOutline(View v, Outline outline) {
                        outline.setRoundRect(0, 0, v.getWidth(), v.getHeight(), radiusPx);
                    }
                });
        view.setClipToOutline(true);
    }

    static ProgressBar spinner(Context context, int color) {
        ProgressBar spinner = new ProgressBar(context);
        spinner.setIndeterminate(true);
        spinner.setIndeterminateTintList(ColorStateList.valueOf(color));
        return spinner;
    }

    // -------------------- Le cadre d'un statut --------------------

    /**
     * Un statut WhatsApp en réduction : le média, la barre de progression en haut, le LIEN EN
     * LÉGENDE en bas, là où WhatsApp le posera — ⭐ l'aperçu dit ce que fait le geste (Karim,
     * 2026-09-29). Toujours en 9:16 : sa hauteur suit sa largeur.
     */
    static final class StatusFrame extends FrameLayout {
        private final FrameLayout mMedia;
        private final TextView mCaption;
        private final float mCaptionPx;
        /** Pour mesurer le lien à sa taille d'origine, sans rien allouer pendant une mesure. */
        private final Paint mCaptionPaint;
        private final ProgressBar mSpinner;
        private final LinearLayout mSent;
        private final TextView mSentLabel;

        /**
         * @param small une des deux vignettes (sinon le grand cadre de l'image seule).
         */
        StatusFrame(Context context, boolean small, String link) {
            super(context);
            setBackgroundColor(0xFF000000);
            clipRounded(this, ReferralUi.dp(context, small ? 18 : 22));

            mMedia = new FrameLayout(context);
            addView(mMedia, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.MATCH));

            View bar = new View(context);
            bar.setBackground(ReferralUi.rounded(0xCCFFFFFF, ReferralUi.dp(context, 1)));
            FrameLayout.LayoutParams barParams =
                    new FrameLayout.LayoutParams(
                            ReferralUi.MATCH, ReferralUi.dp(context, 2), Gravity.TOP);
            int barMargin = ReferralUi.dp(context, small ? 7 : 8);
            barParams.setMargins(barMargin, barMargin, barMargin, 0);
            addView(bar, barParams);

            // ⚠️ Un lien se lit de gauche à droite, même en arabe.
            mCaption = ReferralUi.text(context, bareLink(link), small ? 9 : 11, ReferralUi.REGULAR, CAPTION_LINK);
            mCaptionPx = mCaption.getTextSize();
            mCaptionPaint = new Paint(mCaption.getPaint());
            mCaption.setSingleLine(true);
            mCaption.setEllipsize(TextUtils.TruncateAt.END);
            mCaption.setGravity(Gravity.CENTER_HORIZONTAL);
            mCaption.setTextDirection(View.TEXT_DIRECTION_LTR);
            int captionSide = ReferralUi.dp(context, small ? 8 : 12);
            mCaption.setPadding(
                    captionSide,
                    ReferralUi.dp(context, 22),
                    captionSide,
                    ReferralUi.dp(context, small ? 9 : 12));
            mCaption.setBackground(
                    new GradientDrawable(
                            GradientDrawable.Orientation.BOTTOM_TOP,
                            new int[] {0xD9000000, 0x00000000}));
            mCaption.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
            addView(mCaption, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.WRAP, Gravity.BOTTOM));

            mSpinner = spinner(context, 0xFFFFFFFF);
            int spinnerSize = ReferralUi.dp(context, 28);
            addView(mSpinner, new FrameLayout.LayoutParams(spinnerSize, spinnerSize, Gravity.CENTER));
            mSpinner.setVisibility(GONE);

            // « Publié » : un voile, une coche dans un rond, le mot.
            mSent = ReferralUi.column(context);
            mSent.setGravity(Gravity.CENTER);
            mSent.setBackgroundColor(0x9E0E0C08);
            FrameLayout ring = new FrameLayout(context);
            GradientDrawable outline = new GradientDrawable();
            outline.setShape(GradientDrawable.OVAL);
            outline.setStroke(ReferralUi.dp(context, 2), 0xFFFFFFFF);
            ring.setBackground(outline);
            int tick = ReferralUi.dp(context, 15);
            ring.addView(
                    ReferralUi.glyph(context, R.drawable.browther_intro_glyph_check, 15, 0xFFFFFFFF),
                    new FrameLayout.LayoutParams(tick, tick, Gravity.CENTER));
            int ringSize = ReferralUi.dp(context, 34);
            mSent.addView(ring, new LinearLayout.LayoutParams(ringSize, ringSize));
            mSentLabel = ReferralUi.text(context, 15, ReferralUi.SEMIBOLD, 0xFFFFFFFF);
            mSentLabel.setGravity(Gravity.CENTER_HORIZONTAL);
            mSent.addView(
                    mSentLabel,
                    ReferralUi.linear(ReferralUi.WRAP, ReferralUi.WRAP, ReferralUi.dp(context, 8)));
            mSent.setVisibility(GONE);
            addView(mSent, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.MATCH));
        }

        /** Ce que le cadre montre : la vidéo qui joue, l'image — ou rien encore. */
        void setMedia(@Nullable View media) {
            mMedia.removeAllViews();
            if (media != null) {
                mMedia.addView(media, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.MATCH));
            }
        }

        void setLoading(boolean loading) {
            mSpinner.setVisibility(loading ? VISIBLE : GONE);
        }

        /** Décochée : estompée. */
        void setDimmed(boolean dimmed) {
            setAlpha(dimmed ? 0.4f : 1f);
        }

        /** Le statut est parti : son libellé (« Publié »), sinon {@code null}. */
        void setSent(@Nullable String label) {
            mSent.setVisibility(label == null ? GONE : VISIBLE);
            if (label != null) mSentLabel.setText(label);
        }

        @Override
        protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
            int width = MeasureSpec.getSize(widthMeasureSpec);
            int height = Math.round(width * 16f / 9f);
            fitCaption(width);
            super.onMeasure(
                    MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
                    MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY));
        }

        /**
         * Le lien tient EN ENTIER dans la légende : au besoin un peu plus petit (jusqu'à 70 %),
         * comme le {@code minimumScaleFactor} d'iOS — « … » seulement au-delà.
         */
        private void fitCaption(int width) {
            float room = width - mCaption.getPaddingLeft() - mCaption.getPaddingRight();
            if (room <= 0) return;
            float needed = mCaptionPaint.measureText(mCaption.getText().toString());
            float size =
                    needed <= room ? mCaptionPx : Math.max(mCaptionPx * 0.7f, mCaptionPx * room / needed);
            if (Math.abs(size - mCaption.getTextSize()) > 0.5f) {
                mCaption.setTextSize(TypedValue.COMPLEX_UNIT_PX, size);
            }
        }
    }

    // -------------------- La pastille d'une vidéo --------------------

    /** ▶ et la durée, dès qu'elle est connue. Toujours de gauche à droite. */
    static final class VideoTag extends LinearLayout {
        private final TextView mClock;

        VideoTag(Context context) {
            super(context);
            setOrientation(HORIZONTAL);
            setGravity(Gravity.CENTER_VERTICAL);
            setLayoutDirection(LAYOUT_DIRECTION_LTR);
            int padH = ReferralUi.dp(context, 7);
            int padV = ReferralUi.dp(context, 4);
            setPadding(padH, padV, padH, padV);
            setBackground(ReferralUi.rounded(0x8C000000, ReferralUi.dp(context, 100)));
            addView(ReferralUi.glyph(context, R.drawable.browther_intro_glyph_play, 8, 0xFFFFFFFF));
            mClock = ReferralUi.text(context, 11, ReferralUi.MEDIUM, 0xFFFFFFFF);
            mClock.setIncludeFontPadding(false);
            LinearLayout.LayoutParams params =
                    new LinearLayout.LayoutParams(ReferralUi.WRAP, ReferralUi.WRAP);
            params.setMarginStart(ReferralUi.dp(context, 4));
            addView(mClock, params);
            mClock.setVisibility(GONE);
            setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
        }

        /** {@code seconds < 0} : durée pas encore connue. */
        void setSeconds(int seconds) {
            mClock.setVisibility(seconds < 0 ? GONE : VISIBLE);
            if (seconds >= 0) mClock.setText(clock(seconds));
        }
    }

    // -------------------- La coche --------------------

    /**
     * Une coche dans sa forme : ronde en haut d'une vignette, carrée aux coins doux devant « Joindre
     * la vidéo ». Elle ne se touche pas elle-même : le geste est celui de ce qui la porte.
     */
    static final class CheckMark extends FrameLayout {
        private final GradientDrawable mShape = new GradientDrawable();
        private final ImageView mTick;
        private final int mOnFill;
        private final int mOffFill;

        /**
         * @param radiusDp le rayon des coins — au moins la moitié du côté : un rond.
         */
        CheckMark(
                Context context,
                float sizeDp,
                float radiusDp,
                int onFill,
                int offFill,
                int stroke,
                int tick) {
            super(context);
            mOnFill = onFill;
            mOffFill = offFill;
            mShape.setCornerRadius(ReferralUi.dp(context, radiusDp));
            mShape.setStroke(ReferralUi.dp(context, 2), stroke);
            setBackground(mShape);
            mTick = ReferralUi.glyph(context, R.drawable.browther_intro_glyph_check, 12, tick);
            int tickSize = ReferralUi.dp(context, 12);
            addView(mTick, new FrameLayout.LayoutParams(tickSize, tickSize, Gravity.CENTER));
            int size = ReferralUi.dp(context, sizeDp);
            setLayoutParams(new LinearLayout.LayoutParams(size, size));
            setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
            setChecked(true);
        }

        void setChecked(boolean checked) {
            mShape.setColor(checked ? mOnFill : mOffFill);
            mTick.setVisibility(checked ? VISIBLE : INVISIBLE);
        }
    }

    // -------------------- Le bouton à jauge --------------------

    /**
     * Le bouton PLEIN de la feuille, et sa <b>jauge</b> : elle annonce que le geste suivant partira
     * tout seul. ⭐ Plein, et pas un contour qui se remplit : en contour, une jauge se lit « ce
     * bouton n'est pas encore disponible » (retour Karim sur Fajrunaa, 2026-10-07). L'aplat du
     * bouton, et par-dessus un voile à 25 % qui s'élargit dans le sens de lecture.
     *
     * <p>⚠️ La jauge avance à l'horloge ({@link SystemClock#uptimeMillis}), ⛔ pas par un {@code
     * ValueAnimator} : avec « Supprimer les animations » un animateur finit à l'instant, et la jauge
     * serait pleine avant d'avoir rien annoncé — or c'est une information, pas un décor.
     *
     * <p>Mêmes cotes que {@code ReferralUi.primaryButton}. La roue d'attente prend la place du
     * pictogramme : le libellé ne bouge pas.
     */
    static final class GaugeButton extends FrameLayout {
        private final ReferralUi.Palette mP;
        private final Paint mPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final RectF mRect = new RectF();
        private final Path mClip = new Path();
        private final float mRadius;
        private final ImageView mIcon;
        private final ProgressBar mSpinner;
        private final TextView mLabel;
        private boolean mBusy;
        private boolean mAvailable = true;
        /** Le départ de la jauge ({@code uptimeMillis}) — {@code -1} : aucun passage annoncé. */
        private long mGaugeStart = -1;
        private long mGaugeMs;

        GaugeButton(Context context, ReferralUi.Palette p, int iconRes, Runnable action) {
            super(context);
            mP = p;
            mRadius = ReferralUi.dp(context, 18);
            setWillNotDraw(false);
            setMinimumHeight(ReferralUi.dp(context, 52));
            int padH = ReferralUi.dp(context, 16);
            int padV = ReferralUi.dp(context, 8);
            setPadding(padH, padV, padH, padV);

            LinearLayout line = ReferralUi.row(context);
            line.setGravity(Gravity.CENTER);
            FrameLayout slot = new FrameLayout(context);
            mIcon = ReferralUi.glyph(context, iconRes, 18, p.onPrimary);
            int iconSize = ReferralUi.dp(context, 18);
            slot.addView(mIcon, new FrameLayout.LayoutParams(iconSize, iconSize, Gravity.CENTER));
            mSpinner = spinner(context, p.onPrimary);
            mSpinner.setVisibility(INVISIBLE);
            int slotSize = ReferralUi.dp(context, 20);
            slot.addView(mSpinner, new FrameLayout.LayoutParams(slotSize, slotSize, Gravity.CENTER));
            line.addView(slot, new LinearLayout.LayoutParams(slotSize, slotSize));
            mLabel = ReferralUi.text(context, 16, ReferralUi.SEMIBOLD, p.onPrimary);
            mLabel.setGravity(Gravity.CENTER);
            mLabel.setTextAlignment(View.TEXT_ALIGNMENT_CENTER);
            LinearLayout.LayoutParams labelParams =
                    new LinearLayout.LayoutParams(ReferralUi.WRAP, ReferralUi.WRAP);
            labelParams.setMarginStart(ReferralUi.dp(context, 8));
            line.addView(mLabel, labelParams);
            addView(line, new FrameLayout.LayoutParams(ReferralUi.WRAP, ReferralUi.WRAP, Gravity.CENTER));

            setClickable(true);
            setFocusable(true);
            setOnClickListener(
                    v -> {
                        if (mAvailable && !mBusy) action.run();
                    });
            ReferralUi.pressFeedback(this);
            setLayoutParams(ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        }

        void setLabel(String label) {
            if (label.contentEquals(mLabel.getText())) return;
            mLabel.setText(label);
            setContentDescription(label);
        }

        /** Un envoi est en route : la roue à la place du pictogramme. */
        void setBusy(boolean busy) {
            mBusy = busy;
            mIcon.setVisibility(busy ? INVISIBLE : VISIBLE);
            mSpinner.setVisibility(busy ? VISIBLE : INVISIBLE);
            refresh();
        }

        /** Hors d'usage : rien à publier, ou ce qui doit partir n'est pas encore prêt. */
        void setAvailable(boolean available) {
            mAvailable = available;
            refresh();
        }

        private void refresh() {
            boolean enabled = mAvailable && !mBusy;
            if (enabled == isEnabled() && getAlpha() == (enabled ? 1f : 0.5f)) return;
            setEnabled(enabled);
            // Un enfoncement en cours ne doit pas rallumer un bouton qu'on vient d'éteindre.
            animate().cancel();
            setScaleX(1f);
            setScaleY(1f);
            setAlpha(enabled ? 1f : 0.5f);
        }

        /** La jauge part de zéro et se remplit en {@code durationMs}. */
        void startGauge(long durationMs) {
            mGaugeStart = SystemClock.uptimeMillis();
            mGaugeMs = Math.max(1, durationMs);
            invalidate();
        }

        /** Plus aucun passage annoncé : le bouton redevient un aplat. */
        void stopGauge() {
            if (mGaugeStart < 0) return;
            mGaugeStart = -1;
            invalidate();
        }

        @Override
        protected void onDraw(Canvas canvas) {
            float width = getWidth();
            float height = getHeight();
            mRect.set(0, 0, width, height);
            mPaint.setColor(mP.primary);
            canvas.drawRoundRect(mRect, mRadius, mRadius, mPaint);
            if (mGaugeStart >= 0) {
                float progress =
                        Math.min(1f, (SystemClock.uptimeMillis() - mGaugeStart) / (float) mGaugeMs);
                float veil = width * progress;
                int save = canvas.save();
                mClip.rewind();
                mClip.addRoundRect(mRect, mRadius, mRadius, Path.Direction.CW);
                canvas.clipPath(mClip);
                mPaint.setColor(ReferralUi.withAlpha(mP.onPrimary, 0.25f));
                // Dans le sens de lecture : depuis la droite en arabe.
                if (getLayoutDirection() == LAYOUT_DIRECTION_RTL) {
                    canvas.drawRect(width - veil, 0, width, height, mPaint);
                } else {
                    canvas.drawRect(0, 0, veil, height, mPaint);
                }
                canvas.restoreToCount(save);
                if (progress < 1f) postInvalidateOnAnimation();
            }
            super.onDraw(canvas);
        }
    }
}
