// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.Objects;

/** La réponse à un code saisi : accepté (et ce qu'il offre), ou refusé (et pourquoi). */
public final class RedeemOutcome {
    public final boolean accepted;
    public final int monthsGranted;
    public final String coveredUntil;
    /** {@code null} quand le code est accepté. */
    public final RedeemRefusal refusal;

    private RedeemOutcome(boolean accepted, int monthsGranted, String coveredUntil, RedeemRefusal refusal) {
        this.accepted = accepted;
        this.monthsGranted = monthsGranted;
        this.coveredUntil = coveredUntil;
        this.refusal = refusal;
    }

    public static RedeemOutcome accepted(int monthsGranted, String coveredUntil) {
        return new RedeemOutcome(true, monthsGranted, coveredUntil, null);
    }

    public static RedeemOutcome refused(RedeemRefusal refusal) {
        return new RedeemOutcome(false, 0, null, refusal);
    }

    public static RedeemOutcome fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
        if (o.bool("accepted")) {
            Integer months = o.optInteger("monthsGranted");
            return accepted(months == null ? 0 : months, o.optString("coveredUntil"));
        }
        // Un refus inconnu se lit comme « ce code ne correspond à personne ».
        RedeemRefusal refusal = RedeemRefusal.fromRaw(o.optString("reason"));
        return refused(refusal == null ? RedeemRefusal.UNKNOWN_CODE : refusal);
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof RedeemOutcome)) return false;
        RedeemOutcome o = (RedeemOutcome) other;
        return accepted == o.accepted
                && monthsGranted == o.monthsGranted
                && Objects.equals(coveredUntil, o.coveredUntil)
                && refusal == o.refusal;
    }

    @Override
    public int hashCode() {
        return Objects.hash(accepted, monthsGranted, coveredUntil, refusal);
    }
}
