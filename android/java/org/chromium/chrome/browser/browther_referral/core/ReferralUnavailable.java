// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

/** Le service injoignable, un 429, un 500 — ⛔ jamais une raison de bloquer. */
public final class ReferralUnavailable extends Exception {
    /** Le code HTTP, ou {@code null} si la réponse n'est jamais arrivée (ou était illisible). */
    public final Integer status;

    public ReferralUnavailable(Integer status) {
        super(status == null ? "service injoignable" : "service : HTTP " + status);
        this.status = status;
    }
}
