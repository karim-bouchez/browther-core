// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AVKit
import SwiftUI
import UIKit

/// La vidéo « comment définir Browther par défaut », en incrustation au-dessus
/// des Réglages d'iOS.
///
/// Elle a été tournée sur appareil (`set-default-pip-{light,dark}.mp4`) parce
/// que le chemin dans les Réglages d'iOS ne se devine pas : on quitte l'app, et
/// sans elle on cherche. C'est la seule raison pour laquelle l'incrustation
/// existe — elle survit au passage dans une autre app, pas une vue SwiftUI.
///
/// Exposé ici parce que la vidéo vit dans les ressources de CE module, alors
/// que l'introduction Browther qui l'utilise vit dans le module Brave.
@MainActor
public enum BrowtherDefaultBrowserVideo {

  /// Démarre l'incrustation, si l'appareil la supporte. Ne fait rien sinon —
  /// l'appelant enchaîne de toute façon sur l'ouverture des Réglages.
  public static func presentPictureInPicture(
    isDarkMode: Bool,
    windowScene: UIWindowScene?
  ) async {
    guard
      AVPictureInPictureController.isPictureInPictureSupported(),
      let windowScene,
      let videoFileURL = Bundle.module.url(
        forResource: "set-default-pip-\(isDarkMode ? "dark" : "light")",
        withExtension: "mp4",
        subdirectory: "Videos"
      )
    else { return }

    var controller: DefaultBrowserPictureInPictureController?
    controller = DefaultBrowserPictureInPictureController(
      videoURL: videoFileURL,
      windowScene: windowScene,
      onStop: {
        // On garde le contrôleur en vie jusqu'à l'arrêt de l'incrustation,
        // que l'arrêt vienne de l'utilisateur ou du retour au premier plan.
        _ = controller
        controller = nil
      }
    )
    await controller?.start()
  }
}
