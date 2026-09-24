// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

/** La réponse à un fait d'usage du filleul (`POST /v1/progress`). */
public final class ProgressOutcome {
    public static final class Progress {
        public final double current;
        public final double target;
        public final boolean validated;

        public Progress(double current, double target, boolean validated) {
            this.current = current;
            this.target = target;
            this.validated = validated;
        }
    }

    public final boolean counted;
    public final Progress progress;

    public ProgressOutcome(boolean counted, Progress progress) {
        this.counted = counted;
        this.progress = progress;
    }

    public static ProgressOutcome fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
        ReferralJson.Obj p = o.optObj("progress");
        return new ProgressOutcome(
                o.bool("counted"),
                p == null ? null : new Progress(p.number("current"), p.number("target"), p.bool("validated")));
    }
}
