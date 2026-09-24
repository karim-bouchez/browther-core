// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

/**
 * Ce que Browther met dans le dispositif — `docs/PARRAINAGE.md` § 9 (ligne Browther, tranchée le
 * 2026-09-11 puis le 2026-09-22 avec Karim).
 *
 * <p>⭐ **C'est le SEUL endroit où la liste vit** ({@link EssentialFeature}, {@link ExtraFeature}).
 * Les écrans 0, 1, 2 et 7 affichent le même composant « fonctionnalités » avec l'état qui va ; la
 * garde de l'app lit {@link ExtraFeature}. ⛔ Ne jamais recopier un libellé ou une icône dans un
 * écran.
 *
 * <p>🔴 **Basarunaa (le floutage) ne se met JAMAIS en pause** (§ 11.2, arbitré le 2026-09-11) : il
 * est « disponible, pour toujours ». Seul Sawtunaa (le retrait de la musique) est supplémentaire —
 * et il tourne en local, à coût marginal nul : « à vie » tient (§ 5.1).
 */
public final class ReferralProduct {
    private ReferralProduct() {}

    /** La clé du produit côté service (⛔ jamais affichée). */
    public static final String key = "browther";

    /**
     * L'adresse du service — ⛔ jamais une adresse de beta en dur ici : il n'y a qu'un service, et la
     * recette y pose ses états par un jeton.
     */
    public static final String serviceURL = "https://referral.devndin.com";

    /** Le site : repli du message partagé quand le lien traqué manque encore. */
    public static final String siteURL = "https://browther.devndin.com";

    // MARK: - Le critère de validation (§ 5.2, § 9)

    /**
     * 🔴 **Doublon commenté du service** (`referral/src/domain/products.ts`) — à garder identique.
     * Tranché le 2026-09-22 (Karim : « validé quand le filleul a passé Browther en navigateur par
     * défaut ») : **3 journées distinctes où Browther, navigateur par défaut, a chargé une vraie
     * page**. ⛔ Le défaut SEUL se ferait en dix secondes (installer, cocher, revenir en arrière) :
     * § 5.2, il faut un geste ET une durée.
     */
    public static final String validationEvent = "default_browser_day";

    /** Ne sert qu'aux TEXTES (« 3 jours ») : la progression affichée est celle que le service renvoie. */
    public static final int validationTargetDays = 3;
}
