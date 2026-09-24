// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.time.Instant;
import java.time.ZoneId;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Objects;

/**
 * Quand solliciter — `docs/PARRAINAGE.md` § 3, § 3.1, § 3.2, § 3.3 bis et § 4, avec la ligne
 * Browther du § 10.4.
 *
 * <pre>
 * | Écran                 | Quand                                                                   |
 * | O Code d'un proche    | Dans l'INTRODUCTION (étape à part) — ⛔ jamais d'ici                    |
 * | 0 Annonce             | 3ᵉ jour de navigation — ⚠️ et seulement quand Sawtunaa est finalisé     |
 * | 1 J−10 / J−3          | de la PREMIÈRE fin de couverture (pas de cas de rappel)                 |
 * | 3 Rappel              | J−10 / J−3 de CHAQUE autre fin, avec le cas du service                  |
 * | 2 J0                  | la couverture est tombée — J0, +7 j, puis toutes les deux semaines      |
 * </pre>
 *
 * <p>⛔ **Jamais de paywall à l'ouverture ni en fin d'onboarding** (§ 11.2), et les écrans 1, 2, 3
 * attendent le **moment de mérite** (§ 3.1 — Browther : après un retrait de musique, ou au N-ième
 * onglet du jour). ⭐ **Qui a payé n'est plus jamais sollicité** (§ 4, absolu).
 *
 * <p>Toutes les fonctions rendent un NOUVEL état : ⛔ l'état reçu n'est jamais modifié (la
 * sémantique « valeur » de la version Swift). Le « jour local » se calcule dans {@code zone}
 * (défaut : le fuseau de l'appareil).
 */
public final class ReferralPrompt {
    private ReferralPrompt() {}

    /** Jours de navigation DISTINCTS avant l'annonce (§ 3, écran 0). */
    public static final int announceAfterDistinctDays = 3;

    /**
     * Le moment de mérite « au N-ième onglet du jour » (§ 3.1) : la N-ième vraie page chargée dans
     * la journée. ⚠️ Pas l'ouverture de l'app — § 3.1 : jamais pendant, jamais à l'ouverture, juste
     * après que le produit a rendu service.
     */
    public static final int meritPagesPerDay = 5;

    /**
     * Les rappels d'une fin de couverture : **J−10 puis J−3**, une fois chacun par échéance (§ 3.3
     * bis). ⭐ J−10 parce qu'une invitation met des JOURS à se valider (installer PUIS 3 jours par
     * défaut). ⛔ Pas de troisième palier : le pied de J0 promet « jamais plus d'une fois par
     * semaine ».
     */
    public static final List<Integer> reminderStages = Collections.unmodifiableList(Arrays.asList(10, 3));

    /**
     * Cadence de l'écran J0 (§ 3.2) : **J0, +7 j, puis toutes les deux semaines**. ⛔ Ne jamais
     * redescendre sous 7 jours sans changer d'abord le texte que la personne lit (« jamais plus
     * d'une fois par semaine »).
     */
    public static int pausedGapDays(int alreadyShown) {
        if (alreadyShown <= 0) return 0;
        if (alreadyShown == 1) return 7;
        return 14;
    }

    private static int orZero(Integer value) {
        return value == null ? 0 : value;
    }

    // MARK: - Ce que l'usage écrit

    /** Un jour de navigation de plus — une fois par JOUR local au plus. */
    public static ReferralPromptState recordBrowsingDay(
            ReferralPromptState state, Instant now, ZoneId zone) {
        String today = ReferralDate.localDayKey(now, zone);
        if (today.equals(state.lastDay)) return state;
        ReferralPromptState next = state.copy();
        next.lastDay = today;
        next.days = orZero(state.days) + 1;
        return next;
    }

    public static ReferralPromptState recordBrowsingDay(ReferralPromptState state, Instant now) {
        return recordBrowsingDay(state, now, ZoneId.systemDefault());
    }

    /** Le moment de mérite d'aujourd'hui est-il encore disponible ? */
    public static boolean meritAvailable(ReferralPromptState state, Instant now, ZoneId zone) {
        return !ReferralDate.localDayKey(now, zone).equals(state.meritUsedDay);
    }

    public static boolean meritAvailable(ReferralPromptState state, Instant now) {
        return meritAvailable(state, now, ZoneId.systemDefault());
    }

    // MARK: - La décision

    /**
     * L'écran à solliciter. L'énumération Swift à valeurs associées devient {@link Kind} + les
     * champs du cas ({@code daysLeft} et {@code stage} pour ENDING et REMINDER, {@code
     * reminderCase} pour REMINDER).
     */
    public static final class Solicitation {
        public enum Kind {
            /** Écran 0 — ⭐ l'app DOIT démarrer le mois en l'affichant (§ 4). */
            ANNOUNCE,
            /** Écran 1 — première fin de couverture, le service n'a rien de plus à dire. */
            ENDING,
            /** Écran 3 — fins suivantes, avec le cas du § 3.3. */
            REMINDER,
            /** Écran 2 — la couverture est tombée. */
            PAUSED
        }

        public final Kind kind;
        public final int daysLeft;
        public final int stage;
        public final ReminderCase reminderCase;

        private Solicitation(Kind kind, int daysLeft, int stage, ReminderCase reminderCase) {
            this.kind = kind;
            this.daysLeft = daysLeft;
            this.stage = stage;
            this.reminderCase = reminderCase;
        }

        public static Solicitation announce() {
            return new Solicitation(Kind.ANNOUNCE, 0, 0, null);
        }

        public static Solicitation ending(int daysLeft, int stage) {
            return new Solicitation(Kind.ENDING, daysLeft, stage, null);
        }

        public static Solicitation reminder(int daysLeft, int stage, ReminderCase reminderCase) {
            return new Solicitation(Kind.REMINDER, daysLeft, stage, reminderCase);
        }

        public static Solicitation paused() {
            return new Solicitation(Kind.PAUSED, 0, 0, null);
        }

        @Override
        public boolean equals(Object other) {
            if (!(other instanceof Solicitation)) return false;
            Solicitation o = (Solicitation) other;
            return kind == o.kind
                    && daysLeft == o.daysLeft
                    && stage == o.stage
                    && reminderCase == o.reminderCase;
        }

        @Override
        public int hashCode() {
            return Objects.hash(kind, daysLeft, stage, reminderCase);
        }

        @Override
        public String toString() {
            switch (kind) {
                case ENDING:
                    return "ending(daysLeft: " + daysLeft + ", stage: " + stage + ")";
                case REMINDER:
                    return "reminder(daysLeft: " + daysLeft + ", stage: " + stage + ", " + reminderCase + ")";
                default:
                    return kind.toString();
            }
        }
    }

    public static final class Input {
        public final ReferralPromptState state;
        public final ReferralStatus status;
        public final AccessState access;
        /**
         * ⭐ Le produit vient de rendre son service (§ 3.1). Les écrans 1, 2 et 3 ne sortent QUE
         * là ; l'annonce, elle, n'a pas besoin de l'attendre.
         */
        public final boolean atMeritMoment;
        /**
         * ⚠️ Sawtunaa est-il sorti de « encore en développement » ? L'annonce, qui démarre le mois
         * offert, l'attend (§ 9).
         */
        public final boolean extrasReleased;

        public final Instant now;
        public final ZoneId zone;

        public Input(
                ReferralPromptState state,
                ReferralStatus status,
                AccessState access,
                boolean atMeritMoment,
                boolean extrasReleased,
                Instant now,
                ZoneId zone) {
            this.state = state;
            this.status = status;
            this.access = access;
            this.atMeritMoment = atMeritMoment;
            this.extrasReleased = extrasReleased;
            this.now = now;
            this.zone = zone;
        }

        public Input(
                ReferralPromptState state,
                ReferralStatus status,
                AccessState access,
                boolean atMeritMoment,
                boolean extrasReleased,
                Instant now) {
            this(state, status, access, atMeritMoment, extrasReleased, now, ZoneId.systemDefault());
        }
    }

    public static Solicitation decide(Input input) {
        ReferralPromptState state = input.state;
        AccessState access = input.access;
        ReferralStatus status = input.status;
        Instant now = input.now;

        // ⛔ Tant qu'on ne sait pas, on n'affiche rien (trois états, jamais deux).
        if (!access.known || status == null) return null;
        // ⭐ Absolu : qui a payé n'est plus jamais sollicité (§ 4).
        if (status.isSubscriberAtPeace()) return null;
        // Plus rien à demander à quelqu'un qui a tout gagné.
        if (access.lifetime) return null;

        if (!Boolean.TRUE.equals(state.announced)) {
            // ⚠️ Un mois déjà démarré ailleurs (même identité sur un autre appareil) : l'annonce
            // « offert 1 mois » ne serait plus vraie. L'appelant la marque vue sans la montrer
            // (`announceAlreadyStarted`).
            if (status.trial.startedAt != null) return null;
            // ⭐ Browther : le mois offert ne démarre qu'à la finalisation de Sawtunaa.
            if (!input.extrasReleased) return null;
            return orZero(state.days) >= announceAfterDistinctDays ? Solicitation.announce() : null;
        }

        // ⚠️ Tout le reste attend que le produit ait rendu service (§ 3.1).
        if (!input.atMeritMoment || !meritAvailable(state, now, input.zone)) return null;

        if (access.isPaused(now)) {
            return shouldShowPaused(state, now) ? Solicitation.paused() : null;
        }

        Integer left = access.daysLeft(now);
        Instant until = access.until;
        if (left == null || left <= 0 || until == null) return null;

        // Le palier en cours = le plus PETIT de ceux qu'on a atteints (à J−2, c'est le 3, même si
        // le 10 est passé) — et chacun ne sort qu'une fois par fin.
        Integer stage = reminderStage(left);
        if (stage == null) return null;
        String deadline = ReferralDate.string(until);
        Integer already = deadline.equals(state.reminderShownFor) ? state.reminderStageShown : null;
        if (already != null && already <= stage) return null;

        if (status.reminder.reminderCase != null) {
            return Solicitation.reminder(left, stage, status.reminder.reminderCase);
        }
        return Solicitation.ending(left, stage);
    }

    /** Le palier de rappel atteint : le plus petit des paliers ≥ jours restants. */
    public static Integer reminderStage(int daysLeft) {
        Integer best = null;
        for (int stage : reminderStages) {
            if (daysLeft <= stage && (best == null || stage < best)) best = stage;
        }
        return best;
    }

    static boolean shouldShowPaused(ReferralPromptState state, Instant now) {
        int gap = pausedGapDays(orZero(state.pausedShownCount));
        Instant shownAt = ReferralDate.parse(state.pausedShownAt);
        if (gap <= 0 || shownAt == null) return true;
        return (now.toEpochMilli() - shownAt.toEpochMilli()) >= gap * 86_400_000L;
    }

    /**
     * Le mois a démarré sans que CET appareil ait montré l'annonce (même identité sur un autre
     * appareil, recette) : on la marque vue sans l'afficher — sinon elle promettrait « offert 1
     * mois » à quelqu'un dont le mois court.
     */
    public static boolean announceAlreadyStarted(ReferralPromptState state, ReferralStatus status) {
        return !Boolean.TRUE.equals(state.announced)
                && status != null
                && status.trial.startedAt != null;
    }

    // MARK: - Les bonnes nouvelles (écrans 8 et 8 bis)

    /**
     * Une invitation a-t-elle abouti depuis la dernière annonce ? ⚠️ Au tout premier statut (rien
     * de vu), on s'aligne SANS rien annoncer — sinon une réinstallation ferait fêter des invitations
     * validées depuis des mois.
     */
    public static boolean newlyValidated(ReferralPromptState state, int validated) {
        if (state.seenValidated == null) return false;
        return validated > state.seenValidated;
    }

    /** Le filleul vient-il d'être validé ? Seulement s'il était « en cours » la dernière fois. */
    public static boolean refereeJustValidated(
            ReferralPromptState state, ReferralStatus.ReferredBy referredBy) {
        return state.seenRefereeStatus == ReferralPromptState.SeenReferee.INSTALLED
                && referredBy != null
                && referredBy.status == ReferralStatus.ReferredBy.Status.VALIDATED;
    }

    // MARK: - Ce que l'affichage écrit

    public static ReferralPromptState markValidatedSeen(ReferralPromptState state, int validated) {
        ReferralPromptState next = state.copy();
        next.seenValidated = validated;
        return next;
    }

    public static ReferralPromptState markRefereeSeen(
            ReferralPromptState state, ReferralStatus.ReferredBy referredBy) {
        ReferralPromptState next = state.copy();
        if (referredBy == null) {
            next.seenRefereeStatus = ReferralPromptState.SeenReferee.NONE;
        } else if (referredBy.status == ReferralStatus.ReferredBy.Status.INSTALLED) {
            next.seenRefereeStatus = ReferralPromptState.SeenReferee.INSTALLED;
        } else {
            next.seenRefereeStatus = ReferralPromptState.SeenReferee.VALIDATED;
        }
        return next;
    }

    public static ReferralPromptState markWelcomed(ReferralPromptState state) {
        ReferralPromptState next = state.copy();
        next.welcomed = true;
        return next;
    }

    public static ReferralPromptState markAnnounced(ReferralPromptState state) {
        ReferralPromptState next = state.copy();
        next.announced = true;
        return next;
    }

    public static ReferralPromptState markMeritUsed(
            ReferralPromptState state, Instant now, ZoneId zone) {
        ReferralPromptState next = state.copy();
        next.meritUsedDay = ReferralDate.localDayKey(now, zone);
        return next;
    }

    public static ReferralPromptState markMeritUsed(ReferralPromptState state, Instant now) {
        return markMeritUsed(state, now, ZoneId.systemDefault());
    }

    /** Un rappel a été montré pour CETTE échéance, à CE palier (10 puis 3). */
    public static ReferralPromptState markReminderShown(
            ReferralPromptState state, Instant deadline, int stage) {
        if (deadline == null) return state;
        ReferralPromptState next = state.copy();
        next.reminderShownFor = ReferralDate.string(deadline);
        next.reminderStageShown = stage;
        return next;
    }

    /**
     * L'écran J0 a été montré. ⚠️ Le compteur repart de zéro quand la couverture s'est rouverte
     * entre-temps (une invitation validée, puis une nouvelle pause) : sinon quelqu'un qui a déjà vu
     * l'écran trois fois ne le reverrait plus qu'une fois par quinzaine pour une pause toute neuve.
     */
    public static ReferralPromptState markPausedShown(
            ReferralPromptState state, Instant pausedSince, Instant now) {
        String since = pausedSince == null ? null : ReferralDate.string(pausedSince);
        boolean restarted = since != null && !since.equals(state.pausedSince);
        ReferralPromptState next = state.copy();
        next.pausedSince = since != null ? since : state.pausedSince;
        next.pausedShownAt = ReferralDate.string(now);
        next.pausedShownCount = restarted ? 1 : orZero(state.pausedShownCount) + 1;
        return next;
    }

    /** 🔴 Le circuit des trois façons s'ouvre (J0, puis 2b ouvert depuis lui). */
    public static ReferralPromptState markCircuitOpen(
            ReferralPromptState state, ReferralPromptState.Circuit entry) {
        if (state.circuit != null) return state;
        ReferralPromptState next = state.copy();
        next.circuit = entry;
        return next;
    }

    /**
     * Une des trois sorties a été prise (inviter, payer, une du'a) — ou il n'y a plus rien à
     * demander.
     */
    public static ReferralPromptState markCircuitClosed(ReferralPromptState state) {
        if (state.circuit == null) return state;
        ReferralPromptState next = state.copy();
        next.circuit = null;
        return next;
    }

    /**
     * Ce qu'il faut ROUVRIR au lancement : l'écran par lequel le circuit a commencé. ⛔ Rien tant
     * que le statut n'est pas connu, ⛔ jamais à qui a payé ou obtenu l'accès à vie entre-temps, et
     * plus rien si la pause elle-même a disparu (une invitation validée) : le circuit n'a plus
     * d'objet.
     */
    public static ReferralPromptState.Circuit circuitToRestore(
            ReferralPromptState state, ReferralStatus status, AccessState access, Instant now) {
        ReferralPromptState.Circuit circuit = state.circuit;
        if (circuit == null || status == null || !access.known) return null;
        if (status.isSubscriberAtPeace() || access.lifetime) return null;
        if (!access.isPaused(now)) return null;
        return circuit;
    }
}
