// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

/** Ce que la connexion peut rendre, en clair pour l'écran. */
public final class ReferralAuthFailure extends Exception {
    public enum Kind {
        /** Réseau coupé, service injoignable. */
        UNREACHABLE,
        /** Code e-mail faux ou expiré. */
        BAD_CODE,
        /** Tout le reste (code à usage unique périmé, session illisible…). */
        FAILED
    }

    public final Kind kind;

    public ReferralAuthFailure(Kind kind) {
        // ⛔ Jamais le jeton, le code ni l'adresse dans le message : il peut finir dans un journal.
        super("compte dev&din : " + kind);
        this.kind = kind;
    }
}
