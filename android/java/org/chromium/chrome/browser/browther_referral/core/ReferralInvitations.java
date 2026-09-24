// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Les invitations qu'on MONTRE. */
public final class ReferralInvitations {
    private ReferralInvitations() {}

    /**
     * 🔴 **On n'invente rien** (§ 12.1) : une invitation n'existe, pour la personne, qu'à partir du
     * moment où un proche a UTILISÉ son code (`installed`, puis `validated`). ⛔ Pas l'état `sent`.
     * Les plus récentes d'abord (le service les rend dans l'ordre de création).
     */
    public static List<InvitationItem> known(List<InvitationItem> items) {
        List<InvitationItem> result = new ArrayList<>();
        for (InvitationItem item : items) {
            if (item.status != InvitationStatus.SENT) result.add(item);
        }
        Collections.reverse(result);
        return result;
    }

    /**
     * Les JOURS qui restent à une invitation EN COURS — « encore 2 jours avec Browther par défaut »
     * (§ 5.3). {@code null} = validée, ou progression inconnue. ⚠️ Jamais 0 tant qu'elle n'est pas
     * validée : « encore 0 jour » se lirait comme un bug.
     */
    public static Integer daysLeft(InvitationItem item) {
        if (item.status != InvitationStatus.INSTALLED || item.progress == null) return null;
        return daysLeft(item.progress);
    }

    public static Integer daysLeft(ValidationProgress progress) {
        if (progress == null) return null;
        return Math.max(1, (int) Math.ceil(progress.target - progress.current));
    }

    /** Celle qui est la plus près d'être validée — le rappel « en bonne voie ». */
    public static Integer closestDaysLeft(List<InvitationItem> items) {
        Integer best = null;
        for (InvitationItem item : items) {
            Integer left = daysLeft(item);
            if (left != null && (best == null || left < best)) best = left;
        }
        return best;
    }

    /** La part accomplie, de 0 à 1 (la barre de la carte du filleul). */
    public static double ratio(ValidationProgress progress) {
        if (progress == null || progress.target <= 0) return 0;
        return Math.max(0, Math.min(1, progress.current / progress.target));
    }
}
