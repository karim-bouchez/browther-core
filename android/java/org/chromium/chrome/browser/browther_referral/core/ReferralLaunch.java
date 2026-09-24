// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

/**
 * Le parrainage existe-t-il dans CE binaire ? — l'interrupteur de lancement.
 *
 * <h3>Pourquoi un interrupteur, et pourquoi dans le CODE</h3>
 *
 * Le flow est ÉTEINT dans les builds du store tant que {@link #inStoreBuilds} vaut {@code false} —
 * une ligne, visible dans git, que Karim bascule le jour du lancement. Allumé ailleurs (builds de
 * dev), pour la recette.
 *
 * <p>⚠️ **Android n'a pas de vrai paiement** (`docs/PARRAINAGE.md` § 12.27 : Google Play n'ouvre pas
 * de compte marchand au Maroc) : la **porte factice** (`POST /v1/gift`) tient lieu de paiement.
 * Il n'y a donc pas de condition « paiement prêt » comme sur iOS — l'argument App Store « un
 * abonnement qui ne débloque rien = rejet » ne s'applique pas ici. Le seul verrou qui compte au
 * lancement est {@link #extrasReleased}, à basculer LE MÊME JOUR que les autres plateformes et que
 * le service (`announcementDeferred: false`).
 */
public final class ReferralLaunch {
    private ReferralLaunch() {}

    /** ⛔ Ne passer à {@code true} que le jour du lancement, sur décision de Karim. */
    public static final boolean inStoreBuilds = false;

    /**
     * ⚠️ **Sawtunaa est-il sorti de « encore en développement » ?** (§ 9) Le mois offert ne démarre
     * qu'à sa finalisation : l'annonce (écran 0), qui lance le compteur, attend ce jour-là. D'ici là
     * tout est ouvert (§ 12.11), et le reste du flow tourne — code, invitations, écran 6,
     * validation. ⛔ À basculer en même temps que le retrait de l'encadré « encore en développement »
     * de Sawtunaa, jamais avant — et le même jour qu'iOS, le desktop et le service.
     */
    public static final boolean extrasReleased = false;

    public static boolean isEnabled(boolean isStoreBuild) {
        if (!isStoreBuild) return true;
        return inStoreBuilds;
    }
}
