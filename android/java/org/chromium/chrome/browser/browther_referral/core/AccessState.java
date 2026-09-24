// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.time.Instant;
import java.util.Objects;

/**
 * Ce que l'app a le droit d'ouvrir — `docs/PARRAINAGE.md` § 4 et § 7.4 : **statut effectif =
 * max(accès payé, couverture du parrainage)**.
 *
 * <p>🔴 **Trois états, jamais deux.** Tant qu'on ne sait pas, on n'affiche NI la pause NI une
 * sollicitation : un écran qui « choisit » pendant qu'il ne sait pas est un écran qui clignote.
 *
 * <p>🔴 **Sens de la panne : OUVERT.** Jamais interrogé ⇒ tout est ouvert ; service injoignable ⇒
 * dernier statut connu. ⛔ Interdit permanent (§ 11.2) : on ne bloque jamais quelqu'un à cause d'une
 * panne serveur.
 */
public final class AccessState {
    /** {@code true} = les fonctionnalités supplémentaires sont ouvertes. */
    public final boolean unlocked;

    public final boolean lifetime;
    /** Fin de la couverture, {@code null} si à vie ou si rien n'a jamais couvert. */
    public final Instant until;

    public final AccessSource source;
    /** ⭐ {@code false} tant que la réponse du service n'est pas arrivée. */
    public final boolean known;
    /**
     * Le mois de l'annonce n'a pas démarré et rien d'autre ne couvre : tout est ouvert. Sert au
     * libellé de l'écran 6.
     */
    public final boolean beforeTrial;

    /** Ce qu'on vaut tant qu'on ne sait pas — ⛔ ne jamais mettre en pause ici. */
    public static final AccessState unknown =
            new AccessState(true, false, null, AccessSource.NONE, false, false);

    public AccessState(
            boolean unlocked,
            boolean lifetime,
            Instant until,
            AccessSource source,
            boolean known,
            boolean beforeTrial) {
        this.unlocked = unlocked;
        this.lifetime = lifetime;
        this.until = until;
        this.source = source;
        this.known = known;
        this.beforeTrial = beforeTrial;
    }

    /**
     * 🔴 **Avant l'annonce, RIEN n'est en pause** (§ 12.11). Le service ne dit que ce qui COUVRE :
     * un sujet neuf y est `unlocked: false, source: none`, et le lire tel quel mettait tout nouveau
     * venu en pause dès l'arrivée — un paywall à l'installation (⛔ § 11.2).
     *
     * <p>⚠️ `trial.startedAt` est le seul signal : dans `access`, une couverture tombée ne se
     * distingue pas d'une couverture qui n'a jamais existé.
     *
     * <p>{@code status == null} ⇒ {@link #unknown}.
     */
    public AccessState(ReferralStatus status) {
        if (status == null) {
            this.unlocked = unknown.unlocked;
            this.lifetime = unknown.lifetime;
            this.until = unknown.until;
            this.source = unknown.source;
            this.known = unknown.known;
            this.beforeTrial = unknown.beforeTrial;
            return;
        }
        boolean beforeTrial =
                status.trial.startedAt == null && status.access.source == AccessSource.NONE;
        this.unlocked = status.access.unlocked || beforeTrial;
        this.lifetime = status.access.lifetime;
        this.until = ReferralDate.parse(status.access.until);
        this.source = status.access.source;
        this.known = true;
        this.beforeTrial = beforeTrial;
    }

    /**
     * Les fonctionnalités supplémentaires sont-elles en pause **maintenant** ?
     *
     * <p>⚠️ On recalcule sur l'horloge locale plutôt que de croire `unlocked` : le statut peut dater
     * de plusieurs heures (cache), et une couverture qui tombe pendant que l'app est ouverte doit se
     * voir. ⛔ Mais un statut inconnu ne met jamais en pause, et « avant l'annonce » non plus.
     */
    public boolean isPaused(Instant now) {
        if (!known || lifetime || beforeTrial) return false;
        if (until == null) return !unlocked;
        return !until.isAfter(now);
    }

    public boolean isPaused() {
        return isPaused(Instant.now());
    }

    /** Jours entiers restants avant la fin de la couverture (⌈…⌉, jamais négatif). */
    public Integer daysLeft(Instant now) {
        if (!known || lifetime || until == null) return null;
        double seconds = (until.toEpochMilli() - now.toEpochMilli()) / 1000.0;
        if (seconds <= 0) return 0;
        return (int) Math.ceil(seconds / 86_400);
    }

    public Integer daysLeft() {
        return daysLeft(Instant.now());
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof AccessState)) return false;
        AccessState o = (AccessState) other;
        return unlocked == o.unlocked
                && lifetime == o.lifetime
                && Objects.equals(until, o.until)
                && source == o.source
                && known == o.known
                && beforeTrial == o.beforeTrial;
    }

    @Override
    public int hashCode() {
        return Objects.hash(unlocked, lifetime, until, source, known, beforeTrial);
    }
}
