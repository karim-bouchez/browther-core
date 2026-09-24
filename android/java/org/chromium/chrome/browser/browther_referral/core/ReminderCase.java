// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

/**
 * Le cas de rappel choisi par le service (§ 3.3). ⭐ Il dit **quoi** dire, jamais **quand** : c'est
 * l'app qui décide (J−10 / J−3, au moment de mérite).
 */
public enum ReminderCase {
    SUBSCRIPTION_CANCELLED("subscription_cancelled"),
    IN_PROGRESS("in_progress"),
    NONE_OPENED("none_opened"),
    EARNED_MONTHS_ENDING("earned_months_ending");

    public final String rawValue;

    ReminderCase(String rawValue) {
        this.rawValue = rawValue;
    }

    /** La valeur du service, ou {@code null} si elle est inconnue (service plus récent que l'app). */
    public static ReminderCase fromRaw(String raw) {
        if (raw == null) return null;
        for (ReminderCase value : values()) {
            if (value.rawValue.equals(raw)) return value;
        }
        return null;
    }
}
