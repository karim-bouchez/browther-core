/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_intro;

import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.MATCH;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.WRAP;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.dp;

import android.content.Context;
import android.view.Gravity;
import android.widget.FrameLayout;

import org.chromium.chrome.R;

/**
 * 2 · Pubs. Le premier des trois écrans qui <b>demandent un geste</b> : l'interrupteur doit passer
 * sur ON pour que le bouton s'allume. ⚠️ Conséquence assumée : cet écran n'a aucune sortie sans
 * activer (ONBOARDING-SPEC.md § 3.2).
 */
final class BrowtherIntroAdsStep extends BrowtherIntroStepView {
    private final BrowtherIntroWebPage mPage;
    private final BrowtherIntroWidgets.StampPair mStamps;
    private final BrowtherIntroWidgets.SwitchRow mSwitch;
    private final BrowtherIntroWidgets.AdvanceButton mAdvance;

    BrowtherIntroAdsStep(Context context, BrowtherIntroModel model) {
        super(context, model);
        Slots slots =
                template(
                        BrowtherIntroWidgets.pill(context, R.string.browther_intro_ads_pill),
                        context.getString(R.string.browther_intro_ads_title),
                        context.getString(R.string.browther_intro_ads_subtitle),
                        null);

        mPage = new BrowtherIntroWebPage(context);
        FrameLayout.LayoutParams pageParams = BrowtherIntroUi.frame(MATCH, MATCH, Gravity.TOP);
        pageParams.bottomMargin = dp(context, 34);
        slots.mScene.addView(mPage, pageParams);

        mStamps = new BrowtherIntroWidgets.StampPair(context);
        FrameLayout.LayoutParams stampParams =
                BrowtherIntroUi.frame(WRAP, WRAP, Gravity.TOP | Gravity.END);
        slots.mScene.addView(mStamps, stampParams);
        offsetStamps(mStamps);

        // ⛔ Aucun nom de service tiers : c'est la pub avant la vidéo qui fait reconnaître la scène.
        mSwitch =
                new BrowtherIntroWidgets.SwitchRow(
                        context,
                        R.drawable.shield_icon_toolbar,
                        context.getString(R.string.browther_intro_shields_name),
                        R.string.browther_intro_ads_switch_off,
                        R.string.browther_intro_ads_switch_on,
                        () -> mModel.toggleDemo(BrowtherIntroModel.Step.ADS));
        slots.mScene.addView(mSwitch, BrowtherIntroUi.frame(MATCH, WRAP, Gravity.BOTTOM));

        mAdvance = new BrowtherIntroWidgets.AdvanceButton(context, mModel::advance);
        slots.mActions.addView(mAdvance);
        bind(false);
    }

    /** Le tampon déborde du coin haut-fin de la scène, comme sur l'iOS. */
    static void offsetStamps(BrowtherIntroWidgets.StampPair stamps) {
        stamps.post(
                () -> {
                    int x = dp(stamps.getContext(), 10);
                    stamps.setTranslationX(BrowtherIntroUi.isRtl(stamps) ? -x : x);
                    stamps.setTranslationY(-dp(stamps.getContext(), 14));
                });
    }

    @Override
    void bind(boolean animated) {
        boolean on = mModel.isAdsDemoOn();
        mPage.setBlocked(on);
        mStamps.setOn(on);
        mSwitch.setOn(on);
        mAdvance.setActive(on);
    }
}
