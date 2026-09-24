// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;

/** Une invitation, telle que le service la rend (§ 5.3). */
public final class InvitationItem {
    public String id;
    public InvitationStatus status;
    public String sentAt;
    public String installedAt;
    public String validatedAt;
    public int creditedMonths;
    /** Vrai quand elle a fait franchir un palier — la ligne ★ de l'écran 6. */
    public boolean milestone;
    /** En cours seulement : où en est le critère (« encore 2 jours », § 5.3). */
    public ValidationProgress progress;

    public InvitationItem(String id, InvitationStatus status) {
        this.id = id;
        this.status = status;
    }

    public static InvitationItem fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
        InvitationStatus status = InvitationStatus.fromRaw(o.string("status"));
        if (status == null) throw new ReferralJson.JsonException("statut d'invitation inconnu");
        InvitationItem item = new InvitationItem(o.string("id"), status);
        item.sentAt = o.optString("sentAt");
        item.installedAt = o.optString("installedAt");
        item.validatedAt = o.optString("validatedAt");
        item.creditedMonths = o.integer("creditedMonths");
        item.milestone = o.bool("milestone");
        ReferralJson.Obj progress = o.optObj("progress");
        item.progress = progress == null ? null : ValidationProgress.fromJson(progress);
        return item;
    }

    public Map<String, Object> toJson() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", id);
        m.put("status", status.rawValue);
        m.put("sentAt", sentAt);
        m.put("installedAt", installedAt);
        m.put("validatedAt", validatedAt);
        m.put("creditedMonths", creditedMonths);
        m.put("milestone", milestone);
        m.put("progress", progress == null ? null : progress.toJson());
        return m;
    }

    @Override
    public boolean equals(Object other) {
        return other instanceof InvitationItem && toJson().equals(((InvitationItem) other).toJson());
    }

    @Override
    public int hashCode() {
        return toJson().hashCode();
    }
}
