/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_widgets;

import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.graphics.drawable.GradientDrawable;
import android.view.View;
import android.widget.ImageView;
import android.widget.TextView;

import org.chromium.build.annotations.NullMarked;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.util.TabUtils;

/**
 * Accès anticipé de Sawtunaa et Basarunaa : un seul interrupteur pour les trois
 * surfaces qui le signalent — le badge de la toolbar, le gros toggle des panels
 * et l'encadré « encore en développement ». Parité avec {@code
 * kBrowtherEarlyAccess} (desktop, *_action_view.cc) et iOS.
 *
 * <p>Les deux features partent OFF (pref Chromium partagée avec le desktop,
 * cf. brave_profile_prefs.cc). Celui qui les allume choisit d'essayer quelque
 * chose d'inachevé : il doit l'apprendre au moment du geste, pas en concluant
 * d'un résultat irrégulier que le navigateur est mauvais.
 */
@NullMarked
public final class BrowtherEarlyAccess {
    /**
     * Tant que c'est vrai, « ON » ne veut pas dire « ça marche » : badge et gros
     * toggle passent à l'ambre au lieu du vert, et l'encadré s'affiche.
     * À REPASSER à {@code false} quand on sort de l'accès anticipé, en même
     * temps que le desktop et iOS.
     */
    public static final boolean ENABLED = true;

    // Mêmes URL que le bandeau NTP (BrowtherBetaNoticeView) et l'onboarding :
    // si elles changent, `grep 0029Vb8ydkv5vKABH78PVX32`.
    private static final String WHATSAPP_URL =
            "https://whatsapp.com/channel/0029Vb8ydkv5vKABH78PVX32";
    private static final String TELEGRAM_URL = "https://t.me/devndin_nouveautes";

    // L'ambre du desktop (#FBBF24) tombe à ~1,7:1 de contraste sur le fond
    // blanc du thème jour : illisible. amber-700 en jour, #FBBF24 en nuit.
    private static final int AMBER_LIGHT_THEME = 0xFFB45309;
    private static final int AMBER_DARK_THEME = 0xFFFBBF24;

    private BrowtherEarlyAccess() {}

    /**
     * Branche l'encadré inclus via {@code @layout/browther_feature_beta_notice}.
     *
     * @param root vue racine du panel qui contient l'encadré.
     * @param onChannelOpened appelé après l'ouverture d'un canal — le panel s'y
     *     referme, sinon le nouvel onglet s'ouvre derrière une bottom sheet.
     */
    public static void bindNotice(View root, Runnable onChannelOpened) {
        View notice = root.findViewById(R.id.browther_feature_beta_notice);
        if (notice == null) return;

        boolean night =
                (root.getResources().getConfiguration().uiMode
                                & Configuration.UI_MODE_NIGHT_MASK)
                        == Configuration.UI_MODE_NIGHT_YES;
        int amber = night ? AMBER_DARK_THEME : AMBER_LIGHT_THEME;

        // Fond NEUTRE et seul le bécher + les liens en ambre : l'ambre plein
        // veut déjà dire ailleurs « allumé mais sans effet ici ». Ici la
        // feature marche, elle n'est simplement pas finie.
        float density = root.getResources().getDisplayMetrics().density;
        GradientDrawable bg = new GradientDrawable();
        bg.setCornerRadius(8 * density);
        bg.setColor(night ? 0x0DFFFFFF : 0x0A000000);
        bg.setStroke(Math.round(density), (amber & 0x00FFFFFF) | 0x52000000);
        notice.setBackground(bg);

        ImageView icon = root.findViewById(R.id.browther_feature_beta_icon);
        if (icon != null) {
            icon.setImageTintList(ColorStateList.valueOf(amber));
        }

        bindChannel(root, R.id.browther_feature_beta_whatsapp, WHATSAPP_URL, amber,
                onChannelOpened);
        bindChannel(root, R.id.browther_feature_beta_telegram, TELEGRAM_URL, amber,
                onChannelOpened);
    }

    /**
     * Visible tant que la feature est ON, et seulement là. Volontairement non
     * refermable : ce n'est pas une notification qu'on acquitte, c'est l'état
     * de la feature.
     */
    public static void setNoticeVisible(View root, boolean featureOn) {
        View notice = root.findViewById(R.id.browther_feature_beta_notice);
        if (notice == null) return;
        notice.setVisibility(ENABLED && featureOn ? View.VISIBLE : View.GONE);
    }

    private static void bindChannel(
            View root, int id, String url, int amber, Runnable onChannelOpened) {
        TextView link = root.findViewById(id);
        if (link == null) return;
        link.setTextColor(amber);
        link.setOnClickListener(
                v -> {
                    TabUtils.openUrlInNewTab(false, url);
                    onChannelOpened.run();
                });
    }
}
