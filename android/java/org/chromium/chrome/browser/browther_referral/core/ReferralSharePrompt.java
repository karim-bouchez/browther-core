// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.time.Instant;

/**
 * **Le partage proposé** — `docs/PARRAINAGE.md` § 12.45 et `docs/PROMPT-partage-propose.md`
 * (décidé par Karim le 2026-10-12). Port de la règle de Darsunaa
 * (`packages/core/src/referral/share-prompt.ts`), le premier client.
 *
 * <p>Le partage de l'écran Parrainage s'ouvre de lui-même, à un moment de mérite, avec un titre
 * au-dessus des onglets. Ce qui le distingue des autres écrans ({@link ReferralPrompt}) :
 *
 * <ul>
 *   <li>🔴 **L'abonné et l'accès à vie le voient AUSSI** — sans la phrase du gain, avec « Ne plus
 *       me redemander ». D'où une décision SÉPARÉE de {@link ReferralPrompt#decide}, qui s'arrête à
 *       eux dès sa première ligne.
 *   <li>⛔ **Il n'est pas daté** : il passe APRÈS tout écran daté, prend le verrou du jour, mais ne
 *       fait céder la journée à personne.
 *   <li>⛔ **Jamais pendant la pause** : J0 y est le créneau de sollicitation.
 * </ul>
 *
 * <p>Toutes les fonctions rendent un NOUVEL état (⛔ l'état reçu n'est jamais modifié).
 */
public final class ReferralSharePrompt {
    private ReferralSharePrompt() {}

    /** Première fois : ce nombre de jours après l'annonce (écran 0). */
    public static final int firstAfterDays = 7;
    /** Ensuite : au plus une fois par période — et le silence après un partage abouti. */
    public static final int gapDays = 30;
    /** Après deux fermetures d'affilée, la période s'allonge. */
    public static final int longGapDays = 60;
    public static final int dismissalsForLongGap = 2;
    /**
     * ⛔ Jamais la même semaine qu'un autre écran du parrainage — **dans les deux sens** (Karim,
     * 2026-10-13) : ni dans les 7 jours qui suivent un écran, ni dans les 7 jours qui précèdent un
     * rappel. Pendant le seul mois offert, il n'a donc qu'une fenêtre, du 7ᵉ au 13ᵉ jour.
     */
    public static final int quietDays = 7;

    /**
     * Le compteur (Karim, 2026-10-14 : « le nombre d'h de musique retirées ainsi que le nombre de
     * personnes floutées, sauf si on a vraiment très très peu ») : en dessous de ces seuils, la
     * moitié de phrase se tait ; les deux en dessous → le titre « Browther t'est utile ? ».
     */
    public static final int minMusicHours = 1;

    public static final int minPersons = 20;

    private static final long DAY_MS = 86_400_000L;

    /** Ce qui change le texte et les sorties. */
    public enum Profile {
        /** Des mois offerts ou gagnés : la phrase du gain, « Plus tard ». */
        OFFERED("offered"),
        /** Un abonnement court : ⛔ pas la phrase du gain, « Ne plus me redemander » en plus. */
        PAID("paid"),
        /** L'accès à vie : idem, et son silence est définitif. */
        LIFETIME("lifetime");

        public final String rawValue;

        Profile(String rawValue) {
            this.rawValue = rawValue;
        }

        /** « Ne plus me redemander » ne se propose qu'à qui a payé. */
        public boolean canMute() {
            return this != OFFERED;
        }
    }

    /** L'onglet ouvert — les valeurs de `opened_on`. */
    public enum Tab {
        STATUS("status"),
        MESSAGE("message");

        public final String wire;

        Tab(String wire) {
            this.wire = wire;
        }
    }

    /** Pourquoi il ne sort pas — rendu à l'outil de recette (« il se tait à raison »). */
    public enum Silence {
        UNKNOWN("unknown"),
        NO_MERIT("no_merit"),
        PAUSED("paused"),
        BEFORE_ANNOUNCE("before_announce"),
        MUTED("muted"),
        TOO_EARLY("too_early"),
        RECENT_PROMPT("recent_prompt"),
        RECENT_SHARE("recent_share"),
        RECENT_SCREEN("recent_screen"),
        REMINDER_SOON("reminder_soon");

        public final String rawValue;

        Silence(String rawValue) {
            this.rawValue = rawValue;
        }
    }

    public static final class Decision {
        public final Profile profile;
        public final Tab openedOn;

        public Decision(Profile profile, Tab openedOn) {
            this.profile = profile;
            this.openedOn = openedOn;
        }
    }

    /** La décision, AVEC sa raison quand elle est négative. */
    public static final class Verdict {
        /** {@code null} = il se tait, et {@link #reason} dit pourquoi. */
        public final Decision decision;

        public final Silence reason;

        private Verdict(Decision decision, Silence reason) {
            this.decision = decision;
            this.reason = reason;
        }

        public boolean due() {
            return decision != null;
        }

        static Verdict due(Decision decision) {
            return new Verdict(decision, null);
        }

        static Verdict silent(Silence reason) {
            return new Verdict(null, reason);
        }
    }

    public static final class Input {
        public final ReferralPromptState state;
        public final ReferralStatus status;
        public final AccessState access;
        /** ⭐ Le produit vient de rendre son service (§ 3.1) — jamais à l'ouverture. */
        public final boolean atMeritMoment;

        public final Instant now;

        public Input(
                ReferralPromptState state,
                ReferralStatus status,
                AccessState access,
                boolean atMeritMoment,
                Instant now) {
            this.state = state;
            this.status = status;
            this.access = access;
            this.atMeritMoment = atMeritMoment;
            this.now = now;
        }
    }

    public static Profile profile(ReferralStatus status, AccessState access) {
        if (access.lifetime) return Profile.LIFETIME;
        return status.subscription.active ? Profile.PAID : Profile.OFFERED;
    }

    /**
     * ⭐ **L'onglet ouvert alterne** d'un affichage à l'autre : « Statut WhatsApp » la première
     * fois, « Message » la suivante. ⛔ Ce n'est pas un test sur le prix (§ 11.2). Sans WhatsApp,
     * l'appelant impose « Message » ({@link #tab(int, boolean)}).
     */
    public static Tab tab(int shownSoFar) {
        return shownSoFar % 2 == 0 ? Tab.STATUS : Tab.MESSAGE;
    }

    /** Browther sait si WhatsApp est installé (Karim, 2026-10-14) : sans lui, toujours « Message ». */
    public static Tab tab(int shownSoFar, boolean hasWhatsApp) {
        return hasWhatsApp ? tab(shownSoFar) : Tab.MESSAGE;
    }

    private static Double elapsedDays(String since, Instant now) {
        Instant at = ReferralDate.parse(since);
        return at == null ? null : (now.toEpochMilli() - at.toEpochMilli()) / (double) DAY_MS;
    }

    private static int orZero(Integer value) {
        return value == null ? 0 : value;
    }

    private static ReferralPromptState.SharePrompt own(ReferralPromptState state) {
        return state.sharePrompt == null ? new ReferralPromptState.SharePrompt() : state.sharePrompt;
    }

    public static Verdict explain(Input input) {
        ReferralPromptState state = input.state;
        ReferralStatus status = input.status;
        AccessState access = input.access;
        Instant now = input.now;

        // Trois états, jamais deux.
        if (!access.known || status == null) return Verdict.silent(Silence.UNKNOWN);

        Profile profile = profile(status, access);
        ReferralPromptState.SharePrompt own = own(state);

        if (profile == Profile.OFFERED) {
            // ⛔ Jamais pendant la pause : J0 y est le créneau de sollicitation.
            if (access.isPaused(now)) return Verdict.silent(Silence.PAUSED);
            // Avant l'annonce, la personne ne sait pas ce qu'est le parrainage.
            if (access.beforeTrial || !Boolean.TRUE.equals(state.announced)) {
                return Verdict.silent(Silence.BEFORE_ANNOUNCE);
            }
        }

        if ("lifetime".equals(own.muted) && access.lifetime) return Verdict.silent(Silence.MUTED);
        if ("subscription".equals(own.muted) && status.subscription.active) {
            return Verdict.silent(Silence.MUTED);
        }

        String start = status.trial.startedAt != null ? status.trial.startedAt : own.since;
        Double sinceStart = elapsedDays(start, now);
        if (sinceStart == null) return Verdict.silent(Silence.BEFORE_ANNOUNCE);
        if (sinceStart < firstAfterDays) return Verdict.silent(Silence.TOO_EARLY);

        int gap = orZero(own.dismissedInRow) >= dismissalsForLongGap ? longGapDays : gapDays;
        Double sinceShown = elapsedDays(own.shownAt, now);
        if (sinceShown != null && sinceShown < gap) return Verdict.silent(Silence.RECENT_PROMPT);

        Double sinceShared = elapsedDays(own.sharedAt, now);
        if (sinceShared != null && sinceShared < gapDays) return Verdict.silent(Silence.RECENT_SHARE);

        Double sinceScreen = elapsedDays(state.lastScreenAt, now);
        if (sinceScreen != null && sinceScreen < quietDays) return Verdict.silent(Silence.RECENT_SCREEN);

        // ⚠️ Un abonné en paix n'a pas de rappel à venir : son échéance se renouvelle.
        if (!access.lifetime && !status.isSubscriberAtPeace()) {
            Integer left = access.daysLeft(now);
            int furthest = 0;
            for (int stage : ReferralPrompt.reminderStages) furthest = Math.max(furthest, stage);
            if (left != null && left <= furthest + quietDays) {
                return Verdict.silent(Silence.REMINDER_SOON);
            }
        }

        // ⚠️ En dernier : la recette lit ainsi « il sortirait, au moment de mérite ».
        if (!input.atMeritMoment) return Verdict.silent(Silence.NO_MERIT);

        return Verdict.due(new Decision(profile, tab(orZero(own.count))));
    }

    public static Decision decide(Input input) {
        return explain(input).decision;
    }

    // MARK: - Le compteur au-dessus des onglets

    /** La phrase du compteur — laquelle, et ses deux nombres. */
    public static final class Headline {
        public enum Kind {
            /** « Browther a retiré {hours} de musique et flouté {persons} pour toi. » */
            BOTH,
            /** « Browther a retiré {hours} de musique pour toi. » */
            MUSIC,
            /** « Browther a flouté {persons} pour toi. » */
            BLUR,
            /** « Browther t'est utile ? » */
            NONE
        }

        public final Kind kind;
        public final long hours;
        public final long persons;

        Headline(Kind kind, long hours, long persons) {
            this.kind = kind;
            this.hours = hours;
            this.persons = persons;
        }
    }

    /** Totaux À VIE de l'appareil. ⛔ Aucun seuil dans un écran : il est ici. */
    public static Headline headline(long musicSecondsTotal, long personsBlurredTotal) {
        long hours = Math.max(0, musicSecondsTotal) / 3600;
        long persons = Math.max(0, personsBlurredTotal);
        boolean music = hours >= minMusicHours;
        boolean blur = persons >= minPersons;
        Headline.Kind kind =
                music && blur
                        ? Headline.Kind.BOTH
                        : music ? Headline.Kind.MUSIC : blur ? Headline.Kind.BLUR : Headline.Kind.NONE;
        return new Headline(kind, hours, persons);
    }

    // MARK: - Ce que l'affichage et les gestes écrivent

    private static ReferralPromptState with(
            ReferralPromptState state, ReferralPromptState.SharePrompt own) {
        ReferralPromptState next = state.copy();
        next.sharePrompt = own;
        return next;
    }

    /**
     * À chaque statut reçu : pose le départ des 7 jours pour qui n'a jamais vu l'annonce (abonné,
     * accès à vie), et lève un « Ne plus me redemander » dont l'abonnement s'est éteint. Rend le
     * MÊME objet quand rien ne change.
     */
    public static ReferralPromptState sync(
            ReferralPromptState state, ReferralStatus status, AccessState access, Instant now) {
        ReferralPromptState.SharePrompt own = own(state);
        ReferralPromptState.SharePrompt next = null;
        if (status.trial.startedAt == null
                && own.since == null
                && profile(status, access) != Profile.OFFERED) {
            next = own.copy();
            next.since = ReferralDate.string(now);
        }
        if ("subscription".equals(own.muted) && !status.subscription.active) {
            if (next == null) next = own.copy();
            next.muted = null;
        }
        return next == null ? state : with(state, next);
    }

    /** Le partage proposé vient d'être affiché. */
    public static ReferralPromptState markShown(ReferralPromptState state, Instant now) {
        ReferralPromptState.SharePrompt next = own(state).copy();
        next.shownAt = ReferralDate.string(now);
        next.count = orZero(next.count) + 1;
        return with(state, next);
    }

    /**
     * Refermé (« Plus tard », croix, glissé, retour). ⚠️ Refermer APRÈS avoir partagé n'est pas une
     * fermeture : le partage a eu lieu.
     */
    public static ReferralPromptState markDismissed(ReferralPromptState state) {
        ReferralPromptState.SharePrompt own = own(state);
        Instant shared = ReferralDate.parse(own.sharedAt);
        Instant shown = ReferralDate.parse(own.shownAt);
        if (shared != null && shown != null && !shared.isBefore(shown)) return state;
        ReferralPromptState.SharePrompt next = own.copy();
        next.dismissedInRow = orZero(own.dismissedInRow) + 1;
        return with(state, next);
    }

    /** « Ne plus me redemander » — proposé à l'abonné et à l'accès à vie seulement. */
    public static ReferralPromptState markMuted(ReferralPromptState state, Profile profile) {
        if (profile == Profile.OFFERED) return state;
        ReferralPromptState.SharePrompt next = own(state).copy();
        next.muted = profile == Profile.LIFETIME ? "lifetime" : "subscription";
        return with(state, next);
    }

    /**
     * Un partage a abouti, **d'où qu'il vienne** (écran Parrainage, trois façons, cadeau, partage
     * proposé) : 30 jours de silence, et les fermetures repartent de zéro.
     */
    public static ReferralPromptState markShareAchieved(ReferralPromptState state, Instant now) {
        ReferralPromptState.SharePrompt next = own(state).copy();
        next.sharedAt = ReferralDate.string(now);
        next.dismissedInRow = 0;
        return with(state, next);
    }

    /**
     * Un AUTRE écran du parrainage vient de venir à la personne (annonce, rappels, J0, invitation
     * validée) : le partage proposé se tait une semaine.
     */
    public static ReferralPromptState markReferralScreenShown(ReferralPromptState state, Instant now) {
        ReferralPromptState next = state.copy();
        next.lastScreenAt = ReferralDate.string(now);
        return next;
    }

    /**
     * 🧪 Recette : « Réarmer le partage proposé » sur un onglet — efface ce qui le fait taire (sauf
     * l'annonce et la pause, qui sont l'état du service) et pose le compte qui ouvre CET onglet.
     */
    public static ReferralPromptState rearmForRecette(
            ReferralPromptState state, Tab tab, Instant now) {
        ReferralPromptState.SharePrompt next = new ReferralPromptState.SharePrompt();
        next.count = tab == Tab.STATUS ? 0 : 1;
        next.since = ReferralDate.string(now.minusMillis((firstAfterDays + 1) * DAY_MS));
        ReferralPromptState out = with(state, next);
        out.lastScreenAt = null;
        return out;
    }
}
