// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * Le toast d'une garde porte DEUX boutons — `devndin/docs/PARRAINAGE.md` § 12.41, port de
 * `BrowtherReferral/ReferralLockedToast.swift`. Jumeau de l'ordinateur : `core/lockedToast.ts` ;
 * référence : `darsunaa/packages/core/src/referral/locked-toast.ts`.
 *
 * <p>Un bouton unique « Soutenir dev&din » se lisait « payer » : la façon gratuite, celle qu'on
 * espère, ne vivait que dans une phrase que peu de gens lisent. Les deux façons se VOIENT donc
 * avant de toucher, avec les mots des trois façons (2b), et chacune mène à SON écran.
 *
 * <p>⭐ Seule autorité : le vrai toast et son aperçu de recette lisent tous deux d'ici quels
 * boutons poser, et où chacun mène.
 */
public final class ReferralLockedToast {
    private ReferralLockedToast() {}

    /**
     * Le bouton touché — {@link #rawValue} est aussi l'{@code action} de {@code paywall_action
     * {screen: 'locked'}} (⛔ plus {@code 'support'}).
     */
    public enum Button {
        INVITE("invite"),
        BILLING("billing");

        public final String rawValue;

        Button(String rawValue) {
            this.rawValue = rawValue;
        }
    }

    /** L'écran qu'un bouton ouvre. */
    public enum Destination {
        SUPPORT,
        BILLING
    }

    /**
     * Les boutons, dans l'ordre : « Inviter un proche · gratuit » (plein), puis « Soutenir
     * financièrement » (contour). ⛔ Le second n'existe pas là où le paiement n'est pas proposé — la
     * phrase du toast reste vraie sans lui. ⚠️ Sur Android, « payer » est la porte factice
     * (§ 12.27) : le bouton y mène.
     */
    public static List<Button> buttons(boolean billingAvailable) {
        return billingAvailable
                ? Collections.unmodifiableList(Arrays.asList(Button.INVITE, Button.BILLING))
                : Collections.singletonList(Button.INVITE);
    }

    /**
     * Où mène chaque bouton, du dessous vers le dessus. « Inviter un proche » ouvre les trois
     * façons (2b), où l'on se demande combien de proches inviter. « Soutenir financièrement » a
     * déjà choisi : il ouvre DIRECTEMENT l'écran de paiement — ⚠️ avec 2b DESSOUS, pour que
     * « Retour » y ramène (⛔ ni impasse, ni fermeture sèche).
     */
    public static List<Destination> stack(Button button) {
        return button == Button.BILLING
                ? Collections.unmodifiableList(Arrays.asList(Destination.SUPPORT, Destination.BILLING))
                : Collections.singletonList(Destination.SUPPORT);
    }
}
