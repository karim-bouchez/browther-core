// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import UIKit

/// Un bouton de barre d'outils qui porte le **dot de statut** de Browther.
///
/// La géométrie est celle de macOS (`BrowtherStatusDotImageSource`) : un disque
/// de **40 % de la largeur de l'icône** — 8 dip pour une icône de 20 —, posé
/// **entièrement à l'intérieur** de son coin bas-droite, cerné de blanc.
///
/// ⚠️ Il se cale sur l'`imageView`, jamais sur le bouton. Le bouton est plus
/// large que son icône et ses marges changent avec la barre : accroché à lui,
/// le dot flottait loin du coin et paraissait plus gros qu'il n'est. Et comme
/// UIKit positionne l'`imageView` par frames et non par contraintes, le calcul
/// se fait ici, à chaque passe de layout.
class BrowtherBadgedToolbarButton: ToolbarButton {
  /// Sa couleur dit l'état : rouge éteint, vert allumé, ambre en accès
  /// anticipé (cf. `TopToolbarView.featureBadgeColor`).
  let statusBadge = UIView()

  /// Part de la largeur de l'icône occupée par le dot. ⛔ Ne pas s'en écarter
  /// sans revoir macOS *et* l'introduction : les trois doivent rendre pareil.
  private static let badgeRatio: CGFloat = 0.4

  override init() {
    super.init()
    statusBadge.isUserInteractionEnabled = false
    statusBadge.layer.borderWidth = 1
    statusBadge.layer.borderColor = UIColor.white.cgColor
    addSubview(statusBadge)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let iconFrame = imageView?.frame, iconFrame.width > 0 else {
      statusBadge.isHidden = true
      return
    }
    statusBadge.isHidden = false
    let side = (iconFrame.width * Self.badgeRatio).rounded()
    statusBadge.frame = CGRect(
      x: iconFrame.maxX - side,
      y: iconFrame.maxY - side,
      width: side,
      height: side
    )
    statusBadge.layer.cornerRadius = side / 2
  }
}
