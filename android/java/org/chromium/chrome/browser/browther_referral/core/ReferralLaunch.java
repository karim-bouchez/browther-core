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
    // ✅ Allumé le 2026-09-27 (décision Karim du 2026-09-25, private/docs/PARRAINAGE.md § 7.8),
    // après le premier build Chromium qui compile et la recette sur le Huawei P20. Le mois offert
    // lié à Sawtunaa, lui, reste en sommeil : `extrasReleased` ci-dessous.
    public static final boolean inStoreBuilds = true;

    /**
     * ⚠️ **Sawtunaa est-il sorti de « encore en développement » ?** (§ 9) Le mois offert ne démarre
     * qu'à sa finalisation : l'annonce (écran 0), qui lance le compteur, attend ce jour-là. D'ici là
     * tout est ouvert (§ 12.11), et le reste du flow tourne — code, invitations, écran 6,
     * validation. ⛔ À basculer en même temps que le retrait de l'encadré « encore en développement »
     * de Sawtunaa, jamais avant — et le même jour qu'iOS, le desktop et le service.
     */
    public static final boolean extrasReleased = false;

    /**
     * ⏸ **Le compte dev&din facultatif est ÉTEINT dans les builds du store** (§ 7.1 du doc commun,
     * porté sur Android le 2026-10-07) — alors que le parrainage, lui, y est allumé ({@link
     * #inStoreBuilds}). Il n'a jamais tourné sur un appareil : il attend la recette de Karim ET la
     * mise à jour de la déclaration « Sécurité des données » de Google Play (une adresse e-mail
     * devient collectée — un écart entre la fiche et le binaire vaut un retrait). Hors store (builds
     * de dev) : allumé, pour la recette.
     *
     * <p>Éteint, RIEN du compte n'existe : ni l'icône de l'en-tête, ni les rangées des onglets,
     * ni la ligne « Mon compte » des Paramètres, et un compte rangé n'est pas relu — le sujet
     * reste l'appareil.
     *
     * <p>🔴 ⛔ Jamais {@code true} sans la SUPPRESSION du compte dans l'app (Google l'exige dès
     * qu'une app permet d'en créer un, comme Apple 5.1.1(v)) : elle est sur la page du compte
     * (`ReferralAccountDeletion`). ⛔ Une ligne du code, visible dans git, pas un réglage distant —
     * même raison que {@link #inStoreBuilds}. Même interrupteur que `ACCOUNT_IN_STORE_BUILDS` de
     * `fajrunaa/lib/referral/account.ts`.
     */
    public static final boolean accountInStoreBuilds = false;

    public static boolean isEnabled(boolean isStoreBuild) {
        if (!isStoreBuild) return true;
        return inStoreBuilds;
    }

    /**
     * Le compte existe-t-il dans CE binaire ? ⚠️ Jamais sans le parrainage lui-même : il ne porte
     * que lui.
     *
     * @param referralEnabled {@link #isEnabled} pour ce même binaire.
     */
    public static boolean isAccountEnabled(boolean isStoreBuild, boolean referralEnabled) {
        if (!referralEnabled) return false;
        if (!isStoreBuild) return true;
        return accountInStoreBuilds;
    }
}
