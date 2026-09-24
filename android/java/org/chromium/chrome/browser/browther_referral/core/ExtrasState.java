// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.time.Instant;
import java.util.Collections;
import java.util.Objects;

/**
 * L'état que montre le composant « fonctionnalités » (§ 2.2) : Offert 1 mois · Jusqu'au … · En
 * pause dans N j · En pause · Inclus.
 */
public final class ExtrasState {
    public enum Kind {
        OFFERED,
        UNTIL,
        SOON,
        PAUSED,
        INCLUDED
    }

    public final Kind kind;
    /** {@code UNTIL} seulement. */
    public final Instant until;
    /** {@code SOON} seulement. */
    public final int days;

    private ExtrasState(Kind kind, Instant until, int days) {
        this.kind = kind;
        this.until = until;
        this.days = days;
    }

    public static ExtrasState offered() {
        return new ExtrasState(Kind.OFFERED, null, 0);
    }

    public static ExtrasState until(Instant until) {
        return new ExtrasState(Kind.UNTIL, until, 0);
    }

    public static ExtrasState soon(int days) {
        return new ExtrasState(Kind.SOON, null, days);
    }

    public static ExtrasState paused() {
        return new ExtrasState(Kind.PAUSED, null, 0);
    }

    public static ExtrasState included() {
        return new ExtrasState(Kind.INCLUDED, null, 0);
    }

    /** L'état du MOMENT, pour la liste du (i) de l'écran 6. */
    public ExtrasState(ReferralStatus status, AccessState access, Instant now) {
        ExtrasState state;
        Integer left = access.daysLeft(now);
        if (access.lifetime || status.subscription.active) {
            state = included();
        } else if (access.isPaused(now)) {
            state = paused();
        } else if (left != null && left <= Collections.max(ReferralPrompt.reminderStages)) {
            state = soon(left);
        } else if (access.until != null && !access.beforeTrial) {
            state = until(access.until);
        } else {
            state = offered();
        }
        this.kind = state.kind;
        this.until = state.until;
        this.days = state.days;
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof ExtrasState)) return false;
        ExtrasState o = (ExtrasState) other;
        return kind == o.kind && days == o.days && Objects.equals(until, o.until);
    }

    @Override
    public int hashCode() {
        return Objects.hash(kind, until, days);
    }

    @Override
    public String toString() {
        return kind + (kind == Kind.SOON ? "(" + days + ")" : until == null ? "" : "(" + until + ")");
    }
}
