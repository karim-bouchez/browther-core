/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_ads;

import org.jni_zero.CalledByNative;
import org.jni_zero.JNINamespace;
import org.jni_zero.NativeMethods;

import org.chromium.build.annotations.NullMarked;

/**
 * Bridge JNI vers le client C++ {@code browther_ads::AdsClient} (régie pub
 * dev&din {@code ads-api.devndin.com}).
 *
 * <p>Serve en mode publisher <b>public</b> ({@code X-Publisher-Id} seul, aucun
 * secret embarqué — HMAC retiré 2026-07-07, l'anti-fraude vit côté serveur).
 * Seuls {@code id}, {@code imageUrl}, {@code ratio}, {@code locale} et
 * {@code showAdLabel} traversent le JNI (parité mojom {@code BrowtherAd}
 * desktop + port iOS {@code BrowtherServedAd}) ; le click URL et l'impression
 * token restent dans le client C++.
 *
 * <p>Sémantique (parité {@code components/browther_ads/ads_client.cc}) :
 * <ul>
 *   <li>{@link #serve(AdsCallback)} : {@code POST /v1/serve}, cache id→ad,
 *       best effort (tableau vide sur erreur réseau / 4xx / config absente).
 *   <li>{@link #markVisible(String)} : batch des impression tokens (≤ 50 toutes
 *       les ~10 s, idempotent par id) puis flush {@code /v1/track/impressions}.
 *   <li>{@link #getClickUrl(String)} : URL de click d'une pub servie (à ouvrir
 *       dans un nouvel onglet).
 * </ul>
 *
 * <p>Toutes les méthodes sont safe-by-default : config absente ⇒
 * {@link #isConfigured()} false ⇒ aucune requête réseau, bannière masquée.
 */
@JNINamespace("browther_ads::android")
@NullMarked
public final class BrowtherAdsBridge {
    private BrowtherAdsBridge() {}

    /**
     * Une pub servie exposée à l'UI (parité mojom {@code BrowtherAd}) ; le
     * click URL et l'impression token restent côté C++.
     */
    public static final class Ad {
        public final String id;
        public final String imageUrl;

        /**
         * Format renvoyé par le serve (ex {@code "3.2:1"}) — pilote
         * l'aspect-ratio côté UI (pas de valeur en dur, INTEGRATION.md § 3).
         * Chaîne vide si absent (fallback UI).
         */
        public final String ratio;

        /**
         * true = annonceur externe → label « Pub » obligatoire sur cette créa ;
         * false = house ad dev&din, pas de label. Décision par slide.
         */
        public final boolean showAdLabel;

        /**
         * Langue de la créa ({@code "fr"}/{@code "en"}/{@code "ar"}) renvoyée par
         * le serve ; chaîne vide pour une créa neutre. Pilote le sens de lecture
         * ({@code ar} → RTL) et l'attribut a11y de la bannière (parité desktop).
         */
        public final String locale;

        Ad(String id, String imageUrl, String ratio, String locale, boolean showAdLabel) {
            this.id = id;
            this.imageUrl = imageUrl;
            this.ratio = ratio;
            this.locale = locale;
            this.showAdLabel = showAdLabel;
        }
    }

    /** Callback du {@link #serve(AdsCallback)}, toujours appelé sur le UI thread. */
    public interface AdsCallback {
        /** Reçoit les pubs servies (jamais null ; vide ⇒ masquer la bannière). */
        void onAdsReceived(Ad[] ads);
    }

    /**
     * True si la régie est configurée (publisher id + url embarqués).
     * Sinon inutile de {@link #serve(AdsCallback)} : aucune requête ne partira.
     */
    public static boolean isConfigured() {
        return BrowtherAdsBridgeJni.get().isConfigured();
    }

    /**
     * Récupère jusqu'à 3 pubs pour le placement {@code browther-ntp-banner}.
     * {@code POST /v1/serve} côté natif, re-serve throttlé à ~10 min par
     * placement (cache C++ process-wide, INTEGRATION.md § 4). Best effort :
     * {@code callback} reçoit un tableau vide sur erreur / config absente
     * (jamais d'échec dur).
     */
    public static void serve(AdsCallback callback) {
        BrowtherAdsBridgeJni.get().serve(callback);
    }

    /**
     * Signale qu'une pub (par {@code id}) est devenue réellement visible.
     * Batch + flush différé des impression tokens, idempotent par {@code id}.
     */
    public static void markVisible(String id) {
        BrowtherAdsBridgeJni.get().markVisible(id);
    }

    /**
     * URL de click d'une pub servie (chaîne vide si {@code id} inconnu). À ouvrir
     * dans un nouvel onglet : l'API log le click puis 302 vers la destination.
     */
    public static String getClickUrl(String id) {
        return BrowtherAdsBridgeJni.get().getClickUrl(id);
    }

    @CalledByNative
    private static void onAdsServed(
            AdsCallback callback,
            String[] ids,
            String[] imageUrls,
            String[] ratios,
            String[] locales,
            boolean[] showAdLabels) {
        int count = Math.min(ids.length, imageUrls.length);
        Ad[] ads = new Ad[count];
        for (int i = 0; i < count; i++) {
            ads[i] =
                    new Ad(
                            ids[i],
                            imageUrls[i],
                            i < ratios.length ? ratios[i] : "",
                            i < locales.length ? locales[i] : "",
                            i < showAdLabels.length && showAdLabels[i]);
        }
        callback.onAdsReceived(ads);
    }

    @NativeMethods
    interface Natives {
        boolean isConfigured();

        void serve(AdsCallback callback);

        void markVisible(String id);

        String getClickUrl(String id);
    }
}
