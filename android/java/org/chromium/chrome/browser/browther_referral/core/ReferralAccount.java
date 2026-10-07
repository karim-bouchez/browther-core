// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.Objects;

/**
 * Le compte dev&din FACULTATIF sur Android — `docs/PARRAINAGE.md` § 7.1 et
 * `private/docs/PARRAINAGE.md` § 7.4 ; port de `ReferralAccount.swift` (iOS, la référence). ⛔
 * Jamais exigé : il ne sert qu'à faire suivre le PARRAINAGE (code, invitations, mois gagnés) et
 * l'abonnement d'un appareil à l'autre. 🔴 Il ne porte que ça : ni historique, ni favoris, ni
 * onglets.
 *
 * <p>⭐ Le contrat est COMMUN à toutes les apps dev&din (§ 7.1, tableau « Le contrat ») : les appels
 * vivent dans {@link ReferralAuthClient}, les règles dans {@link ReferralDeletability}, {@link
 * ReferralDeletionCode}, {@link ReferralDeletionOutcome}, {@link ReferralDeletion}, {@link
 * ReferralAccountLabel} et {@link ReferralAccountStakes} (le pendant de
 * `ReferralAccountRules.swift`). ⛔ Un écart avec l'iOS, le desktop ou Fajrunaa est un défaut, pas
 * une variante.
 *
 * <p>⚠️ Sur Android le rangement n'est PAS ici : le jeton vit chiffré par l'Android Keystore
 * (`ReferralAccountKeystore`, hors de `core/` — il lui faut `android.*`).
 */
public final class ReferralAccount {
    /** L'identifiant Better Auth — il DEVIENT le sujet du parrainage. */
    public final String userId;

    /** {@code null} tant qu'on ne la connaît pas (rangement illisible, compte sans adresse). */
    public final String email;

    public final String name;

    public ReferralAccount(String userId, String email, String name) {
        this.userId = userId;
        this.email = email;
        this.name = name;
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof ReferralAccount)) return false;
        ReferralAccount o = (ReferralAccount) other;
        return userId.equals(o.userId) && Objects.equals(email, o.email) && Objects.equals(name, o.name);
    }

    @Override
    public int hashCode() {
        return Objects.hash(userId, email, name);
    }
}
