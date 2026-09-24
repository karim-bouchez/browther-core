/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.animation.ObjectAnimator;
import android.app.Activity;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * Le parrainage DANS le panneau d'une fonctionnalité supplémentaire (Sawtunaa) — pendant iOS de
 * {@code SawtunaaPanelView} + {@code ReferralExtraCallout}, et du {@code setUIReferralPaused} de
 * macOS (private/docs/PARRAINAGE.md § 2.10 et § 2.14).
 *
 * <p>🔴 <b>En pause, l'interrupteur est VERROUILLÉ</b> : terne, il ne bascule pas — un toucher
 * fait CLIGNOTER l'explication, et rien ne s'ouvre. ⛔ Un interrupteur qu'on peut pousser et qui
 * revient tout seul ment (le bug qu'iOS a eu). L'état dit « En pause », la description dit le
 * verrou, et un seul bouton plein doré « Débloquer » ouvre J0 — FERMABLE ({@code paused(chosen)},
 * § 12.16). ⚠️ Le panneau se ferme D'ABORD : une fenêtre ouverte depuis une feuille ne s'ouvre
 * pas par-dessus elle.
 *
 * <p>Hors pause : un encadré doré discret (« Fonctionnalité supplémentaire », jusqu'à quand, « La
 * garder à vie »), MUET avant l'annonce, à vie, pour un abonné — et en pause (le panneau le dit
 * alors avec SES surfaces : ⛔ pas deux fois).
 */
public final class ReferralExtraPanel {
    /** Le temps que la feuille du panneau se retire avant d'ouvrir la fenêtre. */
    private static final long AFTER_CLOSE_MS = 300;

    private ReferralExtraPanel() {}

    /**
     * Pose l'état du parrainage sur le panneau.
     *
     * @param slot un conteneur vide sous la description, rempli ici (ou laissé caché).
     * @param closePanel ferme la feuille du panneau.
     * @return {@code true} si la fonctionnalité est en pause (interrupteur verrouillé).
     */
    public static boolean bind(
            Activity activity,
            View toggle,
            TextView status,
            TextView description,
            ViewGroup slot,
            Runnable closePanel) {
        slot.removeAllViews();
        slot.setVisibility(View.GONE);
        BrowtherReferralController controller = BrowtherReferralController.get();
        Context context = slot.getContext();
        ReferralUi.Palette p = ReferralUi.palette(context);

        if (controller.isPaused()) {
            toggle.setAlpha(0.4f);
            toggle.setOnTouchListener(
                    (v, event) -> {
                        if (event.getActionMasked() == MotionEvent.ACTION_UP) blink(description);
                        // ⛔ Le toucher est gardé : l'interrupteur ne bascule pas.
                        return true;
                    });
            status.setText(ReferralStrings.get(context, "features.paused"));
            status.setTextColor(p.gold);
            description.setText(ReferralStrings.get(context, "locked.musicRemoval"));
            description.setMovementMethod(null);
            description.setGravity(Gravity.CENTER_HORIZONTAL);

            // Un bouton PLEIN doré (§ 2.14 / desktop 2026-09-24 : un lien doré « on ne le voit
            // pas vraiment », alors que c'est la seule sortie). ⛔ Pas le ∞ du bouton « à vie ».
            TextView unlock =
                    ReferralUi.text(
                            context,
                            ReferralStrings.get(context, "locked.unlock"),
                            16,
                            ReferralUi.SEMIBOLD,
                            ReferralUi.Palette.INK);
            unlock.setGravity(Gravity.CENTER);
            unlock.setMinHeight(ReferralUi.dp(context, 48));
            unlock.setBackground(
                    ReferralUi.pressable(
                            ReferralUi.rounded(p.goldFill, ReferralUi.dp(context, 14)),
                            ReferralUi.withAlpha(ReferralUi.Palette.INK, 0.2f),
                            ReferralUi.dp(context, 14)));
            unlock.setOnClickListener(
                    v ->
                            after(
                                    closePanel,
                                    () ->
                                            BrowtherReferralPresenter.present(
                                                    activity,
                                                    ReferralScreen.paused(true),
                                                    BrowtherReferralPresenter.Source.LOCKED,
                                                    false)));
            ReferralUi.pressFeedback(unlock);
            slot.addView(unlock, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
            slot.setVisibility(View.VISIBLE);
            return true;
        }

        toggle.setAlpha(1f);
        toggle.setOnTouchListener(null);
        String line = controller.extraCalloutLine(context);
        if (line == null) return false;

        LinearLayout box = ReferralUi.column(context);
        int pad = ReferralUi.dp(context, 12);
        box.setPadding(pad, pad, pad, pad);
        box.setBackground(
                ReferralUi.rounded(p.goldSurface, ReferralUi.dp(context, 14), 1, p.goldSurface));
        box.addView(
                ReferralUi.text(
                        context,
                        ReferralStrings.get(context, "panel.extraBadge"),
                        12,
                        ReferralUi.SEMIBOLD,
                        p.gold));
        TextView lineView = ReferralUi.text(context, line, 14, ReferralUi.REGULAR, p.text);
        lineView.setPadding(0, ReferralUi.dp(context, 4), 0, ReferralUi.dp(context, 8));
        box.addView(lineView);
        TextView keep =
                ReferralUi.text(
                        context,
                        ReferralStrings.get(context, "panel.keepForLife"),
                        14,
                        ReferralUi.SEMIBOLD,
                        p.gold);
        // ⚠️ La zone touchable, c'est le libellé ET sa marge (le piège du `Button` iOS, § 2.14).
        int touch = ReferralUi.dp(context, 6);
        keep.setPadding(0, touch, touch * 2, touch);
        keep.setOnClickListener(
                v ->
                        after(
                                closePanel,
                                () ->
                                        BrowtherReferralPresenter.present(
                                                activity,
                                                ReferralScreen.support(false),
                                                BrowtherReferralPresenter.Source.USER,
                                                false)));
        box.addView(keep);
        slot.addView(box, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        slot.setVisibility(View.VISIBLE);
        return false;
    }

    /** L'explication clignote une fois, sur place (desktop : « allumer pendant la pause n'ouvre RIEN »). */
    private static void blink(View view) {
        ObjectAnimator animator = ObjectAnimator.ofFloat(view, View.ALPHA, 1f, 0.2f, 1f, 0.2f, 1f);
        animator.setDuration(700);
        animator.start();
    }

    private static void after(Runnable closePanel, Runnable open) {
        closePanel.run();
        new Handler(Looper.getMainLooper()).postDelayed(open, AFTER_CLOSE_MS);
    }
}
