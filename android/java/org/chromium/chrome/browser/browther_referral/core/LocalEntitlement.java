// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.time.Instant;

/**
 * Ce que le magasin dit de l'abonnement, sur CET appareil. ⚠️ Android n'a pas de paiement (§ 12.27,
 * porte factice) : le type existe pour que {@link ReferralStatus#merging} reste le même partout, le
 * jour où un vrai paiement arrivera.
 */
public final class LocalEntitlement {
    public final boolean active;
    public final boolean willRenew;
    public final Instant until;

    public LocalEntitlement(boolean active, boolean willRenew, Instant until) {
        this.active = active;
        this.willRenew = willRenew;
        this.until = until;
    }
}
