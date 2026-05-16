/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_analytics;

import org.jni_zero.JNINamespace;
import org.jni_zero.NativeMethods;

import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;

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

        boolean isPostHogEnabled();

        boolean isMetricsReportingEnabled();
    }
}
