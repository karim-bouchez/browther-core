/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_intro;

import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.MATCH;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.dp;

import android.content.Context;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Insets;
import android.os.Build;
import android.view.ContextThemeWrapper;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.view.WindowInsets;
import android.widget.FrameLayout;
import android.widget.LinearLayout;

import org.chromium.chrome.R;

import java.util.List;

/**
 * L'introduction Browther : six écrans qui montrent ce que fait le navigateur et laissent la
 * personne régler ce qui la concerne. Portage Android de {@code BrowtherIntroView.swift}.
 *
 * <p>Plein écran, portrait, et <b>impossible à écarter d'un geste</b> : le retour recule d'un
 * écran, jamais au-delà du premier. Sortir se fait par le bouton de la dernière étape.
 */
final class BrowtherIntroView extends FrameLayout implements BrowtherIntroModel.Listener {
    private static final long TRANSITION_MS = 380;

    private final BrowtherIntroModel mModel;
    private final BrowtherIntroAudio mAudio;
    private final BrowtherIntroMedia.Track mVideoTrack;
    private final List<BrowtherIntroMedia.Person> mPhotoPersons;
    private final FrameLayout mStage;
    private final View mBack;
    private final LinearLayout mProgress;
    private final LinearLayout mHeader;
    private final BrowtherIntroConfetti mConfetti;
    private BrowtherIntroStepView mCurrent;
    private BrowtherIntroSoonSheet mSheet;
    private int mTopInset;
    private int mBottomInset;

    /**
     * ⚠️ L'introduction est <b>toujours sombre</b>, quel que soit le thème de l'appareil (décision
     * 2026-09-12, ONBOARDING-SPEC.md § 3.1). Le thème est imposé au <b>contexte</b> de l'écran —
     * l'équivalent Android de {@code overrideUserInterfaceStyle = .dark} sur iOS : il couvre aussi
     * les commandes système hébergées (curseur du volume). ⛔ Jamais en forçant des couleurs une par
     * une, ni de thème clair.
     */
    static Context darkContext(Context base) {
        Configuration configuration = new Configuration(base.getResources().getConfiguration());
        configuration.uiMode =
                (configuration.uiMode & ~Configuration.UI_MODE_NIGHT_MASK)
                        | Configuration.UI_MODE_NIGHT_YES;
        return new ContextThemeWrapper(
                base.createConfigurationContext(configuration),
                android.R.style.Theme_DeviceDefault_NoActionBar);
    }

    @SuppressWarnings("deprecation") // Encarts système avant Android 11.
    BrowtherIntroView(Context context, BrowtherIntroModel model) {
        super(context);
        mModel = model;
        setBackgroundColor(BrowtherIntroUi.BACKGROUND);
        setClipChildren(false);

        // Les médias sont lus et l'extrait décodé dès l'arrivée, hors du fil principal pour le
        // son : le premier geste de l'écran Musique ne doit rien avoir à préparer.
        mAudio = new BrowtherIntroAudio(context);
        mAudio.prepare();
        mVideoTrack = BrowtherIntroMedia.loadVideoTrack(context);
        mPhotoPersons = BrowtherIntroMedia.loadPhotoPersons(context);

        mStage = new FrameLayout(context);
        mStage.setClipChildren(false);
        addView(mStage, new LayoutParams(MATCH, MATCH));

        // Barre du haut : retour et progression.
        mHeader = BrowtherIntroUi.row(context, 6);
        mHeader.setPadding(dp(context, 10), 0, dp(context, 20), 0);
        FrameLayout back = new FrameLayout(context);
        back.addView(
                BrowtherIntroUi.glyph(
                        context, R.drawable.browther_intro_glyph_chevron_left, 20, Color.WHITE),
                new LayoutParams(dp(context, 20), dp(context, 20), Gravity.CENTER));
        back.setClickable(true);
        back.setFocusable(true);
        back.setContentDescription(context.getString(R.string.back));
        back.setOnClickListener(v -> mModel.back());
        mBack = back;
        mHeader.addView(back, new LinearLayout.LayoutParams(dp(context, 44), dp(context, 44)));
        mProgress = BrowtherIntroUi.row(context, 5);
        mProgress.setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
        for (int i = 0; i < model.getSteps().size(); i++) {
            View capsule = new View(context);
            capsule.setBackground(BrowtherIntroUi.capsule(Color.WHITE));
            mProgress.addView(capsule, new LinearLayout.LayoutParams(0, dp(context, 3), 1f));
        }
        mHeader.addView(mProgress, new LinearLayout.LayoutParams(0, dp(context, 3), 1f));
        addView(mHeader, new LayoutParams(MATCH, dp(context, 44), Gravity.TOP));

        mConfetti = new BrowtherIntroConfetti(context);
        addView(mConfetti, new LayoutParams(MATCH, MATCH));

        setOnApplyWindowInsetsListener(
                (view, insets) -> {
                    int top;
                    int bottom;
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        Insets bars = insets.getInsets(WindowInsets.Type.systemBars());
                        top = bars.top;
                        bottom = bars.bottom;
                    } else {
                        top = insets.getSystemWindowInsetTop();
                        bottom = insets.getSystemWindowInsetBottom();
                    }
                    applyInsets(top, bottom);
                    return insets;
                });

        model.addListener(this);
        show(model.getStep(), 0);
        updateHeader(false);
    }

    private void applyInsets(int top, int bottom) {
        mTopInset = top;
        mBottomInset = bottom;
        LayoutParams params = (LayoutParams) mHeader.getLayoutParams();
        params.topMargin = top;
        mHeader.setLayoutParams(params);
        for (int i = 0; i < mStage.getChildCount(); i++) {
            ((BrowtherIntroStepView) mStage.getChildAt(i)).setInsets(top, bottom);
        }
    }

    // -------------------- Écrans --------------------

    private BrowtherIntroStepView create(BrowtherIntroModel.Step step) {
        Context context = getContext();
        switch (step) {
            case WELCOME:
                return new BrowtherIntroWelcomeStep(context, mModel);
            case ADS:
                return new BrowtherIntroAdsStep(context, mModel);
            case BLUR:
                return new BrowtherIntroBlurStep(context, mModel, mVideoTrack, mPhotoPersons);
            case MUSIC:
                return new BrowtherIntroMusicStep(context, mModel, mAudio);
            case DEFAULT_BROWSER:
                return new BrowtherIntroDefaultStep(context, mModel);
            case CHANNELS:
            default:
                return new BrowtherIntroChannelsStep(context, mModel);
        }
    }

    /**
     * Les écrans entrent par la fin et sortent par le début : le parcours a un sens, et le retour le
     * rembobine. En arabe et en hébreu, le sens s'inverse.
     */
    @SuppressWarnings("deprecation") // announceForAccessibility : pas d'équivalent pour un écran.
    private void show(BrowtherIntroModel.Step step, int direction) {
        BrowtherIntroStepView previous = mCurrent;
        BrowtherIntroStepView next = create(step);
        next.setInsets(mTopInset, mBottomInset);
        mStage.addView(next, new LayoutParams(MATCH, MATCH));
        mCurrent = next;

        if (previous == null || direction == 0) {
            if (previous != null) {
                previous.onDeactivated();
                mStage.removeView(previous);
            }
            next.post(next::onActivated);
            return;
        }
        previous.onDeactivated();
        float width = getWidth() > 0 ? getWidth() : getResources().getDisplayMetrics().widthPixels;
        float sign = BrowtherIntroUi.isRtl(this) ? -1f : 1f;
        next.setTranslationX(sign * direction * width);
        next.animate()
                .translationX(0)
                .setDuration(TRANSITION_MS)
                .setInterpolator(BrowtherIntroUi.EASE_OUT)
                .withEndAction(next::onActivated)
                .start();
        previous.animate()
                .translationX(-sign * direction * width)
                .setDuration(TRANSITION_MS)
                .setInterpolator(BrowtherIntroUi.EASE_OUT)
                .withEndAction(() -> mStage.removeView(previous))
                .start();
        CharSequence title = next.accessibilityTitle();
        if (title != null) announceForAccessibility(title);
    }

    private void updateHeader(boolean animated) {
        int index = mModel.getIndex();
        boolean first = index == 0;
        mBack.setEnabled(!first);
        mBack.setImportantForAccessibility(
                first ? IMPORTANT_FOR_ACCESSIBILITY_NO : IMPORTANT_FOR_ACCESSIBILITY_YES);
        float backAlpha = first ? 0f : 1f;
        if (animated) {
            mBack.animate().alpha(backAlpha).setDuration(250).start();
        } else {
            mBack.setAlpha(backAlpha);
        }
        for (int i = 0; i < mProgress.getChildCount(); i++) {
            View capsule = mProgress.getChildAt(i);
            float alpha = i <= index ? 0.85f : 0.18f;
            if (animated) {
                capsule.animate().alpha(alpha).setDuration(400).start();
            } else {
                capsule.setAlpha(alpha);
            }
        }
    }

    // -------------------- Modèle --------------------

    @Override
    public void onStepChanged(BrowtherIntroModel.Step previous, int direction) {
        closeSheetImmediately();
        show(mModel.getStep(), direction);
        updateHeader(true);
    }

    @Override
    public void onStateChanged() {
        if (mCurrent != null) mCurrent.bind(true);
        BrowtherIntroModel.Feature soon = mModel.getSoonFeature();
        if (soon != null && mSheet == null) {
            mSheet =
                    new BrowtherIntroSoonSheet(
                            getContext(),
                            soon,
                            mBottomInset,
                            new BrowtherIntroSoonSheet.Delegate() {
                                @Override
                                public void onSoonContinue() {
                                    removeSheet();
                                    mModel.dismissSoonSheet(true);
                                }

                                @Override
                                public void onSoonDismiss() {
                                    removeSheet();
                                    mModel.dismissSoonSheet(false);
                                }
                            });
            addView(mSheet, new LayoutParams(MATCH, MATCH));
        }
    }

    private void removeSheet() {
        if (mSheet == null) return;
        removeView(mSheet);
        mSheet = null;
    }

    private void closeSheetImmediately() {
        removeSheet();
    }

    @Override
    public void onCelebrate() {
        // Par-dessus tout l'écran, jamais dans la vignette qui l'a déclenché.
        mConfetti.bringToFront();
        mConfetti.fire();
    }

    @Override
    public void onHaptic(BrowtherIntroModel.Haptic haptic) {
        int constant;
        switch (haptic) {
            case LIGHT:
                constant = HapticFeedbackConstants.CLOCK_TICK;
                break;
            case SELECTION:
                constant =
                        Build.VERSION.SDK_INT >= 34
                                ? HapticFeedbackConstants.SEGMENT_TICK
                                : HapticFeedbackConstants.CLOCK_TICK;
                break;
            case SUCCESS:
                constant =
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
                                ? HapticFeedbackConstants.CONFIRM
                                : HapticFeedbackConstants.VIRTUAL_KEY;
                break;
            case MEDIUM:
            default:
                constant = HapticFeedbackConstants.VIRTUAL_KEY;
                break;
        }
        performHapticFeedback(constant);
    }

    // -------------------- Hôte --------------------

    /** Le bouton retour du système : la feuille d'abord, puis l'écran précédent. */
    void handleBack() {
        if (mSheet != null) {
            mSheet.dismiss();
            return;
        }
        mModel.back();
    }

    /** Fin de l'introduction : on libère le son et la vidéo. */
    void release() {
        if (mCurrent != null) mCurrent.onDeactivated();
        mAudio.release();
    }
}
