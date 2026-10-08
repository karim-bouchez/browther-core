/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.app.Activity;
import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.PopupWindow;
import android.widget.TextView;

import androidx.annotation.Nullable;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_referral.core.ReferralToastPlacement;

import java.lang.ref.WeakReference;

/**
 * Les toasts du parrainage — docs/PARRAINAGE.md § 12.14 : <b>ce qui n'attend RIEN n'est pas une
 * fenêtre mais un toast</b> (0 bis « C'est noté », 5 « +3 jours offerts », la garde d'une
 * fonctionnalité en pause). Pendant de {@code BrowtherReferralToast.swift}.
 *
 * <p>Une {@link PopupWindow} NON focalisable : elle ne capte QUE les touchers sur sa carte, le
 * reste de l'écran reste utilisable (le pendant de la fenêtre « passthrough » d'iOS). ⚠️ Pas la
 * {@code Snackbar} de Chromium : une ligne, alors que ces toasts disent une raison en deux ou trois
 * lignes.
 *
 * <ul>
 *   <li>Un changement d'état reste jusqu'à ce qu'on le ferme (§ 12.26) — 0 bis, 5.
 *   <li>La garde a son bouton « Soutenir dev&din » bien visible (§ 12.20), et s'efface après ~10 s.
 *   <li>Un seul toast à la fois (§ 12.16).
 *   <li>⭐ <b>En bas ; en haut dès qu'une feuille ou une fenêtre du flow est ouverte</b> ({@code
 *       core/ReferralToastPlacement}, private/docs/PARRAINAGE.md § 11.6) : leur bouton est en bas,
 *       un toast l'aurait recouvert. C'est l'écran qui RESTE qui décide : une fenêtre fermée ne
 *       compte plus ({@code BrowtherReferralPresenter.sheetOrFlowIsOpen}) — ⛔ on ferme AVANT de
 *       poser le toast, jamais l'inverse.
 * </ul>
 *
 * <h2>Sur quelle fenêtre il se pose</h2>
 *
 * <p>⚠️ Sur Android, ce toast est une sous-fenêtre de CELLE qui le porte : ancré sur l'activité, il
 * s'affiche SOUS toute fenêtre du parrainage ouverte par-dessus (elles sont plein écran). Il se
 * pose donc sur la fenêtre du parrainage du dessus, s'il y en a une ({@code
 * BrowtherReferralPresenter.toastAnchor}) ; et quand elle se ferme, il se REPOSE sur ce qui reste
 * ({@link #windowClosed}) — un toast qui annonce un changement d'état ne disparaît pas parce qu'on a
 * refermé l'écran d'où il est né. (Défaut du § 10.6 : le « +3 jours offerts » d'un partage restait
 * caché sous l'écran Parrainage jusqu'à sa fermeture.)
 */
public final class ReferralToast {
    private static final long DEFAULT_DURATION_MS = 10_000;
    private static final Handler sHandler = new Handler(Looper.getMainLooper());
    private static @Nullable PopupWindow sCurrent;
    private static @Nullable Runnable sAutoHide;
    /** La fenêtre qui porte le toast affiché — voir {@link #hideIfOn} et {@link #windowClosed}. */
    private static @Nullable View sAnchor;
    /**
     * De quoi REPOSER le toast affiché sur une autre fenêtre — {@code null} pour le mot d'une page
     * sur elle-même ({@link #showOn}), qui part avec elle.
     */
    private static @Nullable Spec sSpec;

    private ReferralToast() {}

    /** Un toast, tel qu'il a été demandé. */
    private static final class Spec {
        final WeakReference<Activity> activity;
        final String title;
        final @Nullable String body;
        final @Nullable String actionLabel;
        final @Nullable Runnable action;
        /** Quand il s'efface seul ({@code SystemClock.uptimeMillis}) — {@code 0} = il reste. */
        final long hideAt;

        Spec(
                Activity activity,
                String title,
                @Nullable String body,
                @Nullable String actionLabel,
                @Nullable Runnable action,
                long hideAt) {
            this.activity = new WeakReference<>(activity);
            this.title = title;
            this.body = body;
            this.actionLabel = actionLabel;
            this.action = action;
            this.hideAt = hideAt;
        }
    }

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
        show(activity, title, body, actionLabel, action, persistent ? 0 : DEFAULT_DURATION_MS);
    }

    /**
     * @param durationMs {@code 0} = reste jusqu'à ce qu'on le ferme.
     */
    public static void show(
            @Nullable Activity activity,
            String title,
            @Nullable String body,
            @Nullable String actionLabel,
            @Nullable Runnable action,
            long durationMs) {
        if (activity == null) return;
        long hideAt = durationMs <= 0 ? 0 : SystemClock.uptimeMillis() + durationMs;
        pose(new Spec(activity, title, body, actionLabel, action, hideAt), true);
    }

    /**
     * Pose (ou repose) un toast sur la fenêtre du dessus, à la place que l'écran qui RESTE lui
     * donne.
     */
    private static void pose(Spec spec, boolean announce) {
        Activity activity = spec.activity.get();
        if (activity == null || activity.isFinishing() || activity.isDestroyed()) return;
        long left = spec.hideAt == 0 ? 0 : spec.hideAt - SystemClock.uptimeMillis();
        if (spec.hideAt != 0 && left <= 0) return;
        View anchor = BrowtherReferralPresenter.toastAnchor();
        if (anchor == null || anchor.getWindowToken() == null) {
            anchor = activity.getWindow().getDecorView();
        }
        ReferralToastPlacement placement =
                ReferralToastPlacement.resolve(BrowtherReferralPresenter.sheetOrFlowIsOpen());
        boolean shown =
                present(
                        anchor,
                        activity,
                        spec.title,
                        spec.body,
                        spec.actionLabel,
                        spec.action,
                        left,
                        placement,
                        announce);
        if (shown) sSpec = spec;
    }

    /**
     * Le même toast, posé sur une fenêtre PRÉCISE — la page du compte, pour ce qu'elle dit
     * d'elle-même (« compte supprimé », « c'est fait ») : il s'ancre sur elle, et part avec elle.
     * En bas : c'est un écran à en-tête, son bas est libre.
     *
     * @param window une vue de la fenêtre qui doit le porter (sa vue de décor).
     * @param durationMs {@code 0} = reste jusqu'à ce qu'on le ferme.
     */
    public static void showOn(View window, String title, @Nullable String body, long durationMs) {
        present(
                window,
                window.getContext(),
                title,
                body,
                null,
                null,
                durationMs,
                ReferralToastPlacement.BOTTOM,
                true);
    }

    /** Efface le toast s'il est porté par cette fenêtre — elle se ferme, il partirait de travers. */
    public static void hideIfOn(View window) {
        if (sAnchor == window) hide();
    }

    /**
     * Une fenêtre du parrainage vient de se fermer ({@code BrowtherReferralPresenter}) : le toast
     * qu'elle portait se repose sur ce qui RESTE — la fenêtre d'en dessous, ou l'activité —, à la
     * place que CET écran-là lui donne. Le mot d'une page sur elle-même, lui, s'efface.
     */
    static void windowClosed(View window) {
        if (sAnchor != window) return;
        Spec spec = sSpec;
        hide();
        if (spec != null) pose(spec, false);
    }

    private static boolean present(
            View anchor,
            Context context,
            String title,
            @Nullable String body,
            @Nullable String actionLabel,
            @Nullable Runnable action,
            long durationMs,
            ReferralToastPlacement placement,
            boolean announce) {
        if (anchor.getWindowToken() == null) return false;
        hide();

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
        boolean top = placement == ReferralToastPlacement.TOP;
        try {
            // En bas : au-dessus de la barre d'outils du navigateur. En haut : sous la barre d'état
            // (et l'encoche) — ⚠️ une fenêtre du parrainage s'étend SOUS elles.
            popup.showAtLocation(
                    anchor,
                    (top ? Gravity.TOP : Gravity.BOTTOM) | Gravity.CENTER_HORIZONTAL,
                    0,
                    top ? topInset(anchor) + ReferralUi.dp(context, 8) : ReferralUi.dp(context, 72));
        } catch (RuntimeException e) {
            // La fenêtre est partie entre-temps : rien à montrer.
            return false;
        }
        sCurrent = popup;
        sAnchor = anchor;
        if (announce) card.announceForAccessibility(body == null ? title : title + " " + body);
        if (durationMs <= 0) return true;
        sAutoHide = ReferralToast::hide;
        sHandler.postDelayed(sAutoHide, durationMs);
        return true;
    }

    /** La hauteur de la barre d'état (encoche comprise) de la fenêtre qui porte le toast. */
    private static int topInset(View anchor) {
        WindowInsets insets = anchor.getRootWindowInsets();
        if (insets == null) return 0;
        // ⚠️ `WindowInsets.Type` n'existe qu'à partir d'Android 11 (le minimum de Chromium est 10).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return insets.getInsets(
                            WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout())
                    .top;
        }
        return insets.getSystemWindowInsetTop();
    }

    public static void hide() {
        if (sAutoHide != null) sHandler.removeCallbacks(sAutoHide);
        sAutoHide = null;
        PopupWindow current = sCurrent;
        sCurrent = null;
        sAnchor = null;
        sSpec = null;
        if (current == null) return;
        try {
            current.dismiss();
        } catch (RuntimeException e) {
            // Fenêtre déjà détachée.
        }
    }
}
