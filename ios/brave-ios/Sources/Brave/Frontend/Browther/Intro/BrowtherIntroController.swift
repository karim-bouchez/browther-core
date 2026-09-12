// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import UIKit

/// Le contenant de l'introduction : plein écran, portrait, et **impossible à
/// écarter d'un geste**. Sortir se fait par le bouton de la dernière étape —
/// sinon on se retrouve avec une introduction à moitié vue et des préférences à
/// moitié posées.
///
/// ⚠️ Plein écran **y compris sur iPad** : c'est le refus App Store du
/// 2026-06-23 (règle 2.1(a), boutons hors écran dans la carte `.inset`).
final class BrowtherIntroController: UIHostingController<BrowtherIntroView> {

  init(model: BrowtherIntroModel) {
    super.init(rootView: BrowtherIntroView(model: model))
    modalPresentationStyle = .fullScreen
    isModalInPresentation = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    .portrait
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    .default
  }
}
