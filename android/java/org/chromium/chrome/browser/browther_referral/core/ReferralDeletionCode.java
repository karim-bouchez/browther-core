// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.Objects;

/**
 * Le code de confirmation de la suppression est-il parti ? — `POST /api/auth/send-deletion-otp`.
 * {@link #destination} = l'adresse MASQUÉE (« k****@gmail.com »), telle que l'auth-service la rend.
 */
public final class ReferralDeletionCode {
    public enum Kind {
        SENT,
        UNREACHABLE,
        FAILED
    }

    public final Kind kind;

    /** {@link Kind#SENT} seulement ; {@code null} sinon. */
    public final String destination;

    private ReferralDeletionCode(Kind kind, String destination) {
        this.kind = kind;
        this.destination = destination;
    }

    public static ReferralDeletionCode sent(String destination) {
        return new ReferralDeletionCode(Kind.SENT, destination);
    }

    public static ReferralDeletionCode unreachable() {
        return new ReferralDeletionCode(Kind.UNREACHABLE, null);
    }

    public static ReferralDeletionCode failed() {
        return new ReferralDeletionCode(Kind.FAILED, null);
    }

    /** La règle. {@code reply == null} = aucune réponse. */
    public static ReferralDeletionCode fromReply(ReferralAuthReply reply) {
        if (reply == null) return unreachable();
        String destination = ReferralAuthReply.string(reply.object(), "destination");
        if (reply.status == 200 && destination != null && !destination.isEmpty()) {
            return sent(destination);
        }
        return failed();
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof ReferralDeletionCode)) return false;
        ReferralDeletionCode o = (ReferralDeletionCode) other;
        return kind == o.kind && Objects.equals(destination, o.destination);
    }

    @Override
    public int hashCode() {
        return Objects.hash(kind, destination);
    }
}
