// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

/**
 * Où se pose un toast du parrainage : en bas, ou en haut — `private/docs/PARRAINAGE.md` § 11.6,
 * port de `BrowtherReferral/ReferralToastPlacement.swift`. Jumeau de l'ordinateur :
 * `core/toastPlacement.ts`.
 *
 * <h2>Pourquoi deux places</h2>
 *
 * <ul>
 *   <li>**En bas, par défaut** — c'est là que Browther les a toujours posés, sur le navigateur comme
 *       sur les écrans à en-tête (Parrainage, compte, Réglages), dont le bas est libre. ⚠️ C'est
 *       l'inverse de Fajrunaa, qui partait du haut et a dû descendre sur ces écrans-là
 *       (`fajrunaa/lib/toastPlacement.ts`) : le défaut qu'il corrigeait (un toast sur le bouton
 *       retour) n'a jamais existé ici.
 *   <li>**En haut dès qu'une feuille ou une fenêtre du parrainage est ouverte** : leur bouton
 *       principal est en bas, et un toast l'aurait recouvert — d'autant qu'un toast qui annonce un
 *       changement d'état RESTE jusqu'à ce qu'on le ferme (Karim, 2026-10-08).
 * </ul>
 *
 * <p>⚠️ Une liste de cas, pas « partout sauf » : rien d'autre ne déplace un toast.
 */
public enum ReferralToastPlacement {
    TOP,
    BOTTOM;

    public static ReferralToastPlacement resolve(boolean sheetOrFlowOpen) {
        return sheetOrFlowOpen ? TOP : BOTTOM;
    }
}
