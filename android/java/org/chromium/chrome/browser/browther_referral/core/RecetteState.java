// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 🧪 Une situation COMPLÈTE à poser côté service (`POST /v1/admin/recette`, § 12.18) — un
 * remplacement, jamais une retouche.
 */
public final class RecetteState {
    public enum Subscription {
        NONE("none"),
        ACTIVE("active"),
        CANCELLED("cancelled");

        public final String rawValue;

        Subscription(String rawValue) {
            this.rawValue = rawValue;
        }
    }

    public boolean trialStarted;
    /** Jours de couverture restants ; négatif = déjà tombée ; {@code null} = aucune. */
    public Integer daysLeft;
    public boolean lifetime;
    public int validated;
    public int installed;
    public Subscription subscription = Subscription.NONE;
    public int subscriptionDaysLeft = 30;

    public RecetteState(boolean trialStarted, Integer daysLeft) {
        this.trialStarted = trialStarted;
        this.daysLeft = daysLeft;
    }

    /**
     * ⚠️ `daysLeft: null` doit PARTIR (« aucune couverture ») : l'omettre ferait lire au service
     * « non précisé ».
     */
    public Map<String, Object> toJson() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("trialStarted", trialStarted);
        m.put("daysLeft", daysLeft);
        m.put("lifetime", lifetime);
        m.put("validated", validated);
        m.put("installed", installed);
        m.put("subscription", subscription.rawValue);
        m.put("subscriptionDaysLeft", subscriptionDaysLeft);
        return m;
    }
}
