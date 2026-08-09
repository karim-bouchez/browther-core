/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_analytics;

import android.view.View;
import android.widget.Button;
import android.widget.TextView;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.app.BraveActivity;
import org.chromium.chrome.browser.tab.Tab;
import org.chromium.components.embedder_support.util.UrlUtilities;

/**
 * « Ça ne marche pas sur ce site ? » — signalement d'un site non géré, partagé
 * par les panels Basarunaa et Sawtunaa.
 *
 * <p>Portage Android de {@code components/browther_analytics/site_report.h}.
 * Le C++ n'est pas réutilisable tel quel (les panels Android sont des
 * BottomSheet Java, pas du WebUI), mais les règles sont les MÊMES et doivent le
 * rester :
 *
 * <ul>
 *   <li>seul le <b>domaine enregistrable</b> (eTLD+1) part, jamais l'URL, le
 *       chemin ni les paramètres — {@code dailymotion.com}, pas la vidéo ;
 *   <li>rien ne part sans un clic : aucune télémétrie passive de navigation ;
 *   <li>le consentement statistiques est respecté — et quand il est coupé on
 *       n'affiche pas un bouton qui ne ferait rien, on explique.
 * </ul>
 *
 * <p>C'est l'utilisateur qui juge : il sait ce qu'il s'attendait à voir traité,
 * là où une heuristique produirait des faux positifs sur des pages normales.
 */
@NullMarked
public class BrowtherSiteReport {
    private static final String TAG = "BrowtherSiteReport";

    private BrowtherSiteReport() {}

    /**
     * Câble la ligne de signalement d'un panel. À appeler après l'inflate.
     *
     * @param root vue racine du panel (doit contenir {@code
     *     browther_report_site_row})
     * @param feature {@code "basarunaa"} ou {@code "sawtunaa"} — la propriété
     *     qui permet de savoir LAQUELLE des deux features échoue sur ce site.
     */
    public static void bind(View root, String feature) {
        View row = root.findViewById(R.id.browther_report_site_row);
        TextView question = root.findViewById(R.id.browther_report_site_question);
        Button button = root.findViewById(R.id.browther_report_site_button);
        if (row == null || question == null || button == null) return;

        final String domain = registrableDomain();
        if (domain == null || domain.isEmpty()) {
            // Page interne (NTP, chrome://) ou URL sans domaine : rien à
            // signaler, on ne montre pas la ligne du tout.
            row.setVisibility(View.GONE);
            return;
        }
        row.setVisibility(View.VISIBLE);

        if (!BrowtherAnalyticsBridge.isPostHogEnabled()) {
            // L'envoi serait un no-op : le dire plutôt que d'afficher un bouton
            // sans effet (même règle anti-mensonge que l'encadré DRM).
            question.setText(R.string.browther_panel_report_site_analytics_off);
            button.setVisibility(View.GONE);
            return;
        }

        question.setText(R.string.browther_panel_report_site_question);
        button.setVisibility(View.VISIBLE);
        // Ce qui part exactement, au appui long : la phrase ne veut rien dire
        // tant qu'on ne sait pas à quelle action elle se rapporte.
        button.setTooltipText(
                root.getContext().getString(R.string.browther_panel_report_site_privacy, domain));
        button.setOnClickListener(
                v -> {
                    BrowtherAnalyticsBridge.trackWithProps(
                            "site_reported",
                            new String[] {"feature", "domain"},
                            new String[] {feature, domain});
                    // Confirmation à la place du bouton : on ne remercie que
                    // pour un envoi qui a bien eu lieu.
                    question.setText(R.string.browther_panel_report_site_done);
                    button.setVisibility(View.GONE);
                });
    }

    /** Domaine enregistrable de l'onglet actif, ou null s'il n'y en a pas. */
    private static @Nullable String registrableDomain() {
        try {
            Tab tab = BraveActivity.getBraveActivity().getActivityTab();
            if (tab == null || tab.getUrl() == null) return null;
            String url = tab.getUrl().getSpec();
            if (!url.startsWith("http://") && !url.startsWith("https://")) return null;
            // includePrivateRegistries : `foo.github.io` doit rester
            // `foo.github.io` et pas s'effondrer en `github.io`, sinon des
            // sites distincts se confondent dans les statistiques (même
            // réglage que le INCLUDE_PRIVATE_REGISTRIES du C++).
            return UrlUtilities.getDomainAndRegistry(url, true);
        } catch (BraveActivity.BraveActivityNotFoundException e) {
            Log.e(TAG, "registrableDomain " + e);
            return null;
        }
    }
}
