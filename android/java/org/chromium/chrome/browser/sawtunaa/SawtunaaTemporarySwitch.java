/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.sawtunaa;

import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.Nullable;

import org.chromium.base.ContextUtils;
import org.chromium.base.ObserverList;
import org.chromium.base.ThreadUtils;
import org.chromium.build.annotations.NullMarked;
import org.chromium.chrome.browser.browther_analytics.BrowtherAnalyticsBridge;
import org.chromium.chrome.browser.browther_referral.BrowtherReferralController;
import org.chromium.chrome.browser.preferences.BravePref;
import org.chromium.chrome.browser.preferences.PrefServiceUtil;
import org.chromium.chrome.browser.profiles.Profile;
import org.chromium.chrome.browser.profiles.ProfileManager;
import org.chromium.components.prefs.PrefChangeRegistrar;
import org.chromium.components.user_prefs.UserPrefs;

/**
 * « Seulement 2 min » — port de l'iOS {@code SawtunaaTemporarySwitch.swift} (maquette validée par
 * Karim le 2026-10-01). Juste après une bascule de Sawtunaa, le panneau propose de revenir
 * automatiquement à l'état d'avant dans 2 min, dans les deux sens.
 *
 * <ul>
 *   <li>L'interrupteur montre toujours l'état ACTUEL : la pref n'est touchée qu'à l'échéance.
 *   <li>Revenir plus tôt = rebasculer l'interrupteur, ou toucher le bouton de la barre d'outils
 *       ({@link #revertNow}) ; toute écriture de la pref qui rejoint l'état d'avant, d'où qu'elle
 *       vienne (réglages, pause du parrainage…), annule le retour.
 *   <li>Portée : tout le navigateur. L'échéance est enregistrée : une appli fermée pendant le compte
 *       à rebours retrouve l'état d'avant au lancement suivant.
 *   <li>⛔ Pas de rallumage pendant la pause du parrainage : elle garde Sawtunaa éteint.
 * </ul>
 *
 * <p>Thread UI uniquement. Créé au premier {@link #get()}, après le chargement natif (la barre
 * d'outils l'appelle dans {@code onNativeLibraryReady}).
 */
@NullMarked
public final class SawtunaaTemporarySwitch {
    public static final long DURATION_MS = 120_000L;

    /** Prévenu à chaque début / fin de compte à rebours. */
    public interface Observer {
        void onTemporarySwitchChanged();
    }

    // SharedPreferences de l'appli (pas ChromeSharedPreferences : ses clés doivent être déclarées).
    private static final String KEY_REVERT_AT = "browther_sawtunaa_temporary_revert_at";
    private static final String KEY_REVERT_TO = "browther_sawtunaa_temporary_revert_to";

    @Nullable private static SawtunaaTemporarySwitch sInstance;

    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private final ObserverList<Observer> mObservers = new ObserverList<>();
    private final Runnable mDue = this::checkDue;
    @Nullable private PrefChangeRegistrar mRegistrar;
    /** Échéance (horloge murale, ms) ; 0 = aucun retour programmé. */
    private long mRevertAtMs;
    private boolean mRevertTo;

    public static SawtunaaTemporarySwitch get() {
        ThreadUtils.assertOnUiThread();
        if (sInstance == null) {
            sInstance = new SawtunaaTemporarySwitch();
        }
        return sInstance;
    }

    private SawtunaaTemporarySwitch() {
        SharedPreferences sp = ContextUtils.getAppSharedPreferences();
        mRevertAtMs = sp.getLong(KEY_REVERT_AT, 0);
        mRevertTo = sp.getBoolean(KEY_REVERT_TO, false);
        Profile profile = ProfileManager.getLastUsedRegularProfile();
        if (profile != null) {
            mRegistrar = PrefServiceUtil.createFor(profile);
            mRegistrar.addObserver(BravePref.SAWTUNAA_ENABLED, this::onPrefChanged);
        }
        // L'appli était fermée à l'échéance : on rétablit sans attendre.
        checkDue();
    }

    public void addObserver(Observer observer) {
        mObservers.addObserver(observer);
    }

    public void removeObserver(Observer observer) {
        mObservers.removeObserver(observer);
    }

    public boolean isActive() {
        return mRevertAtMs > 0;
    }

    /** Millisecondes restantes (0 si rien n'est programmé). */
    public long remainingMs() {
        return isActive() ? Math.max(0, mRevertAtMs - System.currentTimeMillis()) : 0;
    }

    /** Programme le retour à l'état d'AVANT la bascule qui vient d'avoir lieu. */
    public void start() {
        boolean enabled = isEnabled();
        mRevertTo = !enabled;
        mRevertAtMs = System.currentTimeMillis() + DURATION_MS;
        persist();
        schedule();
        notifyObservers();
        track(
                "feature_temporary",
                new String[] {"enabled", "minutes"},
                new String[] {Boolean.toString(enabled), Long.toString(DURATION_MS / 60_000L)});
    }

    /** « Ne pas réactiver » / « Ne pas couper » : l'état actuel devient durable. */
    public void keep() {
        if (!isActive()) return;
        clear();
        track("feature_temporary_end", new String[] {"reason"}, new String[] {"keep"});
    }

    /** Retour immédiat à l'état d'avant (appui sur le bouton de la barre d'outils). */
    public void revertNow() {
        if (!isActive()) return;
        finish("icon");
    }

    /**
     * Applique le retour s'il est échu. Appelé par la minuterie, et par la barre d'outils à chaque
     * battement de l'anneau : un {@link Handler} ne compte pas le temps de veille profonde, une
     * échéance tombée écran éteint serait sinon rattrapée en retard.
     */
    public void checkDue() {
        if (!isActive()) return;
        if (System.currentTimeMillis() >= mRevertAtMs) {
            finish("timer");
        } else {
            schedule();
        }
    }

    private void finish(String reason) {
        boolean target = mRevertTo;
        clear();
        if (target && BrowtherReferralController.get().isPaused()) {
            track(
                    "feature_temporary_end",
                    new String[] {"reason", "skipped"},
                    new String[] {reason, "referral_paused"});
            return;
        }
        Profile profile = ProfileManager.getLastUsedRegularProfile();
        if (profile != null) {
            UserPrefs.get(profile).setBoolean(BravePref.SAWTUNAA_ENABLED, target);
        }
        track("feature_temporary_end", new String[] {"reason"}, new String[] {reason});
    }

    private void onPrefChanged() {
        // Quelqu'un est revenu à l'état d'avant : plus rien à rétablir.
        if (isActive() && isEnabled() == mRevertTo) {
            clear();
            track("feature_temporary_end", new String[] {"reason"}, new String[] {"toggle"});
        }
    }

    private void clear() {
        mHandler.removeCallbacks(mDue);
        mRevertAtMs = 0;
        persist();
        notifyObservers();
    }

    private void schedule() {
        mHandler.removeCallbacks(mDue);
        if (isActive()) {
            mHandler.postDelayed(mDue, Math.max(0, mRevertAtMs - System.currentTimeMillis()));
        }
    }

    private void persist() {
        ContextUtils.getAppSharedPreferences()
                .edit()
                .putLong(KEY_REVERT_AT, mRevertAtMs)
                .putBoolean(KEY_REVERT_TO, mRevertTo)
                .apply();
    }

    private void notifyObservers() {
        for (Observer o : mObservers) o.onTemporarySwitchChanged();
    }

    private static boolean isEnabled() {
        Profile profile = ProfileManager.getLastUsedRegularProfile();
        return profile != null && UserPrefs.get(profile).getBoolean(BravePref.SAWTUNAA_ENABLED);
    }

    private static void track(String event, String[] keys, String[] values) {
        String[] k = new String[keys.length + 1];
        String[] v = new String[values.length + 1];
        k[0] = "feature";
        v[0] = "sawtunaa";
        System.arraycopy(keys, 0, k, 1, keys.length);
        System.arraycopy(values, 0, v, 1, values.length);
        BrowtherAnalyticsBridge.trackWithProps(event, k, v);
    }
}
