// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;

/** Un palier du barème : à {@code at} invitations validées, {@code months} mois de bonus. */
public final class MilestoneBonus {
    public int at;
    public int months;

    public MilestoneBonus(int at, int months) {
        this.at = at;
        this.months = months;
    }

    public static MilestoneBonus fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
        return new MilestoneBonus(o.integer("at"), o.integer("months"));
    }

    public Map<String, Object> toJson() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("at", at);
        m.put("months", months);
        return m;
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof MilestoneBonus)) return false;
        MilestoneBonus o = (MilestoneBonus) other;
        return at == o.at && months == o.months;
    }

    @Override
    public int hashCode() {
        return Objects.hash(at, months);
    }

    @Override
    public String toString() {
        return "MilestoneBonus(at: " + at + ", months: " + months + ")";
    }
}
