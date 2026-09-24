// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

/**
 * Les fonctionnalités essentielles — ⚠️ la liste AFFICHÉE et les GARDES ne se confondent pas (§ 9.0) :
 * la liste dit ce que la personne gagne, les gardes suivent les gestes. Basarunaa (`blur`) ⛔ jamais
 * en pause (§ 9). L'icône se résout dans l'écran (Material), ⛔ jamais recopiée ailleurs.
 */
public enum EssentialFeature {
    BLUR("blur"),
    SHIELDS("shields"),
    BROWSING("browsing");

    public final String rawValue;

    EssentialFeature(String rawValue) {
        this.rawValue = rawValue;
    }

    /** La valeur du service, ou {@code null} si elle est inconnue (service plus récent que l'app). */
    public static EssentialFeature fromRaw(String raw) {
        if (raw == null) return null;
        for (EssentialFeature value : values()) {
            if (value.rawValue.equals(raw)) return value;
        }
        return null;
    }
}
