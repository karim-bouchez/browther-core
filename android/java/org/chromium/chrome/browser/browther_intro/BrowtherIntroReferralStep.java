/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_intro;

import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.MATCH;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.WRAP;

import android.content.Context;
import android.view.Gravity;
import android.view.View;
import android.view.inputmethod.InputMethodManager;
import android.widget.FrameLayout;
import android.widget.TextView;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_referral.BrowtherReferralController;
import org.chromium.chrome.browser.browther_referral.ReferralCodeEntry;
import org.chromium.chrome.browser.browther_referral.ReferralStrings;

/**
 * O · Le code d'un proche — l'écran du parrainage dans l'introduction (private/docs/PARRAINAGE.md
 * § 1), pendant de {@code BrowtherIntroReferralStep.swift}, juste après « navigateur par défaut ».
 *
 * <p><b>Le code SEUL</b> (§ 12.24 du doc commun) — ⛔ ni l'accroche « Débloquer… », ni « Tu veux
 * en parler autour de toi ? » : la personne ne connaît pas encore Browther. Ce qui a sa place ici,
 * c'est ce qu'elle ne pourra plus faire aussi simplement plus tard : saisir le code du proche qui
 * l'a amenée. ⭐ Une réussite se fête (confettis, une fois). « Continuer » / « Plus tard ».
 */
final class BrowtherIntroReferralStep extends BrowtherIntroStepView {
    private final BrowtherIntroWidgets.Button mLater;
    private final FrameLayout mScene;
    private boolean mRedeemed;

    BrowtherIntroReferralStep(Context context, BrowtherIntroModel model) {
        super(context, model);
        Slots slots =
                template(
                        null,
                        ReferralStrings.get(context, "redeem.head"),
                        ReferralStrings.get(context, "redeem.body"),
                        null);
        mScene = slots.mScene;

        BrowtherIntroWidgets.Button advance =
                new BrowtherIntroWidgets.Button(
                        context,
                        R.string.browther_intro_continue,
                        BrowtherIntroWidgets.Button.Style.PRIMARY);
        advance.setOnClickListener(
                v -> {
                    hideKeyboard();
                    mModel.advance();
                });
        slots.mActions.addView(advance);
        mLater =
                new BrowtherIntroWidgets.Button(
                        context,
                        R.string.browther_referral_welcome_later,
                        BrowtherIntroWidgets.Button.Style.GHOST);
        mLater.setOnClickListener(
                v -> {
                    hideKeyboard();
                    mModel.referralLater();
                });
        slots.mActions.addView(mLater);
        bind(false);
    }

    @Override
    void bind(boolean animated) {
        mScene.removeAllViews();
        boolean already =
                mRedeemed
                        || (BrowtherReferralController.get().known() != null
                                && BrowtherReferralController.get().known().referredBy != null);
        if (already) {
            // Un code déjà accepté : ⛔ pas de second champ, la phrase qui dit ce qu'il a donné.
            TextView done =
                    BrowtherIntroUi.text(context(), 16, BrowtherIntroUi.MEDIUM, BrowtherIntroUi.HALAL_TEXT);
            done.setText(ReferralStrings.get(context(), "redeem.validatedLine"));
            done.setGravity(Gravity.CENTER);
            mScene.addView(done, BrowtherIntroUi.frame(MATCH, WRAP, Gravity.CENTER));
            mLater.setVisibility(View.GONE);
            return;
        }
        View entry =
                new ReferralCodeEntry(
                        context(),
                        "onboarding",
                        false,
                        () -> {
                            mRedeemed = true;
                            mModel.celebrateReferralCode();
                            bind(true);
                        });
        mScene.addView(entry, BrowtherIntroUi.frame(MATCH, WRAP, Gravity.CENTER));
    }

    @Override
    void onActivated() {
        // ⛔ L'écran O ne revient jamais une fois vu (§ 3).
        BrowtherReferralController.get().markWelcomeSeen();
    }

    private Context context() {
        return getContext();
    }

    private void hideKeyboard() {
        InputMethodManager keyboard = getContext().getSystemService(InputMethodManager.class);
        if (keyboard != null) keyboard.hideSoftInputFromWindow(getWindowToken(), 0);
    }
}
