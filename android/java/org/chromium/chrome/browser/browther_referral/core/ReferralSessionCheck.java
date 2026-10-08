// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.Map;
import java.util.Objects;

/**
 * La session tient-elle toujours ? — {@code GET /api/auth/get-session}. Port de {@code
 * ReferralSessionCheck} (iOS, {@code ReferralAccountRules.swift}), jumeau de {@code checkSession}
 * dans {@code fajrunaa/services/referral/account.ts}.
 *
 * <p>🔴 <b>Depuis que le compte peut être SUPPRIMÉ, la question est réelle</b> : un compte supprimé
 * (ou une session révoquée) depuis un autre appareil laissait celui-ci « connecté » à un compte qui
 * n'existe plus, sur un sujet que le service lui recréait vide — au lieu de le rendre à son sujet
 * d'appareil, qui porte sa copie de la couverture.
 *
 * <ul>
 *   <li>{@link Kind#GONE} : l'auth-service a RÉPONDU que la session n'existe plus ({@code 401}, ou
 *       {@code 200} + {@code null} — c'est ainsi que Better Auth dit « pas de session ») ;
 *   <li>{@link Kind#UNKNOWN} : on ne sait pas (injoignable, erreur, page HTML servie en 200 par un
 *       intermédiaire). ⛔ <b>On ne déconnecte JAMAIS quelqu'un sur un « on ne sait pas »</b> (§
 *       7.1 du doc commun, « Le sens de la panne »).
 * </ul>
 */
public final class ReferralSessionCheck {
    public enum Kind {
        ALIVE,
        GONE,
        UNKNOWN
    }

    public final Kind kind;

    /** Le compte tel que la session le dit — seulement pour {@link Kind#ALIVE}. */
    public final ReferralAccount account;

    private ReferralSessionCheck(Kind kind, ReferralAccount account) {
        this.kind = kind;
        this.account = account;
    }

    public static ReferralSessionCheck alive(ReferralAccount account) {
        return new ReferralSessionCheck(Kind.ALIVE, account);
    }

    public static ReferralSessionCheck gone() {
        return new ReferralSessionCheck(Kind.GONE, null);
    }

    public static ReferralSessionCheck unknown() {
        return new ReferralSessionCheck(Kind.UNKNOWN, null);
    }

    /** {@code reply == null} = injoignable. */
    public static ReferralSessionCheck fromReply(ReferralAuthReply reply) {
        if (reply == null) return unknown();
        if (reply.status == 401) return gone();
        if (reply.status != 200) return unknown();
        // ⚠️ Le `null` de Better Auth est un JSON à part entière ; un corps vide ou une page HTML
        // n'en sont pas un.
        if ("null".equals(reply.body.trim())) return gone();
        Map<String, Object> object = reply.object();
        Object user = object == null ? null : object.get("user");
        if (user instanceof Map) {
            @SuppressWarnings("unchecked")
            Map<String, Object> fields = (Map<String, Object>) user;
            String id = ReferralAuthReply.string(fields, "id");
            if (id != null && !id.isEmpty()) {
                return alive(
                        new ReferralAccount(
                                id,
                                ReferralAuthReply.string(fields, "email"),
                                ReferralAuthReply.string(fields, "name")));
            }
        }
        return unknown();
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof ReferralSessionCheck)) return false;
        ReferralSessionCheck o = (ReferralSessionCheck) other;
        return kind == o.kind && Objects.equals(account, o.account);
    }

    @Override
    public int hashCode() {
        return Objects.hash(kind, account);
    }
}
