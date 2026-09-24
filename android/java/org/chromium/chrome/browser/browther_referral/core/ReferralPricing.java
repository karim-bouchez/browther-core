// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

/**
 * Les prix — ⚠️ ce ne sont pas des textes traduisibles. Sur Android, l'écran 7 les affiche tels
 * quels : il n'y a pas de magasin pour rendre un prix localisé (porte factice, § 12.27).
 *
 * <p>🔴 **UN seul prix, partout : 2,99 € / 29,99 €** (§ 2.1 n° 4). Changer un prix ici suppose de
 * changer les stores ET Polar le même jour.
 */
public final class ReferralPricing {
    private ReferralPricing() {}

    /** ⚠️ Espace INSÉCABLE entre le montant et « € » : ils ne se coupent jamais en fin de ligne (§ 12.26). */
    public static final String monthly = "2,99 €";

    public static final String yearly = "29,99 €";
    /** Douze mois au tarif mensuel — le prix barré. */
    public static final String yearlyStruck = "35,88 €";
    /** Ce que l'annuel revient par mois — « soit 2,50 € par mois ». */
    public static final String yearlyPerMonth = "2,50 €";
    /** Le badge « 2 mois offerts ». */
    public static final int yearlyFreeMonths = 2;
}
