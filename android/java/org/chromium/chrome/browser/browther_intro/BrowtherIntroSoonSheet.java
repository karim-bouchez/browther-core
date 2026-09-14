/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_intro;

import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.MATCH;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.WRAP;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.dp;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.dpf;

import android.annotation.SuppressLint;
import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.LayerDrawable;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.VelocityTracker;
import android.view.View;
import android.view.ViewConfiguration;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.chromium.chrome.R;

/**
 * Ce que répond « Continuer » sur Basarunaa et Sawtunaa pendant l'accès anticipé (ONBOARDING-SPEC.md
 * § 5).
 *
 * <p>⚠️ <b>Une vraie feuille</b>, pas un panneau posé en fondu : elle monte au ressort, la
 * <b>poignée glisse</b> et la referme (la feuille entière suit le doigt), et le fond s'assombrit
 * progressivement. ⛔ La version iOS refusée apparaissait d'un coup, avec une poignée décorative
 * qui ne répondait pas — on promettait un geste qui n'existait pas.
 */
final class BrowtherIntroSoonSheet extends FrameLayout {
    interface Delegate {
        /** « qu'Allah facilite » : ferme la feuille ET avance. */
        void onSoonContinue();

        /** Fermée par un geste (glisser, toucher le fond, retour). */
        void onSoonDismiss();
    }

    private static final float DIM = 0.55f;

    private final Delegate mDelegate;
    private final View mDim;
    private final LinearLayout mCard;
    private final int mTouchSlop;
    private boolean mClosing;
    private float mDownY;
    private boolean mDragging;
    private VelocityTracker mVelocity;

    BrowtherIntroSoonSheet(
            Context context, BrowtherIntroModel.Feature feature, int bottomInset, Delegate delegate) {
        super(context);
        mDelegate = delegate;
        mTouchSlop = ViewConfiguration.get(context).getScaledTouchSlop();
        boolean blur = feature == BrowtherIntroModel.Feature.BASARUNAA;

        mDim = new View(context);
        mDim.setBackgroundColor(Color.BLACK);
        mDim.setAlpha(0f);
        mDim.setOnClickListener(v -> dismiss());
        mDim.setContentDescription(context.getString(R.string.close));
        addView(mDim, new LayoutParams(MATCH, MATCH));

        mCard = BrowtherIntroUi.column(context);
        mCard.setClickable(true);
        int horizontal = dp(context, 22);
        mCard.setPadding(horizontal, 0, horizontal, dp(context, 14) + bottomInset);
        float radius = dpf(context, 28);
        GradientDrawable fill =
                BrowtherIntroUi.corners(BrowtherIntroUi.SURFACE, radius, radius, 0, 0);
        // Un liseré ambre : la feuille appartient à l'accès anticipé, comme le badge de la barre
        // d'outils. En haut seulement — elle n'a pas de bord en bas.
        GradientDrawable border =
                BrowtherIntroUi.corners(Color.TRANSPARENT, radius, radius, 0, 0);
        border.setStroke(
                Math.max(1, dp(context, 1)), BrowtherIntroUi.withAlpha(BrowtherIntroUi.AMBER, 0.35f));
        LayerDrawable background = new LayerDrawable(new android.graphics.drawable.Drawable[] {fill, border});
        background.setLayerInsetBottom(1, -dp(context, 4));
        mCard.setBackground(background);
        mCard.setElevation(dpf(context, 24));
        addView(mCard, new LayoutParams(MATCH, WRAP, Gravity.BOTTOM));

        // Poignée : la feuille entière se tire vers le bas (cf. onInterceptTouchEvent).
        View handle = new View(context);
        handle.setBackground(BrowtherIntroUi.capsule(BrowtherIntroUi.withAlpha(Color.WHITE, 0.28f)));
        LinearLayout.LayoutParams handleParams =
                new LinearLayout.LayoutParams(dp(context, 40), dp(context, 5));
        handleParams.gravity = Gravity.CENTER_HORIZONTAL;
        handleParams.topMargin = dp(context, 8);
        handleParams.bottomMargin = dp(context, 14);
        mCard.addView(handle, handleParams);

        LinearLayout header = BrowtherIntroUi.row(context, 10);
        ImageView icon =
                BrowtherIntroUi.glyph(
                        context,
                        blur ? R.drawable.basarunaa_icon_toolbar : R.drawable.sawtunaa_icon_toolbar,
                        22,
                        BrowtherIntroUi.AMBER);
        FrameLayout iconCircle = new FrameLayout(context);
        iconCircle.setBackground(
                BrowtherIntroUi.capsule(BrowtherIntroUi.withAlpha(BrowtherIntroUi.AMBER, 0.15f)));
        iconCircle.addView(
                icon, new LayoutParams(dp(context, 22), dp(context, 22), Gravity.CENTER));
        header.addView(iconCircle, new LinearLayout.LayoutParams(dp(context, 42), dp(context, 42)));
        LinearLayout titles = BrowtherIntroUi.column(context);
        TextView name =
                BrowtherIntroUi.text(context, 16, BrowtherIntroUi.SEMIBOLD, BrowtherIntroUi.INK);
        name.setText(blur ? "Basarunaa" : "Sawtunaa");
        titles.addView(name);
        TextView soon =
                BrowtherIntroUi.text(
                        context,
                        R.string.browther_intro_soon_title,
                        13,
                        BrowtherIntroUi.SEMIBOLD,
                        BrowtherIntroUi.AMBER);
        LinearLayout.LayoutParams soonParams = BrowtherIntroUi.linear(WRAP, WRAP);
        soonParams.topMargin = dp(context, 2);
        titles.addView(soon, soonParams);
        header.addView(titles, new LinearLayout.LayoutParams(0, WRAP, 1f));
        mCard.addView(header, BrowtherIntroUi.linear(MATCH, WRAP));

        // La fonctionnalité fonctionne déjà, elle est laissée désactivée le temps d'en peaufiner le
        // rendu. ⛔ Jamais « encore en développement » (c'est faux) ni « ton choix est
        // enregistré ».
        TextView body =
                BrowtherIntroUi.text(
                        context,
                        blur
                                ? R.string.browther_intro_soon_blur_body
                                : R.string.browther_intro_soon_music_body,
                        16,
                        BrowtherIntroUi.REGULAR,
                        BrowtherIntroUi.INK_SOFT);
        body.setLineSpacing(dpf(context, 3), 1f);
        mCard.addView(
                body, BrowtherIntroUi.marginTop(BrowtherIntroUi.linear(MATCH, WRAP), dp(context, 14)));

        TextView note =
                BrowtherIntroUi.text(
                        context,
                        R.string.browther_intro_soon_note,
                        13,
                        BrowtherIntroUi.REGULAR,
                        BrowtherIntroUi.INK_TERTIARY);
        mCard.addView(
                note, BrowtherIntroUi.marginTop(BrowtherIntroUi.linear(MATCH, WRAP), dp(context, 14)));

        // « qu'Allah facilite » — ⛔ « Allah », jamais « Dieu » ni « God ».
        BrowtherIntroWidgets.Button primary =
                new BrowtherIntroWidgets.Button(
                        context,
                        R.string.browther_intro_soon_primary_button,
                        BrowtherIntroWidgets.Button.Style.PRIMARY);
        primary.setOnClickListener(v -> close(mDelegate::onSoonContinue));
        mCard.addView(
                primary,
                BrowtherIntroUi.marginTop(BrowtherIntroUi.linear(MATCH, WRAP), dp(context, 16)));
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        mCard.setTranslationY(dp(getContext(), 700));
        mCard.post(
                () -> {
                    mCard.setTranslationY(mCard.getHeight() + dp(getContext(), 24));
                    mCard.animate()
                            .translationY(0)
                            .setInterpolator(BrowtherIntroUi.SPRING)
                            .setDuration(450)
                            .start();
                    mDim.animate().alpha(DIM).setDuration(350).start();
                });
    }

    void dismiss() {
        close(mDelegate::onSoonDismiss);
    }

    /**
     * La feuille redescend avant de rendre la main : sans ça, elle disparaît d'un coup et l'écran
     * suivant arrive par-dessus.
     */
    private void close(Runnable then) {
        if (mClosing) return;
        mClosing = true;
        mCard.animate()
                .translationY(mCard.getHeight() + dp(getContext(), 24))
                .setInterpolator(BrowtherIntroUi.EASE_OUT)
                .setDuration(250)
                .start();
        mDim.animate().alpha(0f).setDuration(250).start();
        postDelayed(then, 220);
    }

    // -------------------- Le geste --------------------

    @Override
    public boolean onInterceptTouchEvent(MotionEvent event) {
        if (mClosing) return true;
        if (!isInsideCard(event)) return false;
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                mDownY = event.getRawY();
                mDragging = false;
                trackVelocity(event, true);
                return false;
            case MotionEvent.ACTION_MOVE:
                trackVelocity(event, false);
                if (event.getRawY() - mDownY > mTouchSlop) {
                    mDragging = true;
                    return true;
                }
                return false;
            default:
                return false;
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    @Override
    public boolean onTouchEvent(MotionEvent event) {
        if (mClosing) return true;
        if (!mDragging) {
            if (event.getActionMasked() == MotionEvent.ACTION_DOWN && isInsideCard(event)) {
                mDownY = event.getRawY();
                trackVelocity(event, true);
                return true;
            }
            if (event.getActionMasked() == MotionEvent.ACTION_MOVE && mVelocity != null) {
                trackVelocity(event, false);
                if (event.getRawY() - mDownY > mTouchSlop) mDragging = true;
            }
            if (!mDragging) return super.onTouchEvent(event);
        }
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_MOVE:
                trackVelocity(event, false);
                mCard.setTranslationY(Math.max(0f, event.getRawY() - mDownY));
                float progress = mCard.getTranslationY() / Math.max(1, mCard.getHeight());
                mDim.setAlpha(DIM * (1f - Math.min(1f, progress)));
                return true;
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                trackVelocity(event, false);
                float velocity = 0;
                if (mVelocity != null) {
                    mVelocity.computeCurrentVelocity(1000);
                    velocity = mVelocity.getYVelocity();
                    mVelocity.recycle();
                    mVelocity = null;
                }
                mDragging = false;
                // Un tiers de la feuille, ou un geste franc : on referme.
                float moved = mCard.getTranslationY();
                if (moved > dp(getContext(), 110) || velocity > dp(getContext(), 900)) {
                    dismiss();
                } else {
                    mCard.animate()
                            .translationY(0)
                            .setInterpolator(BrowtherIntroUi.EASE_OUT)
                            .setDuration(300)
                            .start();
                    mDim.animate().alpha(DIM).setDuration(300).start();
                }
                return true;
            default:
                return true;
        }
    }

    private boolean isInsideCard(MotionEvent event) {
        return event.getY() >= mCard.getTop() + mCard.getTranslationY();
    }

    private void trackVelocity(MotionEvent event, boolean reset) {
        if (reset || mVelocity == null) {
            if (mVelocity != null) mVelocity.recycle();
            mVelocity = VelocityTracker.obtain();
        }
        // Coordonnées brutes : la feuille bouge sous le doigt pendant le geste.
        MotionEvent copy = MotionEvent.obtain(event);
        copy.setLocation(event.getRawX(), event.getRawY());
        mVelocity.addMovement(copy);
        copy.recycle();
    }
}
