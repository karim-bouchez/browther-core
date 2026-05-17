/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_analytics;

import android.content.Context;

import io.sentry.Sentry;
import io.sentry.android.core.SentryAndroid;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;

/**
 * Init Sentry-Android pour Browther.
 *
 * <p>Appelé au plus tôt dans {@link
 * org.chromium.chrome.browser.BraveApplicationImplBase#onCreate()} (browser
 * process uniquement) pour capturer aussi les crashes pendant l'init Chromium
 * (avant que le service C++ {@code BrowtherAnalyticsService} ne soit prêt).
 *
 * <p>Périmètre minimal aligné sur iOS (cf.
 * {@code BrowtherAnalyticsService.swift#startSentry}) : crashes Java + ANR,
 * pas de breadcrumbs UI, pas de tracing perf, pas de PII.
 *
 * <p>Consent : pour l'instant Sentry démarre dès que la DSN n'est pas vide.
 * Le default Browther de {@code kMetricsReportingEnabled} est {@code true}
 * (opt-out, cf. {@code brave_local_state_prefs.cc}). En Batch 2.5 on rajoutera
 * une lecture SharedPreferences pour gater l'init dès le launch et un
 * {@code Sentry.close()} quand l'user désactive le toggle dans les Settings.
 */
@NullMarked
public final class BrowtherSentry {
    private static final String TAG = "BrowtherSentry";
    private static boolean sStarted;

    private BrowtherSentry() {}

    /** Initialise Sentry si la DSN est configurée. Idempotent. */
    public static void initialize(Context appContext) {
        if (sStarted) {
            return;
        }
        final String dsn = BrowtherAnalyticsConfig.SENTRY_DSN;
        if (dsn.isEmpty()) {
            Log.i(TAG, "DSN vide — Sentry désactivé (gen-analytics-config.sh pas lancé ?)");
            return;
        }
        try {
            SentryAndroid.init(
                    appContext,
                    options -> {
                        options.setDsn(dsn);
                        // Crashes only : pas de session tracking, pas de perf, pas de PII.
                        options.setSendDefaultPii(false);
                        options.setAttachStacktrace(true);
                        options.setTracesSampleRate(0.0);
                        options.setEnableAutoSessionTracking(false);
                        // Le release name sera affiné en Batch 2.5 (via BuildConfig).
                        options.setRelease("browther-android");
                    });
            Sentry.setTag("os", "android");
            sStarted = true;
            Log.i(TAG, "Sentry démarré");
        } catch (Throwable t) {
            // Sentry ne doit jamais faire crasher l'app au démarrage.
            Log.e(TAG, "Sentry init failed", t);
        }
    }
}
