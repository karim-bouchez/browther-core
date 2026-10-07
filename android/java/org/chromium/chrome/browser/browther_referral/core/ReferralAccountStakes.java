// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.Objects;

/**
 * Ce qui est en jeu, onglet par onglet ({@link ReferralAccountStake}) — c'est LÀ que le compte se
 * propose, avec les mots de l'onglet (§ 7.1 du doc commun, « L'écran 6 : une rangée PAR ONGLET »).
 * Port de `ReferralAccountStakes` (`ReferralAccountRules.swift`).
 */
public final class ReferralAccountStakes {
    public final boolean invite;
    public final boolean invitations;
    public final boolean referee;
    public final boolean paid;

    /**
     * Un abonnement a existé, même éteint : il compte pour « quelque chose à mettre à l'abri », pas
     * pour la rangée de « Soutenir ».
     */
    private final boolean everPaid;

    /**
     * @param status le statut connu, ou {@code null} — ⚠️ le partage compte même sans statut : le
     *     service n'en sait rien.
     * @param sharedOnce un partage a abouti sur CET appareil (`ReferralStorage.sharedOnce`).
     */
    public ReferralAccountStakes(ReferralStatus status, boolean sharedOnce) {
        boolean known = false;
        if (status != null) {
            for (InvitationItem item : status.invitations.items) {
                if (item.status != InvitationStatus.SENT) {
                    known = true;
                    break;
                }
            }
        }
        boolean earned =
                status != null
                        && (status.access.lifetime
                                || status.milestones.validated > 0
                                || status.milestones.monthsEarned > 0);
        this.invite = sharedOnce || known || earned;
        this.invitations = known;
        this.referee = status != null && status.referredBy != null;
        this.paid = status != null && status.subscription.active;
        this.everPaid = status != null && status.subscription.everPaid;
    }

    public boolean has(ReferralAccountStake stake) {
        switch (stake) {
            case INVITE:
                return invite;
            case INVITATIONS:
                return invitations;
            case REFEREE:
                return referee;
            case PAID:
            default:
                return paid;
        }
    }

    /**
     * Y a-t-il quoi que ce soit à mettre à l'abri ? C'est ce qui fait passer le texte du compte de
     * « retrouver un compte » (qui arrive sur un appareil neuf n'a rien, par définition) à « mettre
     * à l'abri ». ⚠️ Le mois de l'annonce seul ne compte pas : tout le monde l'a.
     */
    public boolean hasSomethingToShelter() {
        return invite || invitations || referee || paid || everPaid;
    }

    @Override
    public boolean equals(Object other) {
        if (!(other instanceof ReferralAccountStakes)) return false;
        ReferralAccountStakes o = (ReferralAccountStakes) other;
        return invite == o.invite
                && invitations == o.invitations
                && referee == o.referee
                && paid == o.paid
                && everPaid == o.everPaid;
    }

    @Override
    public int hashCode() {
        return Objects.hash(invite, invitations, referee, paid, everPaid);
    }
}
