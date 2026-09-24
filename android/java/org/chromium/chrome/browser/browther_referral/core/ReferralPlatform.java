// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

public enum ReferralPlatform {
    IOS("ios"),
    ANDROID("android"),
    WEB("web"),
    DESKTOP("desktop");

    public final String rawValue;

    ReferralPlatform(String rawValue) {
        this.rawValue = rawValue;
    }

    /** La valeur du service, ou {@code null} si elle est inconnue (service plus récent que l'app). */
    public static ReferralPlatform fromRaw(String raw) {
        if (raw == null) return null;
        for (ReferralPlatform value : values()) {
            if (value.rawValue.equals(raw)) return value;
        }
        return null;
    }
}
