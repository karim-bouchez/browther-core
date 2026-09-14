/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_intro;

import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.MATCH;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.WRAP;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.dp;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.dpf;

import android.animation.ArgbEvaluator;
import android.animation.ValueAnimator;
import android.annotation.SuppressLint;
import android.content.Context;
import android.graphics.BlurMaskFilter;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_widgets.BrowtherBigToggleView;

/** Les briques communes aux écrans de l'introduction. */
final class BrowtherIntroWidgets {
    private BrowtherIntroWidgets() {}

    // -------------------- Boutons --------------------

    /** Un bouton qui s'enfonce sous le doigt, comme les styles de boutons iOS de l'introduction. */
    @SuppressLint("AppCompatCustomView")
    static final class Button extends TextView {
        enum Style {
            /** Aplat clair sur le fond sombre (« Continuer »). */
            PRIMARY,
            /** Bouton crème de l'accueil, sur la photo. */
            LIGHT,
            /** Texte seul (« Plus tard »). */
            GHOST,
            /** Contour (« Démarrer la navigation ») : ce sont les canaux l'action de l'écran. */
            OUTLINE
        }

        Button(Context context, int textId, Style style) {
            super(context);
            setText(textId);
            setGravity(Gravity.CENTER);
            setIncludeFontPadding(false);
            setTypeface(BrowtherIntroUi.typeface(BrowtherIntroUi.SEMIBOLD));
            setMaxLines(2);
            int horizontal = dp(context, 16);
            setPadding(horizontal, 0, horizontal, 0);
            switch (style) {
                case PRIMARY:
                    setTextSize(17);
                    setTextColor(BrowtherIntroUi.BACKGROUND);
                    setBackground(BrowtherIntroUi.rounded(BrowtherIntroUi.INK, dpf(context, 18)));
                    setMinHeight(dp(context, 52));
                    break;
                case LIGHT:
                    setTextSize(17);
                    setTextColor(BrowtherIntroUi.NIGHT);
                    setBackground(BrowtherIntroUi.rounded(BrowtherIntroUi.CREAM, dpf(context, 18)));
                    setMinHeight(dp(context, 52));
                    break;
                case GHOST:
                    setTextSize(17);
                    setTextColor(BrowtherIntroUi.INK_SOFT);
                    setMinHeight(dp(context, 44));
                    break;
                case OUTLINE:
                    setTextSize(16);
                    setTextColor(BrowtherIntroUi.INK_SOFT);
                    setBackground(
                            BrowtherIntroUi.rounded(
                                    Color.TRANSPARENT,
                                    dpf(context, 14),
                                    dp(context, 1.5f),
                                    BrowtherIntroUi.withAlpha(BrowtherIntroUi.INK_SOFT, 0.55f)));
                    setMinHeight(dp(context, 48));
                    break;
            }
            setClickable(true);
            setFocusable(true);
        }

        @Override
        public void setPressed(boolean pressed) {
            boolean changed = pressed != isPressed();
            super.setPressed(pressed);
            if (!changed) return;
            float scale = pressed ? 0.97f : 1f;
            animate().scaleX(scale).scaleY(scale).setDuration(120).start();
        }

        /** Éteint : grisé et inerte, la hauteur ne change pas. */
        void setActive(boolean active, boolean animated) {
            setEnabled(active);
            float alpha = active ? 1f : 0.35f;
            if (animated) {
                animate().alpha(alpha).setDuration(300).start();
            } else {
                setAlpha(alpha);
            }
        }
    }

    // -------------------- Pastille d'état --------------------

    /** « Déjà actif, sur tous les sites ». */
    static View pill(Context context, int textId) {
        LinearLayout pill = BrowtherIntroUi.row(context, 5);
        pill.setBackground(
                BrowtherIntroUi.capsule(BrowtherIntroUi.withAlpha(BrowtherIntroUi.HALAL, 0.13f)));
        pill.setPadding(dp(context, 10), dp(context, 5), dp(context, 10), dp(context, 5));
        pill.addView(
                BrowtherIntroUi.glyph(
                        context, R.drawable.browther_intro_glyph_check, 11, BrowtherIntroUi.HALAL));
        pill.addView(
                BrowtherIntroUi.text(
                        context, textId, 13, BrowtherIntroUi.SEMIBOLD, BrowtherIntroUi.HALAL));
        return pill;
    }

    // -------------------- Icône du moteur et son badge --------------------

    /**
     * L'icône du moteur avec <b>son badge</b>, à la géométrie de la barre d'outils.
     *
     * <p>Une seule géométrie pour les trois plateformes (référence macOS) : disque de <b>40 % de la
     * largeur de l'icône</b>, posé <b>entièrement à l'intérieur</b> du coin bas-fin de l'icône, cerné
     * de blanc sur 1 px, sans halo. ⛔ Ne pas se contenter de teinter l'icône : dans l'app, l'icône
     * ne change jamais de couleur, c'est le badge qui parle.
     *
     * <p>⚠️ <b>Toujours vert quand c'est allumé</b>, jamais ambre : l'ambre de la barre d'outils
     * veut dire « allumé, mais pas fini » ; ici rien n'est réellement allumé, l'interrupteur montre
     * un avant/après. C'est la feuille de l'accès anticipé qui dit le reste.
     */
    static final class BadgedIcon extends View {
        // Les couleurs du badge de la barre d'outils Android (sawtunaa_badge_*.xml).
        private static final int ON = 0xFF22C55E;
        private static final int OFF = 0xFFEF4444;

        private final Drawable mIcon;
        private final Paint mDot = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint mRing = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final int mSize;
        private int mColor = OFF;
        private boolean mOn;
        private ValueAnimator mAnimator;

        BadgedIcon(Context context, int iconId, float sizeDp) {
            super(context);
            mSize = dp(context, sizeDp);
            mIcon = context.getDrawable(iconId).mutate();
            mIcon.setTint(BrowtherIntroUi.INK);
            mRing.setStyle(Paint.Style.STROKE);
            mRing.setColor(Color.WHITE);
            mRing.setStrokeWidth(Math.max(1f, dpf(context, 1)));
            setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        }

        void setOn(boolean on, boolean animated) {
            if (on == mOn && (mAnimator == null || !animated)) return;
            mOn = on;
            int target = on ? ON : OFF;
            if (mAnimator != null) mAnimator.cancel();
            if (!animated) {
                mColor = target;
                invalidate();
                return;
            }
            mAnimator = ValueAnimator.ofObject(new ArgbEvaluator(), mColor, target);
            mAnimator.setDuration(250);
            mAnimator.addUpdateListener(
                    animation -> {
                        mColor = (int) animation.getAnimatedValue();
                        invalidate();
                    });
            mAnimator.start();
        }

        @Override
        protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
            setMeasuredDimension(mSize, mSize);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            // L'icône garde ses proportions dans le carré.
            int w = mIcon.getIntrinsicWidth();
            int h = mIcon.getIntrinsicHeight();
            float ratio = (w > 0 && h > 0) ? (float) w / h : 1f;
            int iconW = ratio >= 1f ? mSize : Math.round(mSize * ratio);
            int iconH = ratio >= 1f ? Math.round(mSize / ratio) : mSize;
            int left = (mSize - iconW) / 2;
            int top = (mSize - iconH) / 2;
            mIcon.setBounds(left, top, left + iconW, top + iconH);
            mIcon.draw(canvas);

            float diameter = mSize * 0.4f;
            float radius = diameter / 2f;
            boolean rtl = getLayoutDirection() == LAYOUT_DIRECTION_RTL;
            float cx = rtl ? radius : mSize - radius;
            float cy = mSize - radius;
            mDot.setColor(mColor);
            canvas.drawCircle(cx, cy, radius, mDot);
            float stroke = mRing.getStrokeWidth();
            canvas.drawCircle(cx, cy, radius - stroke / 2f, mRing);
        }
    }

    // -------------------- Rangée d'interrupteur --------------------

    /**
     * La commande des démonstrations : le <b>gros interrupteur des panneaux</b> ({@link
     * BrowtherBigToggleView}), pas un interrupteur système. C'est le geste que la personne refera
     * dans Browther, elle l'apprend ici.
     *
     * <p>De gauche à droite : l'icône du moteur avec son badge, le nom du moteur, son état en une
     * ligne, puis l'interrupteur. Hauteur fixe.
     */
    static final class SwitchRow extends LinearLayout {
        private final BadgedIcon mIcon;
        private final TextView mState;
        private final BrowtherBigToggleView mToggle;
        private final String mOffLabel;
        private final String mOnLabel;
        private boolean mOn;

        SwitchRow(
                Context context,
                int iconId,
                String title,
                int offLabelId,
                int onLabelId,
                Runnable onToggle) {
            super(context);
            setOrientation(HORIZONTAL);
            setGravity(Gravity.CENTER_VERTICAL);
            setPadding(dp(context, 16), 0, dp(context, 10), 0);
            setBackground(BrowtherIntroUi.rounded(BrowtherIntroUi.MATERIAL, dpf(context, 22)));
            mOffLabel = context.getString(offLabelId);
            mOnLabel = context.getString(onLabelId);

            mIcon = new BadgedIcon(context, iconId, 24);
            addView(mIcon);

            LinearLayout labels = BrowtherIntroUi.column(context);
            LayoutParams labelsParams = new LayoutParams(0, WRAP, 1f);
            labelsParams.setMarginStart(dp(context, 12));
            labelsParams.setMarginEnd(dp(context, 8));
            addView(labels, labelsParams);

            TextView name =
                    BrowtherIntroUi.text(context, 16, BrowtherIntroUi.SEMIBOLD, BrowtherIntroUi.INK);
            name.setText(title);
            BrowtherIntroUi.singleLine(name, 12, 16);
            labels.addView(name, new LayoutParams(MATCH, WRAP));

            // ⚠️ Une seule ligne, quoi qu'il arrive : « Désactivé · les pubs passent » se cassait
            // en deux et faisait sauter tout le bas de l'écran à chaque bascule.
            mState =
                    BrowtherIntroUi.text(
                            context, 13, BrowtherIntroUi.REGULAR, BrowtherIntroUi.INK_SOFT);
            mState.setText(mOffLabel);
            BrowtherIntroUi.singleLine(mState, 10, 13);
            LayoutParams stateParams = new LayoutParams(MATCH, dp(context, 17));
            stateParams.topMargin = dp(context, 3);
            labels.addView(mState, stateParams);

            mToggle = new BrowtherBigToggleView(context);
            mToggle.setContentDescription(title);
            mToggle.setOnCheckedChangeListener((view, checked) -> onToggle.run());
            addView(mToggle, new LayoutParams(dp(context, 96), dp(context, 52)));
        }

        void setOn(boolean on) {
            if (mToggle.isChecked() != on) mToggle.setCheckedSilently(on);
            if (mOn == on) return;
            mOn = on;
            mIcon.setOn(on, true);
            mState.setText(on ? mOnLabel : mOffLabel);
            mState.setTextColor(on ? BrowtherIntroUi.HALAL_TEXT : BrowtherIntroUi.INK_SOFT);
        }

        @Override
        protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
            super.onMeasure(
                    widthMeasureSpec,
                    MeasureSpec.makeMeasureSpec(dp(getContext(), 74), MeasureSpec.EXACTLY));
        }
    }

    // -------------------- Bouton d'avancement conditionné --------------------

    /**
     * Le bouton de bas d'écran, <b>éteint tant que l'interrupteur n'est pas sur ON</b>. L'écran
     * demande un geste ; le laisser franchir sans le faire, c'est laisser partir quelqu'un qui n'a
     * rien vu fonctionner.
     */
    static final class AdvanceButton extends LinearLayout {
        private final TextView mHint;
        private final Button mButton;
        private Boolean mEnabled;

        AdvanceButton(Context context, Runnable onClick) {
            super(context);
            setOrientation(VERTICAL);
            // ⚠️ Le conseil est AU-DESSUS et sa hauteur est réservée en permanence : rien ne doit
            // bouger entre ON et OFF, ni le bouton ni l'interrupteur.
            mHint =
                    BrowtherIntroUi.text(
                            context,
                            R.string.browther_intro_turn_on_to_continue,
                            13,
                            BrowtherIntroUi.REGULAR,
                            BrowtherIntroUi.INK_SOFT);
            mHint.setGravity(Gravity.CENTER);
            BrowtherIntroUi.singleLine(mHint, 10, 13);
            addView(mHint, new LayoutParams(MATCH, dp(context, 17)));

            mButton = new Button(context, R.string.browther_intro_continue, Button.Style.PRIMARY);
            mButton.setOnClickListener(v -> onClick.run());
            LayoutParams params = new LayoutParams(MATCH, WRAP);
            params.topMargin = dp(context, 6);
            addView(mButton, params);
        }

        void setActive(boolean active) {
            boolean animated = mEnabled != null;
            if (mEnabled != null && mEnabled == active) return;
            mEnabled = active;
            mButton.setActive(active, animated);
            float hintAlpha = active ? 0f : 1f;
            if (animated) {
                mHint.animate().alpha(hintAlpha).setDuration(300).start();
            } else {
                mHint.setAlpha(hintAlpha);
            }
        }
    }

    // -------------------- Point d'état (accueil) --------------------

    /** Le point vert ou ambre des trois protections. Le halo n'est pas décoratif : à 7 dp sur une
     * photo, un aplat mat se perd dans le fond. */
    static final class StatusDot extends View {
        private final Paint mCore = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint mHaloNear = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint mHaloFar = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final int mSize;
        private final int mBox;

        StatusDot(Context context, boolean soon) {
            super(context);
            int color = soon ? 0xFFF59E0B : 0xFF34C759;
            mSize = dp(context, 7);
            // Le halo déborde du point : la vue le contient, sa mise en page reste de 7 dp grâce
            // aux marges négatives posées par l'appelant.
            mBox = dp(context, 23);
            mCore.setColor(color);
            mHaloNear.setColor(BrowtherIntroUi.withAlpha(color, 0.9f));
            mHaloNear.setMaskFilter(new BlurMaskFilter(dpf(context, 4), BlurMaskFilter.Blur.NORMAL));
            mHaloFar.setColor(BrowtherIntroUi.withAlpha(color, 0.5f));
            mHaloFar.setMaskFilter(new BlurMaskFilter(dpf(context, 8), BlurMaskFilter.Blur.NORMAL));
            setLayerType(LAYER_TYPE_SOFTWARE, null);
            setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        }

        /** Marge négative à poser de chaque côté pour que la vue n'occupe que les 7 dp du point. */
        int overflow() {
            return (mBox - mSize) / 2;
        }

        @Override
        protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
            setMeasuredDimension(mBox, mBox);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            float c = mBox / 2f;
            float r = mSize / 2f;
            canvas.drawCircle(c, c, r, mHaloFar);
            canvas.drawCircle(c, c, r, mHaloNear);
            canvas.drawCircle(c, c, r, mCore);
        }
    }

    // -------------------- Signature --------------------

    /**
     * {@code SURFACES-COMMUNES.md} §6 en version <b>muette</b> : la pastille, mais ni flèche ni
     * geste — ouvrir devndin.com ferait sortir de l'introduction. La version tapable reste au pied
     * des Réglages. ⛔ Elle n'émet rien.
     */
    static View signature(Context context) {
        LinearLayout pill = BrowtherIntroUi.row(context, 6);
        pill.setPadding(dp(context, 14), dp(context, 7), dp(context, 14), dp(context, 7));
        pill.setBackground(
                BrowtherIntroUi.rounded(
                        BrowtherIntroUi.withAlpha(Color.WHITE, 0.07f),
                        10000f,
                        Math.max(1, dp(context, 1)),
                        BrowtherIntroUi.withAlpha(Color.WHITE, 0.16f)));
        TextView label =
                BrowtherIntroUi.text(
                        context,
                        R.string.browther_intro_signature_label,
                        13,
                        BrowtherIntroUi.REGULAR,
                        BrowtherIntroUi.withAlpha(Color.WHITE, 0.62f));
        pill.addView(label);
        ImageView logo = new ImageView(context);
        logo.setImageResource(R.drawable.browther_intro_devndin_logo);
        logo.setScaleType(ImageView.ScaleType.FIT_CENTER);
        pill.addView(logo, new LinearLayout.LayoutParams(dp(context, 33.5f), dp(context, 15)));
        pill.setFocusable(true);
        pill.setContentDescription(label.getText() + " dev&din");
        logo.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        label.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        return pill;
    }

    // -------------------- Tampons halal / haram --------------------

    /**
     * Le tampon « halal » ou « haram », repris du site (disque à 24 pointes, deux cercles, deux
     * étoiles, le mot arabe et le mot latin) : le contraste se lit sans lire. ⛔ Pas de texte en arc
     * comme sur le site : à cette taille il serait illisible.
     */
    static final class Stamp extends View {
        private final boolean mHalal;
        private final String mLatin;
        private final Paint mFill = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint mStroke = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint mText = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Path mShape = new Path();
        private final int mSize;

        Stamp(Context context, boolean halal, float sizeDp) {
            super(context);
            mHalal = halal;
            mSize = dp(context, sizeDp);
            mLatin =
                    context.getString(
                            halal
                                    ? R.string.browther_intro_stamp_halal
                                    : R.string.browther_intro_stamp_haram);
            mFill.setColor(halal ? BrowtherIntroUi.HALAL : BrowtherIntroUi.HARAM);
            mStroke.setStyle(Paint.Style.STROKE);
            mStroke.setColor(BrowtherIntroUi.withAlpha(Color.WHITE, 0.92f));
            mText.setColor(Color.WHITE);
            mText.setTextAlign(Paint.Align.CENTER);
            setElevation(dpf(context, 4));
            setOutlineProvider(
                    new android.view.ViewOutlineProvider() {
                        @Override
                        public void getOutline(View view, android.graphics.Outline outline) {
                            outline.setOval(0, 0, view.getWidth(), view.getHeight());
                        }
                    });
            setOutlineSpotShadowColor(BrowtherIntroUi.withAlpha(Color.BLACK, 0.5f));
            setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        }

        @Override
        protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
            setMeasuredDimension(mSize, mSize);
        }

        @Override
        protected void onSizeChanged(int w, int h, int oldw, int oldh) {
            mShape.reset();
            float cx = w / 2f;
            float cy = h / 2f;
            float outer = Math.min(w, h) / 2f;
            float inner = outer * 0.89f;
            int spikes = 24;
            for (int i = 0; i < spikes * 2; i++) {
                float radius = i % 2 == 0 ? outer : inner;
                double angle = i * Math.PI / spikes - Math.PI / 2;
                float x = cx + (float) Math.cos(angle) * radius;
                float y = cy + (float) Math.sin(angle) * radius;
                if (i == 0) {
                    mShape.moveTo(x, y);
                } else {
                    mShape.lineTo(x, y);
                }
            }
            mShape.close();
        }

        @Override
        protected void onDraw(Canvas canvas) {
            float s = mSize;
            float c = s / 2f;
            canvas.drawPath(mShape, mFill);
            // `strokeBorder` iOS : le trait est À L'INTÉRIEUR du cercle rogné.
            float outerWidth = s * 0.026f;
            mStroke.setStrokeWidth(outerWidth);
            canvas.drawCircle(c, c, c - s * 0.085f - outerWidth / 2f, mStroke);
            float innerWidth = s * 0.014f;
            mStroke.setStrokeWidth(innerWidth);
            canvas.drawCircle(c, c, c - s * 0.155f - innerWidth / 2f, mStroke);

            mText.setLetterSpacing(0f);
            mText.setTypeface(Typeface.create(Typeface.DEFAULT, BrowtherIntroUi.BOLD, false));
            mText.setTextSize(s * 0.28f);
            Paint.FontMetrics arabic = mText.getFontMetrics();
            mText.setTextSize(s * 0.12f);
            Paint.FontMetrics latin = mText.getFontMetrics();
            float arabicHeight = arabic.descent - arabic.ascent;
            float latinHeight = latin.descent - latin.ascent;
            float gap = s * 0.01f;
            float top = c - (arabicHeight + gap + latinHeight) / 2f;

            mText.setTextSize(s * 0.28f);
            mText.setAlpha(255);
            canvas.drawText(mHalal ? "حلال" : "حرام", c, top - arabic.ascent, mText);
            mText.setTypeface(Typeface.create(Typeface.DEFAULT, BrowtherIntroUi.HEAVY, false));
            mText.setTextSize(s * 0.12f);
            mText.setLetterSpacing(0.1f);
            canvas.drawText(mLatin, c, top + arabicHeight + gap - latin.ascent, mText);

            mText.setLetterSpacing(0f);
            mText.setTypeface(Typeface.DEFAULT);
            mText.setTextSize(s * 0.07f);
            mText.setAlpha(240);
            float starY = s * 0.16f - mText.getFontMetrics().ascent;
            canvas.drawText("★", s * 0.17f + s * 0.035f, starY, mText);
            canvas.drawText("★", s - s * 0.17f - s * 0.035f, starY, mText);
        }
    }

    /**
     * Les deux tampons superposés : le haram se décolle, le halal claque. Des animations
     * interruptibles : on peut basculer l'interrupteur deux fois par seconde sans que le tampon
     * reparte de zéro.
     */
    static final class StampPair extends FrameLayout {
        private final Stamp mHaram;
        private final Stamp mHalal;
        private Boolean mOn;

        StampPair(Context context) {
            super(context);
            setClipChildren(false);
            mHaram = new Stamp(context, false, 88);
            mHalal = new Stamp(context, true, 88);
            addView(mHaram, new LayoutParams(WRAP, WRAP, Gravity.CENTER));
            addView(mHalal, new LayoutParams(WRAP, WRAP, Gravity.CENTER));
        }

        void setOn(boolean on) {
            boolean animated = mOn != null;
            if (mOn != null && mOn == on) return;
            mOn = on;
            apply(mHaram, on ? -4 : -12, on ? 0.62f : 1f, on ? 0f : 0.95f, animated);
            apply(mHalal, on ? -12 : -34, on ? 1f : 1.9f, on ? 0.96f : 0f, animated);
        }

        private static void apply(
                View stamp, float rotation, float scale, float alpha, boolean animated) {
            if (!animated) {
                stamp.setRotation(rotation);
                stamp.setScaleX(scale);
                stamp.setScaleY(scale);
                stamp.setAlpha(alpha);
                return;
            }
            stamp.animate()
                    .rotation(rotation)
                    .scaleX(scale)
                    .scaleY(scale)
                    .alpha(alpha)
                    .setInterpolator(BrowtherIntroUi.SPRING)
                    .setDuration(420)
                    .start();
        }
    }
}
