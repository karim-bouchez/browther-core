/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_analytics;

import android.content.Context;

import io.sentry.Sentry;
import io.sentry.SentryEvent;
import io.sentry.android.core.SentryAndroid;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;

import java.util.ArrayList;
import java.util.Locale;
import java.util.Map;

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
                        // Dernier point de passage avant l'envoi réseau : rien ne
                        // sort sans traverser ce filtre. Cf. scrubNavigationData.
                        options.setBeforeSend(
                                (event, hint) -> {
                                    scrubNavigationData(event);
                                    return event;
                                });
                    });
            Sentry.setTag("os", "android");
            sStarted = true;
            Log.i(TAG, "Sentry démarré");
        } catch (Throwable t) {
            // Sentry ne doit jamais faire crasher l'app au démarrage.
            Log.e(TAG, "Sentry init failed", t);
        }
    }

    /**
     * Retire d'un event Sentry tout ce qui pourrait porter une adresse visitée.
     *
     * <p>Browther promet publiquement de ne jamais transmettre les URL visitées
     * ({@code docs/ANALYTICS.md}), avec une seule exception : le bouton
     * « Signaler ce site », où l'utilisateur choisit d'envoyer, voit le domaine
     * avant de cliquer, et où seul l'eTLD+1 part. Tout le reste doit être muet.
     *
     * <p>Android n'a pas le trou trouvé sur iOS — la capture des requêtes
     * échouées y passe par l'intégration OkHttp, que Chromium n'utilise pas.
     * Le filtre est là quand même, et c'est délibéré : sur iOS la fuite venait
     * d'un DÉFAUT du SDK, pas d'un choix (cf. BROWTHER-28). Un défaut peut
     * apparaître ici à la prochaine montée de version, et personne ne relira
     * cette classe à ce moment-là. Aligner les trois plateformes sur le même
     * garde-fou coûte moins cher que de se demander, à chaque bump, laquelle
     * était protégée.
     *
     * <p>Volontairement grossier : on préfère perdre du contexte de debug que
     * laisser filer une adresse. C'est la stacktrace qui rend un crash
     * exploitable, pas l'URL.
     */
    private static void scrubNavigationData(SentryEvent event) {
        event.setRequest(null);

        Map<String, String> tags = event.getTags();
        if (tags != null) {
            // Copie des clés avant de retirer : on modifie la map d'origine.
            for (String key : new ArrayList<>(tags.keySet())) {
                if (looksLikeUrl(tags.get(key))) {
                    event.removeTag(key);
                }
            }
        }

        Map<String, Object> extras = event.getExtras();
        if (extras != null) {
            for (String key : new ArrayList<>(extras.keySet())) {
                Object value = extras.get(key);
                // Une valeur non-textuelle ne peut pas porter d'URL : on la garde.
                if (value instanceof String && looksLikeUrl((String) value)) {
                    event.removeExtra(key);
                }
            }
        }
    }

    /** Heuristique délibérément large : au moindre doute, on jette. */
    private static boolean looksLikeUrl(@Nullable String value) {
        if (value == null) {
            return false;
        }
        String lowered = value.toLowerCase(Locale.ROOT);
        return lowered.contains("http://") || lowered.contains("https://");
    }
}
