/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.app.Activity;
import android.content.Context;
import android.content.SharedPreferences;

import androidx.annotation.Nullable;

import org.chromium.base.ApplicationStatus;
import org.chromium.base.ContextUtils;
import org.chromium.base.version_info.VersionInfo;
import org.chromium.chrome.browser.browther_analytics.BrowtherAnalyticsBridge;
import org.chromium.chrome.browser.preferences.BravePref;
import org.chromium.chrome.browser.profiles.ProfileManager;
import org.chromium.chrome.browser.tracing.settings.DeveloperSettings;
import org.chromium.components.user_prefs.UserPrefs;

import java.util.Map;

/**
 * Le parrainage branché sur Chromium : la SEULE classe du paquet qui en importe (hors les points
 * d'accroche de {@link BrowtherReferralHooks}). L'aperçu à l'émulateur la remplace par un faux
 * (private/scripts/android-intro-preview/), sans rien changer au contrôleur.
 */
public final class BrowtherReferralChromium {
    private BrowtherReferralChromium() {}

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
        };
    }
}
