/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import androidx.annotation.Nullable;

import org.chromium.chrome.browser.browther_referral.core.ReferralPrompt;
import org.chromium.chrome.browser.browther_referral.core.ReminderCase;

import java.util.Objects;

/**
 * Les écrans du flow — docs/PARRAINAGE.md § 3 (numérotation de la maquette), pendant de
 * l'{@code enum ReferralScreen} iOS. Une valeur immuable : le type + ses paramètres.
 */
public final class ReferralScreen {
    public enum Kind {
        /** O — ⚠️ en APERÇU seulement : il vit dans l'introduction. */
        WELCOME,
        /** 0 — ⭐ c'est son affichage qui démarre le mois. */
        ANNOUNCE,
        /**
         * 2 — J0. {@code chosen} = ouvert par la personne elle-même (le « Débloquer » du panneau
         * Sawtunaa) : la fenêtre se ferme alors normalement (§ 12.16).
         */
        PAUSED,
        /** 2b — les trois façons. {@code locked} = ouvert depuis J0 (circuit fermé, § 12.16). */
        SUPPORT,
        /** 4 — inviter, par-dessus 2b. {@code shared} = un partage a abouti : fenêtre libérée. */
        INVITE,
        /** 7 — soutenir financièrement : sur Android, la PORTE FACTICE (§ 12.27). */
        BILLING,
        /** 7 ter — « C'est cadeau ! » (§ 12.27) : le mois offert au toucher de « Je soutiens ». */
        GIFT,
        /** 1 — J−10 / J−3 de la première fin (feuille). */
        ENDING,
        /** 3 — les rappels suivants (feuille). */
        REMINDER,
        /** 8 — une invitation validée (feuille). */
        VALIDATED,
        /** 8 bis — côté filleul : sa validation est tombée (feuille). */
        REFEREE_DONE
    }

    public final Kind kind;
    public final boolean chosen;
    public final boolean locked;
    public final boolean shared;
    public final int daysLeft;
    public final @Nullable ReminderCase reminderCase;
    public final int months;
    public final @Nullable String until;
    public final boolean lifetime;
    /** GIFT : le mois vient d'être offert (confettis, promesse) ou l'avait déjà été. */
    public final boolean granted;

    private ReferralScreen(
            Kind kind,
            boolean chosen,
            boolean locked,
            boolean shared,
            int daysLeft,
            @Nullable ReminderCase reminderCase,
            int months,
            @Nullable String until,
            boolean lifetime,
            boolean granted) {
        this.kind = kind;
        this.chosen = chosen;
        this.locked = locked;
        this.shared = shared;
        this.daysLeft = daysLeft;
        this.reminderCase = reminderCase;
        this.months = months;
        this.until = until;
        this.lifetime = lifetime;
        this.granted = granted;
    }

    private static ReferralScreen of(Kind kind) {
        return new ReferralScreen(kind, false, false, false, 0, null, 0, null, false, false);
    }

    public static ReferralScreen welcome() {
        return of(Kind.WELCOME);
    }

    public static ReferralScreen announce() {
        return of(Kind.ANNOUNCE);
    }

    public static ReferralScreen paused(boolean chosen) {
        return new ReferralScreen(Kind.PAUSED, chosen, false, false, 0, null, 0, null, false, false);
    }

    public static ReferralScreen support(boolean locked) {
        return new ReferralScreen(Kind.SUPPORT, false, locked, false, 0, null, 0, null, false, false);
    }

    public static ReferralScreen invite(boolean shared) {
        return new ReferralScreen(Kind.INVITE, false, false, shared, 0, null, 0, null, false, false);
    }

    public static ReferralScreen billing() {
        return of(Kind.BILLING);
    }

    public static ReferralScreen gift(boolean granted, @Nullable String until) {
        return new ReferralScreen(Kind.GIFT, false, false, false, 0, null, 0, until, false, granted);
    }

    public static ReferralScreen ending(int daysLeft) {
        return new ReferralScreen(Kind.ENDING, false, false, false, daysLeft, null, 0, null, false, false);
    }

    public static ReferralScreen reminder(int daysLeft, ReminderCase reminderCase) {
        return new ReferralScreen(
                Kind.REMINDER, false, false, false, daysLeft, reminderCase, 0, null, false, false);
    }

    public static ReferralScreen validated(int months, @Nullable String until, boolean lifetime) {
        return new ReferralScreen(
                Kind.VALIDATED, false, false, false, 0, null, months, until, lifetime, false);
    }

    public static ReferralScreen refereeDone() {
        return of(Kind.REFEREE_DONE);
    }

    /** L'écran d'une sollicitation décidée par {@link ReferralPrompt#decide}. */
    public static ReferralScreen of(ReferralPrompt.Solicitation decision) {
        switch (decision.kind) {
            case ANNOUNCE:
                return announce();
            case PAUSED:
                return paused(false);
            case ENDING:
                return ending(decision.daysLeft);
            case REMINDER:
            default:
                return reminder(decision.daysLeft, decision.reminderCase);
        }
    }

    /**
     * La clé d'analytique ({@code paywall_shown {screen}}) — ⛔ jamais un texte affiché, ⛔ jamais
     * le numéro de la maquette (§ 13.2). Les mêmes que sur iOS et desktop, plus {@code gift}.
     */
    public String analyticsName() {
        switch (kind) {
            case WELCOME:
                return "welcome";
            case ANNOUNCE:
                return "announce";
            case PAUSED:
                return "paused";
            case SUPPORT:
                return "support";
            case INVITE:
                return "invite";
            case BILLING:
                return "billing";
            case GIFT:
                return "gift";
            case ENDING:
                return "ending";
            case REMINDER:
                return "reminder";
            case VALIDATED:
                return "validated";
            case REFEREE_DONE:
            default:
                return "referee_done";
        }
    }

    /**
     * 1, 3, 8, 8 bis : des FEUILLES à fermeture classique (§ 12.14, § 12.23) — ⛔ deux feuilles
     * empilées font un bouton mort, d'où le plein écran pour le reste.
     */
    public boolean isSheet() {
        return kind == Kind.ENDING
                || kind == Kind.REMINDER
                || kind == Kind.VALIDATED
                || kind == Kind.REFEREE_DONE;
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof ReferralScreen)) return false;
        ReferralScreen o = (ReferralScreen) other;
        return kind == o.kind
                && chosen == o.chosen
                && locked == o.locked
                && shared == o.shared
                && daysLeft == o.daysLeft
                && reminderCase == o.reminderCase
                && months == o.months
                && Objects.equals(until, o.until)
                && lifetime == o.lifetime
                && granted == o.granted;
    }

    @Override
    public int hashCode() {
        return Objects.hash(kind, chosen, locked, shared, daysLeft, reminderCase, months, until);
    }
}
