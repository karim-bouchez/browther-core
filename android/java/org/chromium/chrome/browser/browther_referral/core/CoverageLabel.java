// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.time.Instant;
import java.util.Objects;

/**
 * Ce que l'écran Parrainage dit de la couverture — une étiquette pour CHAQUE cas connu, « avant
 * l'annonce » compris (§ 12.11 : sinon l'écran reste en chargement pour tout nouveau venu).
 *
 * <p>L'énumération Swift à valeurs associées devient {@link Kind} + les champs du cas ({@code renews}
 * et {@code until} pour {@code PAID}, {@code until} pour {@code UNTIL}).
 */
public final class CoverageLabel {
    public enum Kind {
        LIFETIME,
        PAID,
        PAUSED,
        UNTIL,
        OFFERED
    }

    public final Kind kind;
    public final boolean renews;
    public final Instant until;

    private CoverageLabel(Kind kind, boolean renews, Instant until) {
        this.kind = kind;
        this.renews = renews;
        this.until = until;
    }

    public static CoverageLabel lifetime() {
        return new CoverageLabel(Kind.LIFETIME, false, null);
    }

    public static CoverageLabel paid(boolean renews, Instant until) {
        return new CoverageLabel(Kind.PAID, renews, until);
    }

    public static CoverageLabel paused() {
        return new CoverageLabel(Kind.PAUSED, false, null);
    }

    public static CoverageLabel until(Instant until) {
        return new CoverageLabel(Kind.UNTIL, false, until);
    }

    public static CoverageLabel offered() {
        return new CoverageLabel(Kind.OFFERED, false, null);
    }

    public CoverageLabel(ReferralStatus status, AccessState access, Instant now) {
        CoverageLabel label;
        if (access.lifetime) {
            label = lifetime();
        } else if (status.subscription.active) {
            label =
                    paid(
                            status.subscription.willRenew,
                            ReferralDate.parse(status.subscription.until));
        } else if (access.isPaused(now)) {
            label = paused();
        } else if (access.until != null && !access.beforeTrial) {
            label = until(access.until);
        } else {
            label = offered();
        }
        this.kind = label.kind;
        this.renews = label.renews;
        this.until = label.until;
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof CoverageLabel)) return false;
        CoverageLabel o = (CoverageLabel) other;
        return kind == o.kind && renews == o.renews && Objects.equals(until, o.until);
    }

    @Override
    public int hashCode() {
        return Objects.hash(kind, renews, until);
    }

    @Override
    public String toString() {
        return kind + (until == null ? "" : "(" + until + ")");
    }
}
