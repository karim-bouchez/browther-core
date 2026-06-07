/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_analytics;

import org.jni_zero.JNINamespace;
import org.jni_zero.NativeMethods;

import org.chromium.build.annotations.NullMarked;

/**
 * Bridge JNI vers le service C++ {@code browther_analytics::BrowtherAnalyticsService}.
 *
 * <p>Le service C++ est initialisé dans {@code PreMainMessageLoopRun} (cross-plateforme)
 * et gère déjà le PostHogClient HTTP, le StatsClient (POST /api/stats/ingest) et
 * la persistance des compteurs pending dans local_state.
 *
 * <p>Ce bridge sert uniquement à fire des events depuis les flows Java :
 * {@code onboarding_completed} (WelcomeOnboardingActivity), {@code default_browser_set}
 * (BraveSetDefaultBrowserUtils), {@code feature_toggled} (Sawtunaa Android, à venir).
 *
 * <p>Toutes les méthodes sont safe-by-default : si le service C++ n'est pas encore
 * init ou si le consent ({@code kP3AEnabled} / {@code kMetricsReportingEnabled}) est
 * désactivé, les appels sont no-op côté natif.
 */
@JNINamespace("browther_analytics::android")
@NullMarked
public final class BrowtherAnalyticsBridge {
    private BrowtherAnalyticsBridge() {}

    /** Track un event sans properties. No-op si service non init ou consent off. */
    public static void track(String eventName) {
        BrowtherAnalyticsBridgeJni.get().track(eventName);
    }

    /**
     * Track un event avec un sac de properties string → string. Les propriétés
     * sont sérialisées en {@code base::DictValue} côté C++. Tableaux de même
     * longueur, non null (utiliser {@link #track(String)} pour pas de props).
     */
    public static void trackWithProps(String eventName, String[] keys, String[] values) {
        if (keys.length == 0) {
            BrowtherAnalyticsBridgeJni.get().track(eventName);
            return;
        }
        if (keys.length != values.length) {
            throw new IllegalArgumentException(
                    "keys.length=" + keys.length + " != values.length=" + values.length);
        }
        BrowtherAnalyticsBridgeJni.get().trackWithProps(eventName, keys, values);
    }

    /**
     * Incrémente le compteur cumulatif {@code music_seconds} publié sur
     * browther.devndin.com via {@code /api/stats/ingest} (parité avec iOS
     * {@code BrowtherStatsReporter.flushSawtunaaSeconds}). No-op si le
     * service C++ n'est pas init ou si le consent stats est désactivé.
     */
    public static void incrementMusicSeconds(int delta) {
        BrowtherAnalyticsBridgeJni.get().incrementMusicSeconds(delta);
    }

    /**
     * Incrémente le compteur cumulatif {@code persons_blurred} (Basarunaa
     * Android). À appeler depuis le pipeline de détection quand des personnes
     * sont effectivement floutées. No-op si service non init / consent off.
     */
    public static void incrementPersonsBlurred(int delta) {
        BrowtherAnalyticsBridgeJni.get().incrementPersonsBlurred(delta);
    }

    /**
     * Lit le compteur cumulatif local de secondes de musique retirées
     * ({@code kStatsMusicSecondsTotal} dans local_state). Utilisé par la NTP
     * pour afficher la stat "Music removed". Retourne 0 si le local_state
     * n'est pas encore prêt.
     */
    public static long getMusicSecondsTotal() {
        return BrowtherAnalyticsBridgeJni.get().getMusicSecondsTotal();
    }

    /**
     * Lit le compteur cumulatif local de personnes floutées
     * ({@code kStatsPersonsBlurredTotal}). Utilisé par la NTP.
     */
    public static long getPersonsBlurredTotal() {
        return BrowtherAnalyticsBridgeJni.get().getPersonsBlurredTotal();
    }

    /**
     * True si l'user a accepté les "product insights" (PostHog).
     * Lit la pref upstream {@code kP3AEnabled} côté C++.
     */
    public static boolean isPostHogEnabled() {
        return BrowtherAnalyticsBridgeJni.get().isPostHogEnabled();
    }

    /**
     * True si l'user a accepté les "crash reports" (Sentry).
     * Lit la pref upstream {@code kMetricsReportingEnabled} côté C++.
     */
    public static boolean isMetricsReportingEnabled() {
        return BrowtherAnalyticsBridgeJni.get().isMetricsReportingEnabled();
    }

    @NativeMethods
    interface Natives {
        void track(String eventName);

        void trackWithProps(String eventName, String[] keys, String[] values);

        void incrementMusicSeconds(int delta);

        void incrementPersonsBlurred(int delta);

        long getMusicSecondsTotal();

        long getPersonsBlurredTotal();

        boolean isPostHogEnabled();

        boolean isMetricsReportingEnabled();
    }
}
