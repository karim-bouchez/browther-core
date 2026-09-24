/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.app.Activity;
import android.view.View;

import org.chromium.chrome.browser.tab.Tab;
import org.chromium.url.GURL;

import java.time.Instant;

/**
 * Les points d'accroche du parrainage dans le navigateur — une ligne dans chaque fichier upstream
 * ({@code BraveToolbarLayoutImpl}, {@code BraveActivity}, {@code BraveNewTabPageLayout}), toute
 * la logique ici. ⛔ Aucun ne doit retenir la navigation : le contrôleur avale ses erreurs.
 */
public final class BrowtherReferralHooks {
    /** ⭐ Jamais à la milliseconde où la page se pose (§ 7.2) : le Nouvel Onglet s'installe d'abord. */
    private static final long NEW_TAB_DELAY_MS = 1_200;

    private BrowtherReferralHooks() {}

    /**
     * Une page a fini de charger. Seule compte une VRAIE page : onglet normal (⛔ navigation
     * privée), {@code http(s)} — la même unité que les surfaces communes (§ 2.1).
     */
    public static void onPageLoaded(Tab tab, GURL url) {
        if (tab == null || url == null || tab.isIncognito()) return;
        String scheme = url.getScheme();
        if (!"http".equals(scheme) && !"https".equals(scheme)) return;
        try {
            BrowtherReferralController.get().notePageLoaded();
        } catch (RuntimeException e) {
            // ⛔ Le parrainage ne casse jamais la navigation.
        }
    }

    /** Reprise de l'activité principale. */
    public static void onForeground() {
        try {
            BrowtherReferralController.get().onForeground();
        } catch (RuntimeException e) {
            // Sens de la panne : ouvert.
        }
    }

    /**
     * Le Nouvel Onglet est affiché : le seul point d'entrée spontané des écrans (§ 2.2). Après 1,2 s,
     * s'il est toujours là et que l'activité a la main : la pause pour de vrai, puis la sollicitation
     * due, s'il y en a une.
     */
    public static void onNewTabPageShown(Activity activity, View ntp) {
        if (activity == null || ntp == null) return;
        ntp.postDelayed(
                () -> {
                    if (!ntp.isAttachedToWindow() || !activity.hasWindowFocus()) return;
                    if (activity.isFinishing() || activity.isDestroyed()) return;
                    try {
                        BrowtherReferralController controller = BrowtherReferralController.get();
                        controller.enforcePauseIfNeeded(activity);
                        controller.attemptSolicitation(activity, Instant.now(), null);
                    } catch (RuntimeException e) {
                        // ⛔ Jamais au prix du Nouvel Onglet.
                    }
                },
                NEW_TAB_DELAY_MS);
    }
}
