// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.Locale;
import java.util.Objects;

/**
 * Comment NOMMER le compte à l'écran. « Masquer mon adresse » d'Apple donne un relais illisible
 * (`x7k2…@privaterelay.appleid.com`) : on dit « avec Apple », ce qui rappelle aussi par où se
 * reconnecter — c'est le piège des deux comptes (§ 7.1 : Apple masqué sur un appareil, Google sur
 * l'autre).
 */
public final class ReferralAccountLabel {
    public enum Kind {
        /** Une adresse lisible : on l'affiche ({@link #email}). */
        EMAIL,
        /** Le relais d'Apple : « avec Apple ». */
        APPLE,
        /** Pas d'adresse connue : « Connecté ». */
        UNKNOWN
    }

    static final String appleRelay = "@privaterelay.appleid.com";

    public final Kind kind;

    /** {@link Kind#EMAIL} seulement ; {@code null} sinon. */
    public final String email;

    private ReferralAccountLabel(Kind kind, String email) {
        this.kind = kind;
        this.email = email;
    }

    public static ReferralAccountLabel email(String email) {
        return new ReferralAccountLabel(Kind.EMAIL, email);
    }

    public static ReferralAccountLabel apple() {
        return new ReferralAccountLabel(Kind.APPLE, null);
    }

    public static ReferralAccountLabel unknown() {
        return new ReferralAccountLabel(Kind.UNKNOWN, null);
    }

    public static ReferralAccountLabel of(ReferralAccount account) {
        String email = account == null ? null : account.email;
        if (email == null || email.isEmpty()) return unknown();
        return email.toLowerCase(Locale.ROOT).endsWith(appleRelay) ? apple() : email(email);
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof ReferralAccountLabel)) return false;
        ReferralAccountLabel o = (ReferralAccountLabel) other;
        return kind == o.kind && Objects.equals(email, o.email);
    }

    @Override
    public int hashCode() {
        return Objects.hash(kind, email);
    }
}
