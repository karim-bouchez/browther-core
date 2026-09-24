// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Objects;

/** Où en est le critère d'une invitation en cours (« encore 2 jours », § 5.3). */
public final class ValidationProgress {
    public double current;
    public double target;
    public boolean met;

    public ValidationProgress(double current, double target, boolean met) {
        this.current = current;
        this.target = target;
        this.met = met;
    }

    public static ValidationProgress fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
        return new ValidationProgress(o.number("current"), o.number("target"), o.bool("met"));
    }

    public Map<String, Object> toJson() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("current", current);
        m.put("target", target);
        m.put("met", met);
        return m;
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof ValidationProgress)) return false;
        ValidationProgress o = (ValidationProgress) other;
        return current == o.current && target == o.target && met == o.met;
    }

    @Override
    public int hashCode() {
        return Objects.hash(current, target, met);
    }
}
