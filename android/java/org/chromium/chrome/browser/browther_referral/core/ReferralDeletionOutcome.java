// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/**
 * Ce que `POST /api/auth/account/delete` a répondu (`docs/AUTH.md`) :
 *
 * <ul>
 *   <li>{@link Kind#DELETED} — le compte et ce qu'il portait sont supprimés ;
 *   <li>{@link Kind#BAD_CODE} — le code de confirmation est faux ou expiré ;
 *   <li>{@link Kind#USED_ELSEWHERE} — le compte sert, ou a pu servir, à une app dev&din qui a ses
 *       propres données : il se supprime depuis celle-là, ⛔ pas d'ici ;
 *   <li>{@link Kind#UNREACHABLE} — un des deux services n'a pas répondu (`422` : l'auth-service n'a
 *       pas joint le service de parrainage) : RIEN n'est supprimé, on peut réessayer avec le même
 *       code ;
 *   <li>{@link Kind#FAILED} — le reste (session perdue, erreur du service).
 * </ul>
 *
 * <p>🔴 Seul {@link Kind#DELETED} autorise le client à toucher à son rangement local.
 */
public final class ReferralDeletionOutcome {
    public enum Kind {
        DELETED,
        BAD_CODE,
        USED_ELSEWHERE,
        UNREACHABLE,
        FAILED
    }

    public final Kind kind;

    /** Les apps nommées par un refus ({@link Kind#USED_ELSEWHERE} seulement) — jamais {@code null}. */
    public final List<String> apps;

    private ReferralDeletionOutcome(Kind kind, List<String> apps) {
        this.kind = kind;
        this.apps = Collections.unmodifiableList(apps);
    }

    private static ReferralDeletionOutcome of(Kind kind) {
        return new ReferralDeletionOutcome(kind, Collections.<String>emptyList());
    }

    public static ReferralDeletionOutcome deleted() {
        return of(Kind.DELETED);
    }

    public static ReferralDeletionOutcome badCode() {
        return of(Kind.BAD_CODE);
    }

    public static ReferralDeletionOutcome usedElsewhere(List<String> apps) {
        return new ReferralDeletionOutcome(Kind.USED_ELSEWHERE, apps);
    }

    public static ReferralDeletionOutcome unreachable() {
        return of(Kind.UNREACHABLE);
    }

    public static ReferralDeletionOutcome failed() {
        return of(Kind.FAILED);
    }

    /**
     * La règle. {@code reply == null} = aucune réponse. ⚠️ `401` dit deux choses (session perdue,
     * code faux) : c'est `error` qui tranche.
     */
    public static ReferralDeletionOutcome fromReply(ReferralAuthReply reply) {
        if (reply == null) return unreachable();
        Map<String, Object> object = reply.object();
        switch (reply.status) {
            case 200:
                return Boolean.TRUE.equals(ReferralAuthReply.bool(object, "success"))
                        ? deleted()
                        : failed();
            case 401:
                return "INVALID_CODE".equals(ReferralAuthReply.string(object, "error"))
                        ? badCode()
                        : failed();
            case 422:
                return unreachable();
            case 409:
                return usedElsewhere(
                        ReferralAuthReply.appNames(object == null ? null : object.get("apps")));
            default:
                return failed();
        }
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof ReferralDeletionOutcome)) return false;
        ReferralDeletionOutcome o = (ReferralDeletionOutcome) other;
        return kind == o.kind && apps.equals(o.apps);
    }

    @Override
    public int hashCode() {
        return Objects.hash(kind, apps);
    }
}
