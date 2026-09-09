/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_ads;

import org.jni_zero.CalledByNative;
import org.jni_zero.JNINamespace;
import org.jni_zero.NativeMethods;

import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;

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
 *   <li>{@link #resolveClick(String)} : ce qu'un tap doit ouvrir — un onglet
 *       (destination site) ou le Play Store hors de Browther (fiche store),
 *       click compté au passage.
 * </ul>
 *
 * <p>Toutes les méthodes sont safe-by-default : config absente ⇒
 * {@link #isConfigured()} false ⇒ aucune requête réseau, bannière masquée.
 */
@JNINamespace("browther_ads::android")
@NullMarked
public final class BrowtherAdsBridge {
    /** Valeur de {@code store.kind} servie par la régie pour une fiche Play. */
    private static final String STORE_KIND_PLAY = "play";

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

    /** Ce qu'un tap sur une pub doit ouvrir, et comment. */
    public static final class ClickTarget {
        /** URL à ouvrir (jamais vide : un tap ne doit jamais ne rien faire). */
        public final String url;

        /**
         * true = {@link #url} est une fiche Play Store à ouvrir <b>hors</b> de
         * Browther (sinon on afficherait la page web du store dans un onglet) ;
         * false = un onglet est le bon comportement — c'est un navigateur.
         */
        public final boolean opensPlayStore;

        private ClickTarget(String url, boolean opensPlayStore) {
            this.url = url;
            this.opensPlayStore = opensPlayStore;
        }
    }

    /**
     * Résout la destination d'un tap sur la pub {@code id} <b>et compte le
     * click</b>, ou renvoie {@code null} si {@code id} est inconnu.
     *
     * <p>Deux chemins (ads/docs/INTEGRATION.md § 5) :
     *
     * <ul>
     *   <li><b>site</b> → {@code clickUrl} dans un onglet ; l'API log le click
     *       elle-même avant son 302, rien à compter ici ;
     *   <li><b>fiche store</b> → {@code targetUrl} (destination déjà résolue par
     *       la régie, UTM et click ID compris) ouvert hors de Browther, et
     *       {@code POST /v1/track/click} <b>avant</b> l'ouverture — sans lui, une
     *       install qui reviendrait avec ce click ID serait un « click inconnu ».
     * </ul>
     *
     * <p>⛔ Ne jamais ouvrir la destination sans passer par ici : c'est ce qui
     * garantit qu'un click servi hors du 302 est quand même compté.
     */
    public static @Nullable ClickTarget resolveClick(String id) {
        String[] target = BrowtherAdsBridgeJni.get().getClickTarget(id);
        String targetUrl = target.length > 0 ? target[0] : "";
        String storeKind = target.length > 1 ? target[1] : "";
        if (!targetUrl.isEmpty() && !storeKind.isEmpty()) {
            // Chemin natif : le click est à nous, compté ici — avant que l'Intent
            // ne bascule Browther en arrière-plan.
            BrowtherAdsBridgeJni.get().trackClick(id);
            // Seul Play sort de Browther. Un autre store (la régie n'en résout
            // aucun pour Android aujourd'hui) ouvre sa page dans un onglet
            // plutôt qu'un Intent voué à échouer — le click est déjà compté.
            return new ClickTarget(targetUrl, STORE_KIND_PLAY.equals(storeKind));
        }
        String clickUrl = getClickUrl(id);
        return clickUrl.isEmpty() ? null : new ClickTarget(clickUrl, false);
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

        String[] getClickTarget(String id);

        void trackClick(String id);
    }
}
