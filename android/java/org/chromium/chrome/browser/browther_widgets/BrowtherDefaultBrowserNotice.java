/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_widgets;

import android.app.role.RoleManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.SystemClock;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.Nullable;

import org.chromium.chrome.R;

/**
 * Encart « navigateur par défaut » du Nouvel Onglet — pendant Android de l'encart iOS
 * ({@code NTPDefaultBrowserCalloutProvider}), redessinés ensemble le 2026-09-27 : l'encart de
 * Brave (« …dans iOS. Appuyez ici pour ouvrir les paramètres. », fond vert) était resté brut
 * (Karim : « c'est moche »), et Brave Android n'en avait pas.
 *
 * <p>⭐ <b>Même famille que le bandeau « accès anticipé »</b> posé juste au-dessus ({@code
 * browther_beta_notice.xml}) : même voile sombre, même liseré ambre, mêmes cotes, même croix, une
 * action en ambre. Les cotes sont RECOPIÉES du XML (pas de ressource partagée) pour que la vue se
 * construise hors Chromium, dans l'aperçu à l'émulateur — ⚠️ les faire évoluer ensemble.
 *
 * <p>⭐ <b>Aucun texte neuf</b> : le titre et la phrase sont ceux de l'étape « navigateur par
 * défaut » de l'introduction ({@code IDS_BROWTHER_INTRO_DEFAULT_*}), l'action celle de Brave
 * ({@code IDS_SET_DEFAULT_BROWSER}), la croix celle du bandeau ({@code
 * IDS_BROWTHER_BETA_NOTICE_DISMISS}) — toutes déjà traduites.
 *
 * <p>Montré tant que Browther n'est pas le navigateur par défaut et que la personne ne l'a pas
 * fermé ; fermé, il ne revient pas.
 */
public final class BrowtherDefaultBrowserNotice extends LinearLayout {
    /** Fermé une fois pour toutes (⛔ pas par version : ce n'est pas une nouveauté). */
    public static final String PREF_DISMISSED = "browther.default_browser_notice.dismissed";

    /** Ambre du bandeau « accès anticipé » (et du badge « Beta » du site). */
    private static final int ACCENT = 0xFFFBBF24;

    /**
     * Le rôle est lu au plus toutes les 2 s : l'adaptateur du Nouvel Onglet demande le compte de
     * ses items à chaque défilement, et {@code isRoleHeld} est un appel au système.
     */
    private static final long CACHE_MS = 2_000;

    private static long sCheckedAt = -CACHE_MS;
    private static boolean sIsDefault;

    /** L'encart doit-il être affiché ? */
    public static boolean shouldShow(Context context, SharedPreferences preferences) {
        if (preferences.getBoolean(PREF_DISMISSED, false)) return false;
        return !isDefaultBrowser(context);
    }

    /**
     * Browther tient-il le rôle « navigateur » ? Un système sans ce rôle (ou qui refuse de
     * répondre) ne montre pas l'encart : proposer un geste impossible serait pire que se taire.
     */
    private static boolean isDefaultBrowser(Context context) {
        long now = SystemClock.elapsedRealtime();
        if (now - sCheckedAt < CACHE_MS) return sIsDefault;
        sCheckedAt = now;
        try {
            RoleManager roles = context.getSystemService(RoleManager.class);
            sIsDefault =
                    roles == null
                            || !roles.isRoleAvailable(RoleManager.ROLE_BROWSER)
                            || roles.isRoleHeld(RoleManager.ROLE_BROWSER);
        } catch (RuntimeException e) {
            sIsDefault = true;
        }
        return sIsDefault;
    }

    /** Oublie la dernière lecture du rôle (au retour de la feuille système). */
    public static void forgetRoleReading() {
        sCheckedAt = -CACHE_MS;
    }

    /**
     * @param onAction ouvre la feuille système du rôle « navigateur » (c'est l'hôte qui a
     *     l'activité) — ⛔ jamais la fiche de l'app.
     * @param onDismissed appelé après la fermeture, pour retirer l'item du Nouvel Onglet.
     */
    public BrowtherDefaultBrowserNotice(
            Context context,
            SharedPreferences preferences,
            Runnable onAction,
            @Nullable Runnable onDismissed) {
        super(context);
        setOrientation(HORIZONTAL);
        setBackground(background());
        setPadding(dp(16), dp(14), dp(8), dp(14));

        // L'icône s'aligne sur la première ligne du titre, comme celle du bandeau.
        ImageView icon = new ImageView(context);
        icon.setImageResource(R.drawable.browther_intro_glyph_shield);
        icon.setImageTintList(ColorStateList.valueOf(ACCENT));
        icon.setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        LayoutParams iconParams = new LayoutParams(dp(20), dp(20));
        iconParams.topMargin = dp(1);
        addView(icon, iconParams);

        LinearLayout texts = new LinearLayout(context);
        texts.setOrientation(VERTICAL);
        LayoutParams textsParams = new LayoutParams(0, LayoutParams.WRAP_CONTENT, 1);
        textsParams.setMarginStart(dp(12));
        addView(texts, textsParams);

        TextView title = text(context, R.string.browther_intro_default_title, 15, 0xFFFFFFFF);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        texts.addView(title, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT));

        TextView body = text(context, R.string.browther_intro_default_subtitle, 13, 0xBFFFFFFF);
        LayoutParams bodyParams =
                new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT);
        bodyParams.topMargin = dp(3);
        texts.addView(body, bodyParams);

        TextView action = text(context, R.string.set_default_browser, 13, ACCENT);
        action.setTypeface(Typeface.DEFAULT_BOLD);
        action.setPadding(0, dp(2), 0, dp(2));
        action.setOnClickListener(
                v -> {
                    forgetRoleReading();
                    onAction.run();
                });
        LayoutParams actionParams =
                new LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT);
        actionParams.topMargin = dp(8);
        texts.addView(action, actionParams);

        ImageView close = new ImageView(context);
        close.setImageResource(R.drawable.ic_baseline_close_24);
        close.setImageTintList(ColorStateList.valueOf(0x99FFFFFF));
        close.setPadding(dp(8), dp(8), dp(8), dp(8));
        close.setBackground(new RippleDrawable(ColorStateList.valueOf(0x33FFFFFF), null, null));
        close.setContentDescription(context.getString(R.string.browther_beta_notice_dismiss));
        close.setOnClickListener(
                v -> {
                    preferences.edit().putBoolean(PREF_DISMISSED, true).apply();
                    if (onDismissed != null) onDismissed.run();
                });
        addView(close, new LayoutParams(dp(32), dp(32)));
        setGravity(Gravity.TOP);
    }

    /**
     * Le fond du bandeau ({@code browther_beta_notice_bg.xml}), recopié — voile à 70 %, raison
     * dans ce fichier ; les deux valeurs se changent ensemble.
     */
    private GradientDrawable background() {
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(0xB3000000);
        shape.setStroke(dp(1), 0x52FBBF24);
        shape.setCornerRadius(dp(12));
        return shape;
    }

    private static TextView text(Context context, int stringId, float sizeSp, int color) {
        TextView view = new TextView(context);
        view.setText(stringId);
        view.setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp);
        view.setTextColor(color);
        view.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);
        return view;
    }

    private int dp(float value) {
        return Math.round(
                TypedValue.applyDimension(
                        TypedValue.COMPLEX_UNIT_DIP, value, getResources().getDisplayMetrics()));
    }
}
