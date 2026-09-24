// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

/**
 * `POST /v1/gift` — la porte factice du paiement Android (`docs/PARRAINAGE.md` § 12.27) : Google
 * Play n'ouvre pas de compte marchand au Maroc. **1 mois, UNE fois par sujet**, quelle que soit la
 * formule choisie ; un 2ᵉ appel (ou un accès à vie) rend {@code granted: false} — l'app remercie
 * quand même, sans cadeau. ⛔ Ce n'est pas un paiement : `subscription.active` reste faux.
 */
public final class GiftOutcome {
    public final boolean granted;
    /** La fin de la couverture après le cadeau — {@code null} si rien n'a été offert. */
    public final String coveredUntil;

    public GiftOutcome(boolean granted, String coveredUntil) {
        this.granted = granted;
        this.coveredUntil = coveredUntil;
    }

    public static GiftOutcome fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
        return new GiftOutcome(o.bool("granted"), o.optString("coveredUntil"));
    }
}
