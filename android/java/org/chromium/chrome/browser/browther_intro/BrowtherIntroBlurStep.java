/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_intro;

import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.MATCH;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.WRAP;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.dp;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.dpf;

import android.content.Context;
import android.graphics.Color;
import android.graphics.Outline;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewOutlineProvider;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.chromium.chrome.R;

/**
 * 3 · Floutage. Deux vignettes en 16:9 : <b>une vidéo</b> (le voile suit les personnes) et <b>une
 * photo</b> (le voile est propre) — elles ne prouvent pas la même chose.
 *
 * <p>Trois états (ONBOARDING-SPEC.md § 4.3) : éteint et jamais allumé = <b>rideau</b> (⛔ on ne
 * montre pas en clair ce que l'app existe pour cacher, à quelqu'un qui n'a rien demandé) ; allumé =
 * le voile ciblé ; éteint après avoir été allumé = les médias d'origine, c'est la personne qui
 * demande à comparer.
 *
 * <p>Ordre du bas d'écran : vignettes → choix → interrupteur → bouton. ⛔ Pas de « Plus tard » : il
 * mangeait la place des vignettes.
 */
final class BrowtherIntroBlurStep extends BrowtherIntroStepView {
    private final BrowtherIntroVideoTile mVideo;
    private final BrowtherIntroPhotoTile mPhoto;
    private final View mCurtain;
    private final Choice[] mChoices = new Choice[3];
    private final BrowtherIntroWidgets.SwitchRow mSwitch;
    private final BrowtherIntroWidgets.AdvanceButton mAdvance;
    private Boolean mCurtainShown;

    BrowtherIntroBlurStep(
            Context context,
            BrowtherIntroModel model,
            BrowtherIntroMedia.Track videoTrack,
            java.util.List<BrowtherIntroMedia.Person> photoPersons) {
        super(context, model);
        Slots slots =
                template(
                        null,
                        context.getString(R.string.browther_intro_blur_title),
                        context.getString(R.string.browther_intro_blur_subtitle),
                        null);

        mVideo = new BrowtherIntroVideoTile(context, videoTrack);
        mPhoto = new BrowtherIntroPhotoTile(context, photoPersons);
        Tiles tiles =
                new Tiles(
                        context,
                        tile(context, mVideo, R.drawable.browther_intro_glyph_play,
                                R.string.browther_intro_tile_video),
                        tile(context, mPhoto, R.drawable.browther_intro_glyph_photo,
                                R.string.browther_intro_tile_image));
        slots.mScene.addView(tiles, BrowtherIntroUi.frame(MATCH, MATCH, Gravity.CENTER));

        LinearLayout curtain = BrowtherIntroUi.column(context);
        curtain.setGravity(Gravity.CENTER_HORIZONTAL);
        curtain.setPadding(dp(context, 16), dp(context, 12), dp(context, 16), dp(context, 12));
        curtain.setBackground(
                BrowtherIntroUi.rounded(BrowtherIntroUi.withAlpha(Color.BLACK, 0.45f), 10000f));
        curtain.addView(
                BrowtherIntroUi.glyph(context, R.drawable.basarunaa_icon_toolbar, 26, Color.WHITE));
        TextView curtainText =
                BrowtherIntroUi.text(
                        context,
                        R.string.browther_intro_blur_curtain,
                        13,
                        BrowtherIntroUi.SEMIBOLD,
                        Color.WHITE);
        curtainText.setGravity(Gravity.CENTER);
        curtain.addView(
                curtainText,
                BrowtherIntroUi.marginTop(BrowtherIntroUi.linear(WRAP, WRAP), dp(context, 8)));
        mCurtain = curtain;
        slots.mScene.addView(curtain, BrowtherIntroUi.frame(WRAP, WRAP, Gravity.CENTER));

        LinearLayout choices = BrowtherIntroUi.row(context, 10);
        mChoices[0] =
                new Choice(context, BrowtherIntroModel.BlurTarget.WOMEN,
                        R.string.browther_intro_blur_women, R.drawable.browther_intro_glyph_woman,
                        BrowtherIntroUi.FEMININE);
        mChoices[1] =
                new Choice(context, BrowtherIntroModel.BlurTarget.MEN,
                        R.string.browther_intro_blur_men, R.drawable.browther_intro_glyph_man,
                        BrowtherIntroUi.MASCULINE);
        mChoices[2] =
                new Choice(context, BrowtherIntroModel.BlurTarget.BOTH,
                        R.string.browther_intro_blur_both, R.drawable.browther_intro_glyph_two_people,
                        BrowtherIntroUi.SAGE);
        for (Choice choice : mChoices) {
            choices.addView(choice, new LinearLayout.LayoutParams(0, dp(context, 74), 1f));
        }
        slots.mActions.addView(choices);

        mSwitch =
                new BrowtherIntroWidgets.SwitchRow(
                        context,
                        R.drawable.basarunaa_icon_toolbar,
                        "Basarunaa",
                        R.string.browther_intro_blur_switch_off,
                        R.string.browther_intro_blur_switch_on,
                        () -> mModel.toggleDemo(BrowtherIntroModel.Step.BLUR));
        slots.mActions.addView(mSwitch);

        mAdvance =
                new BrowtherIntroWidgets.AdvanceButton(
                        context, () -> mModel.activate(BrowtherIntroModel.Feature.BASARUNAA));
        slots.mActions.addView(mAdvance);
        bind(false);
    }

    @Override
    void bind(boolean animated) {
        BrowtherIntroMedia.Veil veil = BrowtherIntroMedia.Veil.of(mModel);
        mVideo.setVeil(veil);
        mPhoto.setVeil(veil);
        boolean curtain = !mModel.isBlurDemoOn() && !mModel.isBlurDemoEverOn();
        if (mCurtainShown == null || mCurtainShown != curtain) {
            boolean first = mCurtainShown == null;
            mCurtainShown = curtain;
            if (first) {
                mCurtain.setAlpha(curtain ? 1f : 0f);
            } else {
                mCurtain.animate().alpha(curtain ? 1f : 0f).setDuration(300).start();
            }
        }
        for (Choice choice : mChoices) {
            choice.setSelected(choice.mTarget == mModel.getBlurTarget(), animated);
        }
        mSwitch.setOn(mModel.isBlurDemoOn());
        mAdvance.setActive(mModel.isBlurDemoOn());
    }

    /** Une vignette : le média, arrondi, et son étiquette. */
    private static View tile(Context context, View media, int glyphId, int labelId) {
        FrameLayout frame = new FrameLayout(context);
        final float radius = dpf(context, 16);
        frame.setOutlineProvider(
                new ViewOutlineProvider() {
                    @Override
                    public void getOutline(View view, Outline outline) {
                        outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), radius);
                    }
                });
        frame.setClipToOutline(true);
        frame.setBackgroundColor(BrowtherIntroUi.SURFACE);
        frame.addView(media, new FrameLayout.LayoutParams(MATCH, MATCH));

        LinearLayout tag = BrowtherIntroUi.row(context, 5);
        tag.setPadding(dp(context, 9), dp(context, 5), dp(context, 9), dp(context, 5));
        tag.setBackground(
                BrowtherIntroUi.rounded(BrowtherIntroUi.withAlpha(Color.BLACK, 0.45f), 10000f));
        tag.addView(BrowtherIntroUi.glyph(context, glyphId, 10, Color.WHITE));
        tag.addView(
                BrowtherIntroUi.text(context, labelId, 11.5f, BrowtherIntroUi.SEMIBOLD, Color.WHITE));
        FrameLayout.LayoutParams tagParams =
                BrowtherIntroUi.frame(WRAP, WRAP, Gravity.TOP | Gravity.START);
        tagParams.setMargins(dp(context, 10), dp(context, 10), dp(context, 10), dp(context, 10));
        frame.addView(tag, tagParams);
        return frame;
    }

    /**
     * Les deux vignettes empilées, en 16:9, aussi grandes que la place le permet — plus étroites
     * que l'écran si la hauteur manque.
     */
    private static final class Tiles extends ViewGroup {
        private final View mTop;
        private final View mBottom;
        private final int mGap;

        Tiles(Context context, View top, View bottom) {
            super(context);
            mTop = top;
            mBottom = bottom;
            mGap = dp(context, 10);
            addView(top);
            addView(bottom);
        }

        @Override
        protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
            int width = MeasureSpec.getSize(widthMeasureSpec);
            int height = MeasureSpec.getSize(heightMeasureSpec);
            int tileWidth = Math.min(width, Math.round((height - mGap) / 2f * 16f / 9f));
            tileWidth = Math.max(0, tileWidth);
            int tileHeight = Math.round(tileWidth * 9f / 16f);
            int exactWidth = MeasureSpec.makeMeasureSpec(tileWidth, MeasureSpec.EXACTLY);
            int exactHeight = MeasureSpec.makeMeasureSpec(tileHeight, MeasureSpec.EXACTLY);
            mTop.measure(exactWidth, exactHeight);
            mBottom.measure(exactWidth, exactHeight);
            setMeasuredDimension(width, height);
        }

        @Override
        protected void onLayout(boolean changed, int l, int t, int r, int b) {
            int width = r - l;
            int height = b - t;
            int tileWidth = mTop.getMeasuredWidth();
            int tileHeight = mTop.getMeasuredHeight();
            int left = (width - tileWidth) / 2;
            int top = (height - (tileHeight * 2 + mGap)) / 2;
            mTop.layout(left, top, left + tileWidth, top + tileHeight);
            int second = top + tileHeight + mGap;
            mBottom.layout(left, second, left + tileWidth, second + tileHeight);
        }
    }

    /**
     * Une case du choix. Chaque cible a <b>sa teinte</b> quand elle est sélectionnée — rose, bleu,
     * sauge — pour que le choix se lise avant d'être lu. ⛔ Pas un troisième cadre vert.
     */
    private final class Choice extends FrameLayout {
        final BrowtherIntroModel.BlurTarget mTarget;
        private final int mTint;
        private final ImageView mIcon;
        private final TextView mLabel;
        private final View mCheck;
        private Boolean mIsSelected;

        Choice(Context context, BrowtherIntroModel.BlurTarget target, int labelId, int glyphId,
                int tint) {
            super(context);
            mTarget = target;
            mTint = tint;
            setClickable(true);
            setFocusable(true);
            setOnClickListener(v -> mModel.choose(mTarget));

            LinearLayout column = BrowtherIntroUi.column(context);
            column.setGravity(Gravity.CENTER);
            mIcon = BrowtherIntroUi.glyph(context, glyphId, 21, BrowtherIntroUi.INK_SOFT);
            column.addView(mIcon);
            mLabel =
                    BrowtherIntroUi.text(
                            context, labelId, 13.5f, BrowtherIntroUi.SEMIBOLD,
                            BrowtherIntroUi.INK_SOFT);
            mLabel.setGravity(Gravity.CENTER);
            BrowtherIntroUi.singleLine(mLabel, 10, 13.5f);
            column.addView(
                    mLabel,
                    BrowtherIntroUi.marginTop(BrowtherIntroUi.linear(MATCH, WRAP), dp(context, 7)));
            LayoutParams columnParams = new LayoutParams(MATCH, WRAP, Gravity.CENTER);
            columnParams.leftMargin = dp(context, 6);
            columnParams.rightMargin = dp(context, 6);
            addView(column, columnParams);

            FrameLayout check = new FrameLayout(context);
            check.setBackground(BrowtherIntroUi.capsule(tint));
            check.addView(
                    BrowtherIntroUi.glyph(
                            context, R.drawable.browther_intro_glyph_check, 11,
                            BrowtherIntroUi.BACKGROUND),
                    new LayoutParams(dp(context, 11), dp(context, 11), Gravity.CENTER));
            LayoutParams checkParams =
                    new LayoutParams(dp(context, 20), dp(context, 20), Gravity.TOP | Gravity.END);
            checkParams.setMargins(dp(context, 7), dp(context, 7), dp(context, 7), dp(context, 7));
            mCheck = check;
            addView(check, checkParams);
            setContentDescription(mLabel.getText());
        }

        void setSelected(boolean selected, boolean animated) {
            if (mIsSelected != null && mIsSelected == selected) return;
            mIsSelected = selected;
            super.setSelected(selected);
            Context context = getContext();
            int color = selected ? mTint : BrowtherIntroUi.INK_SOFT;
            mIcon.setImageTintList(android.content.res.ColorStateList.valueOf(color));
            mLabel.setTextColor(color);
            setBackground(
                    BrowtherIntroUi.rounded(
                            selected ? BrowtherIntroUi.withAlpha(mTint, 0.16f) : BrowtherIntroUi.SURFACE,
                            dpf(context, 18),
                            selected ? dp(context, 2) : Math.max(1, dp(context, 1)),
                            selected ? mTint : BrowtherIntroUi.withAlpha(Color.WHITE, 0.08f)));
            float scale = selected ? 1f : 0.4f;
            float alpha = selected ? 1f : 0f;
            if (animated) {
                mCheck.animate()
                        .scaleX(scale)
                        .scaleY(scale)
                        .alpha(alpha)
                        .setInterpolator(BrowtherIntroUi.SPRING)
                        .setDuration(280)
                        .start();
            } else {
                mCheck.setScaleX(scale);
                mCheck.setScaleY(scale);
                mCheck.setAlpha(alpha);
            }
        }
    }
}
