// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

/** Le code de confirmation de la suppression du compte, tel que la personne le recopie. */
public final class ReferralDeletion {
    private ReferralDeletion() {}

    public static final int codeLength = 6;

    /**
     * Les six chiffres du code reçu (espaces et tirets d'un code recopié retirés) — {@code null}
     * s'il en manque. ⚠️ Des chiffres LATINS seulement : c'est ce que l'e-mail contient, et ce que
     * l'auth-service compare.
     */
    public static String normalizeCode(String raw) {
        if (raw == null) return null;
        StringBuilder digits = new StringBuilder();
        for (int i = 0; i < raw.length(); i++) {
            char c = raw.charAt(i);
            // ⚠️ `isSpaceChar` aussi : l'espace insécable d'un code collé n'est pas un
            // « whitespace » pour Java, alors qu'il l'est pour Swift.
            if (Character.isWhitespace(c) || Character.isSpaceChar(c) || c == '-') continue;
            if (c < '0' || c > '9') return null;
            digits.append(c);
        }
        return digits.length() == codeLength ? digits.toString() : null;
    }
}
