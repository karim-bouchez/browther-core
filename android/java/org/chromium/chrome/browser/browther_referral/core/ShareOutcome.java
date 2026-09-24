// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

/**
 * Les 3 jours conditionnels du moment « partage » (§ 4). ⛔ Ne se disent qu'APRÈS coup, et seulement
 * s'ils ont été offerts.
 */
public final class ShareOutcome {
    public static final class Grace {
        public final boolean granted;
        public final String coveredUntil;

        public Grace(boolean granted, String coveredUntil) {
            this.granted = granted;
            this.coveredUntil = coveredUntil;
        }
    }

    public final Grace grace;

    public ShareOutcome(Grace grace) {
        this.grace = grace;
    }

    public static ShareOutcome fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
        ReferralJson.Obj grace = o.obj("grace");
        return new ShareOutcome(new Grace(grace.bool("granted"), grace.optString("coveredUntil")));
    }
}
