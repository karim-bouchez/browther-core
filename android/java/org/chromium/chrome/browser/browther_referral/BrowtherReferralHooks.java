/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.app.Activity;
import android.view.View;

import org.chromium.chrome.browser.browther_referral.core.ReferralAuthClient;
import org.chromium.chrome.browser.tab.Tab;
import org.chromium.components.external_intents.ExternalNavigationParams;
import org.chromium.url.GURL;
import org.chromium.url.Origin;

import java.time.Instant;

/**
 * Les points d'accroche du parrainage dans le navigateur — une ligne dans chaque fichier upstream
 * ({@code BraveToolbarLayoutImpl}, {@code BraveActivity}, {@code BraveNewTabPageLayout}, {@code
 * BraveExternalNavigationHandler}), toute la logique ici. ⛔ Aucun ne doit retenir la navigation :
 * le contrôleur avale ses erreurs.
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

    /**
     * ⭐ Le retour de la connexion Google / Apple du compte dev&din : {@code
     * browther://auth/callback?code=…} (docs/AUTH.md, {@code SSO_APP_LINKS}). Browther EST le
     * navigateur : la page de connexion vit dans un de ses onglets, et l'auth-service la finit par
     * une navigation vers cette adresse — rattrapée ici, en tête de {@code
     * BraveExternalNavigationHandler.shouldOverrideUrlLoading}, avant tout routage de schéma.
     *
     * <p>{@code true} = c'était le nôtre : la navigation est AVALÉE (une adresse {@code
     * browther://auth/callback} n'ouvre jamais rien d'autre), que le code soit écouté ou non.
     *
     * <p>🔴 Le code n'est écouté que s'il vient de la page de l'auth-service elle-même, dans le
     * cadre principal d'un onglet normal — et le contrôleur exige en plus qu'une connexion ait été
     * lancée d'ici, il y a peu. Sans ces gardes, n'importe quelle page pourrait pousser SON code et
     * rattacher cet appareil au compte de quelqu'un d'autre.
     *
     * <p>⛔ On est DANS le chemin de navigation : rien ne lève, rien n'attend (le contrôleur ne fait
     * que noter, tout le reste part après).
     */
    public static boolean onAuthCallback(ExternalNavigationParams params) {
        try {
            GURL url = params.getUrl();
            // Le cas de TOUTES les autres navigations : un schéma qui n'est pas le nôtre.
            if (url == null || !ReferralAuthClient.callbackScheme.equals(url.getScheme())) {
                return false;
            }
            String spec = url.getSpec();
            if (!ReferralAuthClient.isCallback(spec)) return false;
            if (params.isMainFrame() && !params.isIncognito() && cameFromAuthService(params)) {
                BrowtherReferralController.get().onWebSignInCallback(spec);
            }
            return true;
        } catch (RuntimeException e) {
            // ⛔ Le parrainage ne casse jamais la navigation.
            return false;
        }
    }

    /**
     * La navigation a-t-elle été lancée par une page de {@code https://auth.devndin.com} ? (son
     * script, sa balise de rafraîchissement ou son lien « cliquez ici »). L'origine de l'initiateur
     * d'abord ; à défaut seulement, le référent.
     */
    private static boolean cameFromAuthService(ExternalNavigationParams params) {
        Origin initiator = params.getInitiatorOrigin();
        if (initiator != null) return isAuthService(initiator.getScheme(), initiator.getHost());
        GURL referrer = params.getReferrerUrl();
        return referrer != null && isAuthService(referrer.getScheme(), referrer.getHost());
    }

    private static boolean isAuthService(String scheme, String host) {
        return "https".equals(scheme) && ReferralAuthClient.authHost.equals(host);
    }
}
