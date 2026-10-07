// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

/**
 * Ce que la personne a à PERDRE avec cet appareil — **par onglet** de l'écran Parrainage. Le compte
 * se propose dans l'onglet de ce qui est en jeu, avec les mots de cet onglet (Karim, 2026-10-07) :
 * dire « mets ton parrainage à l'abri » à quelqu'un qui n'a parrainé personne mais qui est ABONNÉ ne
 * parle de rien, et ne lui dit rien là où est son abonnement.
 */
public enum ReferralAccountStake {
    /**
     * Son code est parti (un partage a abouti sur cet appareil), ou il a déjà servi. ⚠️ Un partage
     * ne crée rien côté service (§ 12.1), mais le code dicté à des proches, lui, existe : sans
     * compte, les invitations qui arriveront après un changement d'appareil iraient à un sujet que
     * plus personne ne peut ouvrir. D'où `sharedOnce`, retenu sur l'appareil.
     */
    INVITE("invite"),
    /** Au moins une invitation en cours ou validée. */
    INVITATIONS("invitations"),
    /** Elle a saisi le code d'un proche (son mois offert, sa progression). */
    REFEREE("referee"),
    /** Un abonnement court. */
    PAID("paid");

    public final String rawValue;

    ReferralAccountStake(String rawValue) {
        this.rawValue = rawValue;
    }
}
