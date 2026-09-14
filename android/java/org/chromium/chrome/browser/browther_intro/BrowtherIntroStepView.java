/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_intro;

import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.MATCH;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.WRAP;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.dp;

import android.content.Context;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * Un écran de l'introduction. Cinq des six partagent le même gabarit — titre, sous-titre, scène,
 * commandes ({@link #template}) ; l'accueil a le sien, pleine image.
 */
abstract class BrowtherIntroStepView extends FrameLayout {
    protected final BrowtherIntroModel mModel;
    private LinearLayout mColumn;
    private TextView mTitle;
    private int mTopInset;
    private int mBottomInset;

    BrowtherIntroStepView(Context context, BrowtherIntroModel model) {
        super(context);
        mModel = model;
        setClipChildren(false);
    }

    /** Relit l'état du modèle ; {@code animated} faux au premier affichage. */
    abstract void bind(boolean animated);

    /** L'écran est devenu l'écran courant (fin de la transition d'entrée). */
    void onActivated() {}

    /** L'écran s'en va : tout ce qui joue doit se taire. */
    void onDeactivated() {}

    /** Ce qui est annoncé par le lecteur d'écran à l'arrivée. */
    CharSequence accessibilityTitle() {
        return mTitle == null ? null : mTitle.getText();
    }

    /** Barres système : le contenu se pose entre elles. */
    void setInsets(int top, int bottom) {
        mTopInset = top;
        mBottomInset = bottom;
        applyInsets(top, bottom);
    }

    protected void applyInsets(int top, int bottom) {
        if (mColumn == null) return;
        // La barre du haut (retour + progression) occupe 44 dp sous la barre d'état.
        mColumn.setPadding(0, top + dp(getContext(), 52), 0, bottom + dp(getContext(), 8));
    }

    /** Les deux conteneurs du gabarit, remplis par chaque écran. */
    static final class Slots {
        final FrameLayout mScene;
        final LinearLayout mActions;

        Slots(FrameLayout scene, LinearLayout actions) {
            mScene = scene;
            mActions = actions;
        }
    }

    /**
     * Titre, sous-titre, scène, boutons : la structure que partagent cinq des six écrans.
     *
     * @param pill pastille au-dessus du titre, ou {@code null}.
     * @param footnote ligne sous le sous-titre, ou {@code null}.
     */
    protected Slots template(View pill, CharSequence title, CharSequence subtitle, View footnote) {
        Context context = getContext();
        mColumn = BrowtherIntroUi.column(context);
        mColumn.setClipChildren(false);
        mColumn.setClipToPadding(false);
        addView(mColumn, new LayoutParams(MATCH, MATCH));

        LinearLayout header = BrowtherIntroUi.column(context);
        int gutter = dp(context, 20);
        header.setPadding(gutter, dp(context, 8), gutter, 0);
        if (pill != null) {
            LinearLayout.LayoutParams pillParams = BrowtherIntroUi.linear(WRAP, WRAP);
            pillParams.bottomMargin = dp(context, 9);
            header.addView(pill, pillParams);
        }
        mTitle = BrowtherIntroUi.text(context, 28, BrowtherIntroUi.SEMIBOLD, BrowtherIntroUi.INK);
        mTitle.setText(title);
        mTitle.setLineSpacing(0f, 1.05f);
        mTitle.setAccessibilityHeading(true);
        header.addView(mTitle, BrowtherIntroUi.linear(MATCH, WRAP));
        TextView subtitleView =
                BrowtherIntroUi.text(context, 17, BrowtherIntroUi.REGULAR, BrowtherIntroUi.INK_SOFT);
        subtitleView.setText(subtitle);
        subtitleView.setLineSpacing(dp(context, 2), 1f);
        header.addView(
                subtitleView,
                BrowtherIntroUi.marginTop(BrowtherIntroUi.linear(MATCH, WRAP), dp(context, 9)));
        if (footnote != null) {
            header.addView(
                    footnote,
                    BrowtherIntroUi.marginTop(BrowtherIntroUi.linear(MATCH, WRAP), dp(context, 9)));
        }
        mColumn.addView(header, BrowtherIntroUi.linear(MATCH, WRAP));

        FrameLayout scene = new FrameLayout(context);
        scene.setClipChildren(false);
        LinearLayout.LayoutParams sceneParams = new LinearLayout.LayoutParams(MATCH, 0, 1f);
        sceneParams.topMargin = dp(context, 18);
        sceneParams.leftMargin = gutter;
        sceneParams.rightMargin = gutter;
        mColumn.addView(scene, sceneParams);

        LinearLayout actions = BrowtherIntroUi.column(context);
        actions.setClipChildren(false);
        BrowtherIntroUi.spacing(actions, 6);
        LinearLayout.LayoutParams actionsParams = BrowtherIntroUi.linear(MATCH, WRAP);
        actionsParams.topMargin = dp(context, 14);
        actionsParams.leftMargin = gutter;
        actionsParams.rightMargin = gutter;
        mColumn.addView(actions, actionsParams);

        applyInsets(mTopInset, mBottomInset);
        return new Slots(scene, actions);
    }
}
