// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

/**
 * Les fonctionnalités supplémentaires, par identifiant de garde (§ 9.0). ⚠️ **L'annonce attend que
 * Sawtunaa sorte de « encore en développement »** ({@link ReferralLaunch#extrasReleased}) : d'ici
 * là, rien n'est en pause.
 */
public enum ExtraFeature {
    MUSIC_REMOVAL("music_removal");

    public final String rawValue;

    ExtraFeature(String rawValue) {
        this.rawValue = rawValue;
    }

    /** La valeur du service, ou {@code null} si elle est inconnue (service plus récent que l'app). */
    public static ExtraFeature fromRaw(String raw) {
        if (raw == null) return null;
        for (ExtraFeature value : values()) {
            if (value.rawValue.equals(raw)) return value;
        }
        return null;
    }
}
