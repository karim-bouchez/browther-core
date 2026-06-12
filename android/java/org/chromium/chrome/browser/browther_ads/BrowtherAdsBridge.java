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
 * <p>Le serve est <b>signé HMAC-SHA256 côté natif</b> : le secret publisher
 * (embarqué dans {@code ads_config.h}) ne touche jamais le Java. Seuls
 * {@code id} + {@code imageUrl} d'une pub traversent le JNI (parité mojom
 * {@code BrowtherAd} desktop + port iOS {@code BrowtherServedAd}) ; le click URL
 * et l'impression token restent dans le client C++.
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
     * Une pub servie exposée à l'UI. Seuls {@code id} + {@code imageUrl}
     * traversent le JNI (parité mojom {@code BrowtherAd}).
     */
    public static final class Ad {
        public final String id;
        public final String imageUrl;

        Ad(String id, String imageUrl) {
            this.id = id;
            this.imageUrl = imageUrl;
        }
    }

    /** Callback du {@link #serve(AdsCallback)}, toujours appelé sur le UI thread. */
    public interface AdsCallback {
        /** Reçoit les pubs servies (jamais null ; vide ⇒ masquer la bannière). */
        void onAdsReceived(Ad[] ads);
    }

    /**
     * True si la régie est configurée (publisher id + secret + url embarqués).
     * Sinon inutile de {@link #serve(AdsCallback)} : aucune requête ne partira.
     */
    public static boolean isConfigured() {
        return BrowtherAdsBridgeJni.get().isConfigured();
    }

    /**
     * Récupère jusqu'à 3 pubs pour le placement {@code browther-ntp-banner}.
     * {@code POST /v1/serve} signé HMAC côté natif. Best effort : {@code callback}
     * reçoit un tableau vide sur erreur / config absente (jamais d'échec dur).
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
    private static void onAdsServed(AdsCallback callback, String[] ids, String[] imageUrls) {
        int count = Math.min(ids.length, imageUrls.length);
        Ad[] ads = new Ad[count];
        for (int i = 0; i < count; i++) {
            ads[i] = new Ad(ids[i], imageUrls[i]);
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
