// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

/**
 * `POST /v1/transfer` — l'appareil REJOINT le compte (fusion, brief B ter) : un seul code, un seul
 * compteur, rien de perdu. Le statut rendu est celui de la CIBLE, dans tous les cas.
 */
public final class TransferOutcome {
    public final Boolean transferred;
    /** `renamed` · `merged` · `unknown_source` · `same_subject` */
    public final String reason;
    public final ReferralStatus status;

    public TransferOutcome(Boolean transferred, String reason, ReferralStatus status) {
        this.transferred = transferred;
        this.reason = reason;
        this.status = status;
    }

    public static TransferOutcome fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
        return new TransferOutcome(
                o.optBool("transferred"), o.optString("reason"), ReferralStatus.fromJson(o.obj("status")));
    }
}
