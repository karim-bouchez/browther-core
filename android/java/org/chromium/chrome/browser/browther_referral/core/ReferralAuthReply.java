// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Ce que l'auth-service a répondu à un appel fait au nom du compte — le code HTTP et le corps,
 * rendus tels quels aux RÈGLES ({@link ReferralDeletability}, {@link ReferralDeletionCode}, {@link
 * ReferralDeletionOutcome}). Une réponse {@code null} = aucune réponse (réseau coupé, délai).
 *
 * <p>⚠️ Lecture TOLÉRANTE, au contraire du statut du service : un champ absent ou du mauvais type
 * vaut « absent » (`as? Bool` côté Swift), ⛔ jamais une exception — c'est la règle qui tranche, et
 * dans le doute elle refuse.
 */
public final class ReferralAuthReply {
    public final int status;

    /** Le corps brut ({@code ""} s'il n'y en a pas). */
    public final String body;

    public ReferralAuthReply(int status, String body) {
        this.status = status;
        this.body = body == null ? "" : body;
    }

    /** Le corps lu comme un objet JSON — {@code null} s'il n'en est pas un (`null`, HTML, vide). */
    Map<String, Object> object() {
        try {
            return ReferralJson.parseObject(body).map();
        } catch (ReferralJson.JsonException e) {
            return null;
        }
    }

    /** Un champ booléen — {@code null} s'il manque ou n'est pas un booléen (⛔ pas « true » en chaîne). */
    static Boolean bool(Map<String, Object> object, String key) {
        Object value = object == null ? null : object.get(key);
        return value instanceof Boolean ? (Boolean) value : null;
    }

    /** Un champ texte — {@code null} s'il manque ou n'est pas une chaîne. */
    static String string(Map<String, Object> object, String key) {
        Object value = object == null ? null : object.get(key);
        return value instanceof String ? (String) value : null;
    }

    /** Les NOMS des apps d'un tableau `[{ id, name }]` — vides et entrées illisibles écartés. */
    static List<String> appNames(Object raw) {
        List<String> names = new ArrayList<>();
        if (!(raw instanceof List)) return names;
        for (Object item : (List<?>) raw) {
            if (!(item instanceof Map)) continue;
            Object name = ((Map<?, ?>) item).get("name");
            if (name instanceof String && !((String) name).isEmpty()) names.add((String) name);
        }
        return names;
    }
}
