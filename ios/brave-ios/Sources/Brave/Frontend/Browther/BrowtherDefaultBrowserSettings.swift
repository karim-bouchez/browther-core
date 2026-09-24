// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Onboarding
import UIKit

/// **Où l'on choisit son navigateur par défaut** — un seul endroit dans le code
/// pour y envoyer, et une seule façon de montrer le chemin.
///
/// 🔴 `UIApplication.openSettingsURLString` ouvre la fiche de l'app
/// (« Réseau local », « Siri », « Notifications »…) : depuis iOS 18, le choix du
/// navigateur par défaut n'y est plus — il a déménagé dans **Réglages › Apps ›
/// Apps par défaut**. On tombait donc sur une page qui ne propose PAS ce qu'on
/// vient de promettre (recette Karim, 2026-09-24).
/// ⚠️ Cette fiche reste le repli : le raccourci n'existe qu'à partir d'iOS 18.3.
///
/// ⚠️ **En build de dev, la ligne n'apparaît nulle part** : l'entitlement
/// `com.apple.developer.web-browser` n'est que dans la Release/TestFlight
/// (`docs/PARRAINAGE.md` § 4). Ce n'est pas un bug de ce code.
@MainActor
enum BrowtherDefaultBrowserSettings {

  /// L'adresse la plus proche du geste : la liste des apps par défaut si iOS la
  /// connaît, la fiche de l'app sinon.
  static var url: URL? {
    if #available(iOS 18.3, *) {
      return URL(string: UIApplication.openDefaultApplicationsSettingsURLString)
    }
    return URL(string: UIApplication.openSettingsURLString)
  }

  /// Ouvre les Réglages **avec la vidéo en incrustation** : le chemin ne se
  /// devine pas, et une vidéo flottante survit au passage dans une autre app —
  /// c'est tout l'intérêt de l'incrustation (`BrowtherDefaultBrowserVideo`).
  /// ⚠️ La vidéo part AVANT : lancée après, elle s'ouvre derrière les Réglages.
  static func openWithGuide(isDarkMode: Bool, windowScene: UIWindowScene? = nil) async {
    let scene =
      windowScene
      ?? UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
    await BrowtherDefaultBrowserVideo.presentPictureInPicture(
      isDarkMode: isDarkMode,
      windowScene: scene
    )
    guard let url else { return }
    // ⚠️ `open(_:)` a une surcharge `async` : dans un contexte asynchrone c'est
    // elle que Swift choisit, d'où le `await` (⛔ pas une attente inutile).
    await UIApplication.shared.open(url)
  }
}
