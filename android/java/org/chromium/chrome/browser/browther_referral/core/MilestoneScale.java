// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Objects;

/**
 * Les paliers du parrainage — `docs/PARRAINAGE.md` § 5.1.
 *
 * <pre>
 * | Invitations validées | Récompense       | Cumul |
 * | 1                    | 1 mois           | 1     |
 * | 3                    | +1 mois de bonus | 4     |
 * | 5                    | +3 mois de bonus | 9     |
 * | 7                    | +5 mois de bonus | 16    |
 * | 10                   | à vie            | à vie |
 * </pre>
 *
 * <p>⭐ **Le barème se LIT dans le statut** (`milestones.bonuses` + `lifetimeAt`, brief B bis), ⛔
 * il ne se recopie pas : c'est le service qui crédite, et un barème recopié finirait par dire autre
 * chose que lui. {@link #common} n'est que le repli d'un statut qui ne le porte pas (aucun statut
 * reçu).
 *
 * <p>La jauge (écrans 2b, 4, 6) est un **jouet** : on la tire pour voir ce que rapporteraient plus
 * d'invitations, sans rien enregistrer. ⛔ Jamais pour créditer.
 */
public final class MilestoneScale {
    /** Les bonus, croissants. La base (1 mois par invitation validée) n'y figure pas. */
    public final List<MilestoneBonus> bonuses;
    /** Invitations validées qui débloquent l'accès à vie. */
    public final int lifetimeAt;

    public MilestoneScale(List<MilestoneBonus> bonuses, int lifetimeAt) {
        this.bonuses = Collections.unmodifiableList(new ArrayList<>(bonuses));
        this.lifetimeAt = lifetimeAt;
    }

    public static final MilestoneScale common =
            new MilestoneScale(
                    Arrays.asList(
                            new MilestoneBonus(3, 1),
                            new MilestoneBonus(5, 3),
                            new MilestoneBonus(7, 5)),
                    10);

    /**
     * Le barème du statut, s'il est lisible — sinon le commun. ⚠️ Un barème incohérent (bonus
     * au-delà de « à vie », valeurs négatives) est ÉCARTÉ plutôt qu'affiché : une jauge qui
     * promettrait n'importe quoi serait pire qu'une jauge au barème commun.
     */
    public MilestoneScale(ReferralStatus status) {
        MilestoneScale scale = common;
        if (status != null && status.milestones.bonuses != null && status.milestones.lifetimeAt >= 2) {
            int lifetimeAt = status.milestones.lifetimeAt;
            List<MilestoneBonus> clean = new ArrayList<>();
            for (MilestoneBonus bonus : status.milestones.bonuses) {
                if (bonus.at > 1 && bonus.at < lifetimeAt && bonus.months > 0) clean.add(bonus);
            }
            clean.sort(Comparator.comparingInt(b -> b.at));
            if (clean.size() == status.milestones.bonuses.size()) {
                scale = new MilestoneScale(clean, lifetimeAt);
            }
        }
        this.bonuses = scale.bonuses;
        this.lifetimeAt = scale.lifetimeAt;
    }

    /** Les seuls mois de BONUS gagnés avec {@code n} invitations validées — « dont +X ». */
    public int bonusMonths(int n) {
        int total = 0;
        for (MilestoneBonus bonus : bonuses) {
            if (bonus.at <= n) total += bonus.months;
        }
        return total;
    }

    /** Total des mois gagnés avec {@code n} invitations validées (hors « à vie »). */
    public int totalMonths(int n) {
        return n <= 0 ? 0 : n + bonusMonths(n);
    }

    public static final class Next {
        public final int at;
        public final int bonusMonths;
        public final int remaining;
        public final boolean lifetime;

        public Next(int at, int bonusMonths, int remaining, boolean lifetime) {
            this.at = at;
            this.bonusMonths = bonusMonths;
            this.remaining = remaining;
            this.lifetime = lifetime;
        }

        @Override
        public boolean equals(Object other) {
            if (!(other instanceof Next)) return false;
            Next o = (Next) other;
            return at == o.at && bonusMonths == o.bonusMonths && remaining == o.remaining && lifetime == o.lifetime;
        }

        @Override
        public int hashCode() {
            return Objects.hash(at, bonusMonths, remaining, lifetime);
        }
    }

    /** Le prochain palier à viser (Swift `next(after:)`). {@code null} quand l'accès à vie est déjà atteint. */
    public Next next(int after) {
        if (after >= lifetimeAt) return null;
        for (MilestoneBonus bonus : bonuses) {
            if (bonus.at > after) return new Next(bonus.at, bonus.months, bonus.at - after, false);
        }
        return new Next(lifetimeAt, 0, lifetimeAt - after, true);
    }

    /**
     * Ce que la jauge affiche pour une position donnée — § 2.2 : « Si j'invite N proches, je gagne M
     * mois, dont +X de bonus ». Au palier « à vie », ⭐ il n'y a plus de nombre de mois : c'est « à
     * vie », et rien d'autre.
     */
    public static final class Reading {
        public final int invitations;
        public final int months;
        public final int bonusMonths;
        public final boolean lifetime;

        public Reading(int invitations, int months, int bonusMonths, boolean lifetime) {
            this.invitations = invitations;
            this.months = months;
            this.bonusMonths = bonusMonths;
            this.lifetime = lifetime;
        }

        @Override
        public boolean equals(Object other) {
            if (!(other instanceof Reading)) return false;
            Reading o = (Reading) other;
            return invitations == o.invitations && months == o.months && bonusMonths == o.bonusMonths && lifetime == o.lifetime;
        }

        @Override
        public int hashCode() {
            return Objects.hash(invitations, months, bonusMonths, lifetime);
        }
    }

    public Reading reading(double invitations) {
        // `rounded()` de Swift arrondit la moitié en s'éloignant de zéro, comme Math.round ici (positif).
        int n = (int) Math.max(0, Math.min(lifetimeAt, Math.round(invitations)));
        if (n >= lifetimeAt) return new Reading(n, 0, 0, true);
        return new Reading(n, totalMonths(n), bonusMonths(n), false);
    }

    /**
     * Le palier qu'une invitation validée a fait franchir, d'après les mois qu'elle a crédités (la
     * ligne ★ de « Mes invitations ») : le service marque `milestone` quand le mois porte un bonus,
     * et `creditedMonths` = 1 + ce bonus. {@code null} si rien ne correspond — la ligne ★ ne
     * s'invente pas. (Swift `milestone(forCredit:)`.)
     */
    public MilestoneBonus milestone(int forCredit) {
        for (MilestoneBonus bonus : bonuses) {
            if (bonus.months == forCredit - 1) return bonus;
        }
        return null;
    }

    // MARK: - La démo de la jauge (§ 12.4)

    /**
     * **La démo** : le curseur se tire tout seul **à chaque fois qu'une jauge est affichée** (écran
     * 6, trois façons, écran 4), **jusqu'au jour où la personne l'a tiré ELLE-MÊME jusqu'au bout** —
     * « à vie », là où partent les confettis. À partir de là, plus jamais de démo, nulle part (règle de
     * Karim, 2026-09-21). ⚠️ Toucher la jauge sans aller au bout ne suffit PAS.
     *
     * <p>Jusqu'où elle tire : **5** (assez loin pour faire apparaître un bonus) ; au-delà, jusqu'au
     * palier suivant ; {@code null} quand il n'y a plus rien à viser.
     */
    public Integer demoTarget(int from) {
        int target = 5;
        if (from < target) return Math.min(target, lifetimeAt);
        Next next = next(from);
        return next == null ? null : next.at;
    }

    /**
     * La personne vient-elle de montrer qu'elle a compris ? ⚠️ Au DOIGT seulement : la démo qui
     * monte, ou une invitation validée qui fait bouger la jauge, ne disent rien de ce qu'elle a vu.
     */
    public boolean understood(int value, boolean byHand) {
        return byHand && value >= lifetimeAt;
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof MilestoneScale)) return false;
        MilestoneScale o = (MilestoneScale) other;
        return lifetimeAt == o.lifetimeAt && bonuses.equals(o.bonuses);
    }

    @Override
    public int hashCode() {
        return Objects.hash(bonuses, lifetimeAt);
    }
}
