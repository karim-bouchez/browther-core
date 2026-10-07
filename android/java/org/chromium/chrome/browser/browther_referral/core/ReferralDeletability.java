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
 * Ce compte peut-il être supprimé d'ICI ? — `GET /api/auth/account/deletable` (`docs/AUTH.md` §
 * « Suppression d'un compte FACULTATIF »).
 *
 * <p>⭐ **Se demande AVANT d'envoyer le code** (recette Fajrunaa, 2026-10-07 : un compte qui sert à
 * Darsunaa recevait son code, et n'apprenait le refus qu'après l'avoir saisi — en ayant eu peur,
 * entre-temps, de tout supprimer). ⚠️ {@link Kind#UNREACHABLE} et {@link Kind#FAILED} ne valent PAS
 * « oui » : sans réponse, on n'envoie pas de code.
 */
public final class ReferralDeletability {
    public enum Kind {
        DELETABLE,
        /** {@link #apps} nomme celles qu'on connaît ; VIDE quand le compte n'est pas né ici. */
        BLOCKED,
        UNREACHABLE,
        FAILED
    }

    public final Kind kind;

    /** Les apps qui retiennent le compte ({@link Kind#BLOCKED} seulement) — jamais {@code null}. */
    public final List<String> apps;

    private ReferralDeletability(Kind kind, List<String> apps) {
        this.kind = kind;
        this.apps = Collections.unmodifiableList(apps);
    }

    public static ReferralDeletability deletable() {
        return new ReferralDeletability(Kind.DELETABLE, Collections.<String>emptyList());
    }

    public static ReferralDeletability blocked(List<String> apps) {
        return new ReferralDeletability(Kind.BLOCKED, apps);
    }

    public static ReferralDeletability unreachable() {
        return new ReferralDeletability(Kind.UNREACHABLE, Collections.<String>emptyList());
    }

    public static ReferralDeletability failed() {
        return new ReferralDeletability(Kind.FAILED, Collections.<String>emptyList());
    }

    /** La règle. {@code reply == null} = aucune réponse. */
    public static ReferralDeletability fromReply(ReferralAuthReply reply) {
        if (reply == null) return unreachable();
        Map<String, Object> object = reply.object();
        Boolean deletable = ReferralAuthReply.bool(object, "deletable");
        if (reply.status != 200 || deletable == null) return failed();
        return deletable ? deletable() : blocked(ReferralAuthReply.appNames(object.get("apps")));
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof ReferralDeletability)) return false;
        ReferralDeletability o = (ReferralDeletability) other;
        return kind == o.kind && apps.equals(o.apps);
    }

    @Override
    public int hashCode() {
        return Objects.hash(kind, apps);
    }
}
