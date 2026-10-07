/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;
import android.net.Uri;

import androidx.annotation.Nullable;

import org.chromium.base.ApplicationStatus;
import org.chromium.base.ContextUtils;
import org.chromium.base.FileProviderUtils;
import org.chromium.base.version_info.VersionInfo;
import org.chromium.chrome.browser.app.BraveActivity;
import org.chromium.chrome.browser.browther_analytics.BrowtherAnalyticsBridge;
import org.chromium.chrome.browser.browther_referral.core.ReferralAuthClient;
import org.chromium.chrome.browser.preferences.BravePref;
import org.chromium.chrome.browser.profiles.ProfileManager;
import org.chromium.chrome.browser.tab.Tab;
import org.chromium.chrome.browser.tab.TabLaunchType;
import org.chromium.chrome.browser.tabmodel.TabClosureParams;
import org.chromium.chrome.browser.tracing.settings.DeveloperSettings;
import org.chromium.chrome.browser.util.TabUtils;
import org.chromium.components.user_prefs.UserPrefs;

import java.io.File;
import java.lang.ref.WeakReference;
import java.util.Map;

/**
 * Le parrainage branché sur Chromium : la SEULE classe du paquet qui en importe (hors les points
 * d'accroche de {@link BrowtherReferralHooks}). L'aperçu à l'émulateur la remplace par un faux
 * (private/scripts/android-intro-preview/), sans rien changer au contrôleur.
 */
public final class BrowtherReferralChromium {
    private BrowtherReferralChromium() {}

    /** Le rangement du compte dev&din : un seul, il ne tient que les préférences de l'app. */
    private static @Nullable ReferralAccountStore sAccountStore;

    /**
     * L'onglet ouvert pour la connexion Google / Apple — une référence FAIBLE : s'il est fermé par
     * la personne, on ne le retient pas.
     */
    private static @Nullable WeakReference<Tab> sSignInTab;

    public static BrowtherReferralController.Platform platform() {
        return new BrowtherReferralController.Platform() {
            @Override
            public Context appContext() {
                return ContextUtils.getApplicationContext();
            }

            @Override
            public SharedPreferences preferences() {
                return ContextUtils.getAppSharedPreferences();
            }

            @Override
            public void track(String event, Map<String, Object> properties) {
                // Les types survivent (`trackTyped` : booléen, entier) ; un long qui tient dans un
                // entier en devient un, sinon PostHog le recevrait en texte.
                Object[] keyValues = new Object[properties.size() * 2];
                int i = 0;
                for (Map.Entry<String, Object> entry : properties.entrySet()) {
                    Object value = entry.getValue();
                    if (value instanceof Long
                            && (Long) value <= Integer.MAX_VALUE
                            && (Long) value >= Integer.MIN_VALUE) {
                        value = ((Long) value).intValue();
                    }
                    keyValues[i++] = entry.getKey();
                    keyValues[i++] = value;
                }
                BrowtherAnalyticsBridge.trackTyped(event, keyValues);
            }

            @Override
            public long musicSecondsTotal() {
                return BrowtherAnalyticsBridge.getMusicSecondsTotal();
            }

            @Override
            public boolean isStoreBuild() {
                // Le Play Store ne reçoit que des builds officiels ; un build de dev (Component,
                // non officiel) garde le flow allumé pour la recette (§ 8.5).
                return VersionInfo.isOfficialBuild();
            }

            @Override
            public boolean showsRecette() {
                return !VersionInfo.isOfficialBuild()
                        || DeveloperSettings.shouldShowDeveloperSettings();
            }

            @Override
            public boolean isMusicRemovalEnabled() {
                return UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                        .getBoolean(BravePref.SAWTUNAA_ENABLED);
            }

            @Override
            public void setMusicRemovalEnabled(boolean enabled) {
                UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                        .setBoolean(BravePref.SAWTUNAA_ENABLED, enabled);
            }

            @Override
            public @Nullable Activity topActivity() {
                return ApplicationStatus.getLastTrackedFocusedActivity();
            }

            @Override
            public @Nullable Uri shareableUri(File file) {
                // Le FileProvider de Chrome (`file_paths.xml` : `files/images/`), celui des
                // captures partagées.
                try {
                    return FileProviderUtils.getContentUriFromFile(file);
                } catch (IllegalArgumentException e) {
                    return null;
                }
            }

            @Override
            public ReferralAccountStore accountStore() {
                ReferralAccountStore store = sAccountStore;
                if (store == null) {
                    // 🔴 Le jeton chiffré par l'Android Keystore, l'identifiant en clair à côté.
                    store = new ReferralAccountKeystore(ContextUtils.getAppSharedPreferences());
                    sAccountStore = store;
                }
                return store;
            }

            @Override
            public ReferralAuthClient authClient(String language) {
                return new ReferralAuthClient(language);
            }

            @Override
            public boolean openSignInTab(@Nullable Activity from, String url) {
                try {
                    BraveActivity browser = BraveActivity.getBraveActivity();
                    // ⛔ Jamais en navigation privée : le compte n'a rien à y faire, et le retour
                    // n'y est pas écouté (`BrowtherReferralHooks.onAuthCallback`).
                    Tab tab =
                            browser.getTabCreator(false)
                                    .launchUrl(url, TabLaunchType.FROM_CHROME_UI);
                    if (tab == null) return false;
                    sSignInTab = new WeakReference<>(tab);
                    // Depuis les Paramètres (une autre activité, posée sur le navigateur) : le
                    // navigateur revient devant, comme `TabUtils.openLinkWithFocus`. ⚠️ Cela FERME
                    // les Paramètres — la page du compte revient sur le navigateur.
                    if (from != null && from != browser) {
                        TabUtils.bringChromeTabbedActivityToTheTop(from);
                    }
                    return true;
                } catch (BraveActivity.BraveActivityNotFoundException | RuntimeException e) {
                    return false;
                }
            }

            @Override
            public void closeSignInTab() {
                WeakReference<Tab> reference = sSignInTab;
                sSignInTab = null;
                Tab tab = reference == null ? null : reference.get();
                try {
                    if (tab == null || tab.isDestroyed() || tab.isClosing()) return;
                    // ⚠️ Seulement s'il est ENCORE sur la page de l'auth-service (son « Redirection
                    // vers l'application… ») : un onglet de connexion abandonné, puis utilisé pour
                    // naviguer ailleurs, n'est plus le nôtre — ⛔ on ne ferme pas la page de
                    // quelqu'un.
                    if (!ReferralAuthClient.authHost.equals(tab.getUrl().getHost())) return;
                    // Comme Chromium ferme l'onglet d'une navigation partie vers une autre app
                    // (`InterceptNavigationDelegateClientImpl.closeTab`) : sans « annuler ».
                    BraveActivity.getBraveActivity()
                            .getTabModelSelector()
                            .tryCloseTab(
                                    TabClosureParams.closeTab(tab).allowUndo(false).build(),
                                    /* allowDialog= */ false);
                } catch (BraveActivity.BraveActivityNotFoundException | RuntimeException e) {
                    // L'onglet reste sur sa page « Redirection… » : gênant, jamais bloquant.
                }
            }
        };
    }
}
