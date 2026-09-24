// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

/** L'identité envoyée à chaque appel (§ 7.1). */
public final class ReferralIdentityBody {
    public final String product;
    /** Compte si le produit en a un, identité d'appareil sinon. */
    public final String subjectRef;
    /** L'appareil, quand il diffère du sujet — sert la garde « même appareil ». */
    public final String deviceRef;
    public final ReferralPlatform platform;

    public ReferralIdentityBody(String product, String subjectRef, String deviceRef, ReferralPlatform platform) {
        this.product = product;
        this.subjectRef = subjectRef;
        this.deviceRef = deviceRef;
        this.platform = platform;
    }
}
