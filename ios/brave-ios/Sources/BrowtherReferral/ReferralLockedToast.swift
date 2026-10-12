// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Le toast d'une garde porte DEUX boutons — `devndin/docs/PARRAINAGE.md`
/// § 12.41. Jumeaux : `core/ReferralLockedToast.java` (Android),
/// `core/lockedToast.ts` (ordinateur) ; référence :
/// `darsunaa/packages/core/src/referral/locked-toast.ts`.
///
/// Un bouton unique « Soutenir dev&din » se lisait « payer » : la façon
/// gratuite, celle qu'on espère, ne vivait que dans une phrase que peu de gens
/// lisent. Les deux façons se VOIENT donc avant de toucher, avec les mots des
/// trois façons (2b), et chacune mène à SON écran.
///
/// ⭐ Seule autorité : le vrai toast et son aperçu de recette lisent tous deux
/// d'ici quels boutons poser, et où chacun mène.
public enum ReferralLockedToast {
  /// Le bouton touché — sa valeur est aussi l'`action` de
  /// `paywall_action { screen: 'locked' }` (⛔ plus `'support'`).
  public enum Button: String, Sendable, CaseIterable {
    case invite, billing
  }

  /// L'écran qu'un bouton ouvre.
  public enum Destination: String, Sendable {
    case support, billing
  }

  /// Les boutons, dans l'ordre : « Inviter un proche · gratuit » (plein), puis
  /// « Soutenir financièrement » (contour). ⛔ Le second n'existe pas là où le
  /// paiement n'est pas proposé — la phrase du toast reste vraie sans lui.
  public static func buttons(billingAvailable: Bool) -> [Button] {
    billingAvailable ? [.invite, .billing] : [.invite]
  }

  /// Où mène chaque bouton, du dessous vers le dessus. « Inviter un proche »
  /// ouvre les trois façons (2b), où l'on se demande combien de proches
  /// inviter. « Soutenir financièrement » a déjà choisi : il ouvre DIRECTEMENT
  /// l'écran de paiement — ⚠️ avec 2b DESSOUS, pour que « Retour » y ramène
  /// (⛔ ni impasse, ni fermeture sèche).
  public static func stack(for button: Button) -> [Destination] {
    switch button {
    case .invite: return [.support]
    case .billing: return [.support, .billing]
    }
  }
}
