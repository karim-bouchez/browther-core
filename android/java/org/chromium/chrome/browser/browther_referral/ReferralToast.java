/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.app.Activity;
import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.PopupWindow;
import android.widget.TextView;

import androidx.annotation.Nullable;

import org.chromium.chrome.R;

/**
 * Les toasts du parrainage — docs/PARRAINAGE.md § 12.14 : <b>ce qui n'attend RIEN n'est pas une
 * fenêtre mais un toast</b> (0 bis « C'est noté », 5 « +3 jours offerts », la garde d'une
 * fonctionnalité en pause). Pendant de {@code BrowtherReferralToast.swift}.
 *
 * <p>Une {@link PopupWindow} NON focalisable posée sur l'activité du dessus : elle ne capte QUE les
 * touchers sur sa carte, le reste de l'écran reste utilisable (le pendant de la fenêtre
 * « passthrough » d'iOS). ⚠️ Pas la {@code Snackbar} de Chromium : une ligne, alors que ces toasts
 * disent une raison en deux ou trois lignes.
 *
 * <ul>
 *   <li>Un changement d'état reste jusqu'à ce qu'on le ferme (§ 12.26) — 0 bis, 5.
 *   <li>La garde a son bouton « Soutenir dev&din » bien visible (§ 12.20), et s'efface après ~10 s.
 *   <li>Un seul toast à la fois (§ 12.16).
 * </ul>
 */
public final class ReferralToast {
    private static final long DEFAULT_DURATION_MS = 10_000;
    private static final Handler sHandler = new Handler(Looper.getMainLooper());
    private static @Nullable PopupWindow sCurrent;
    private static @Nullable Runnable sAutoHide;

    private ReferralToast() {}

    /**
     * @param actionLabel le bouton du toast (« Soutenir dev&din »), ou {@code null}.
     * @param persistent reste jusqu'à ce qu'on le ferme ; sinon s'efface après ~10 s.
     */
    public static void show(
            @Nullable Activity activity,
            String title,
            @Nullable String body,
            @Nullable String actionLabel,
            @Nullable Runnable action,
            boolean persistent) {
        if (activity == null || activity.isFinishing() || activity.isDestroyed()) return;
        View anchor = activity.getWindow().getDecorView();
        if (anchor.getWindowToken() == null) return;
        hide();

        Context context = activity;
        ReferralUi.Palette p = ReferralUi.palette(context);
        LinearLayout card = ReferralUi.row(context);
        card.setGravity(Gravity.TOP);
        int pad = ReferralUi.dp(context, 14);
        card.setPadding(pad, pad, ReferralUi.dp(context, 6), pad);
        card.setBackground(ReferralUi.rounded(p.panel, ReferralUi.dp(context, 16), 1, p.line));
        card.setElevation(ReferralUi.dp(context, 8));

        LinearLayout texts = ReferralUi.column(context);
        TextView titleView = ReferralUi.text(context, title, 15, ReferralUi.SEMIBOLD, p.text);
        texts.addView(titleView);
        if (body != null) {
            TextView bodyView = ReferralUi.text(context, ReferralUi.rich(body), 13, ReferralUi.REGULAR, p.text2);
            bodyView.setPadding(0, ReferralUi.dp(context, 4), 0, 0);
            texts.addView(bodyView);
        }
        if (actionLabel != null && action != null) {
            TextView button = ReferralUi.text(context, actionLabel, 13, ReferralUi.SEMIBOLD, p.onPrimary);
            int padH = ReferralUi.dp(context, 14);
            int padV = ReferralUi.dp(context, 8);
            button.setPadding(padH, padV, padH, padV);
            button.setBackground(ReferralUi.rounded(p.primary, ReferralUi.dp(context, 100)));
            button.setOnClickListener(
                    v -> {
                        hide();
                        action.run();
                    });
            LinearLayout.LayoutParams params =
                    new LinearLayout.LayoutParams(ReferralUi.WRAP, ReferralUi.WRAP);
            params.topMargin = ReferralUi.dp(context, 10);
            texts.addView(button, params);
        }
        card.addView(texts, new LinearLayout.LayoutParams(0, ReferralUi.WRAP, 1));

        ImageView close = ReferralUi.glyph(context, R.drawable.browther_intro_glyph_xmark, 14, p.text2);
        int closePad = ReferralUi.dp(context, 15);
        close.setPadding(closePad, closePad, closePad, closePad);
        close.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
        close.setContentDescription(ReferralStrings.get(context, "common.close"));
        close.setOnClickListener(v -> hide());
        int closeSize = ReferralUi.dp(context, 44);
        card.addView(close, new LinearLayout.LayoutParams(closeSize, closeSize));

        int width = Math.min(anchor.getWidth() - ReferralUi.dp(context, 24), ReferralUi.dp(context, 520));
        PopupWindow popup = new PopupWindow(card, width, ViewGroup.LayoutParams.WRAP_CONTENT, false);
        popup.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
        popup.setOutsideTouchable(false);
        popup.setTouchModal(false);
        popup.setAnimationStyle(android.R.style.Animation_Toast);
        popup.setElevation(ReferralUi.dp(context, 8));
        try {
            popup.showAtLocation(anchor, Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL, 0,
                    ReferralUi.dp(context, 72));
        } catch (RuntimeException e) {
            // La fenêtre de l'activité est partie entre-temps : rien à montrer.
            return;
        }
        sCurrent = popup;
        card.announceForAccessibility(body == null ? title : title + " " + body);
        if (persistent) return;
        sAutoHide = ReferralToast::hide;
        sHandler.postDelayed(sAutoHide, DEFAULT_DURATION_MS);
    }

    public static void hide() {
        if (sAutoHide != null) sHandler.removeCallbacks(sAutoHide);
        sAutoHide = null;
        PopupWindow current = sCurrent;
        sCurrent = null;
        if (current == null) return;
        try {
            current.dismiss();
        } catch (RuntimeException e) {
            // Fenêtre déjà détachée.
        }
    }
}
