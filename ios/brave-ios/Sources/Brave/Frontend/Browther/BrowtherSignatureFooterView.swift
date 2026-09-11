// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import UIKit

/// Signature de l'éditeur, en pied des Réglages : « Un projet dev&din ↗ »
/// (`docs/SURFACES-COMMUNES.md` §6).
///
/// Ce n'est pas une surface : elle ne demande rien, ne recueille rien, ne
/// consomme aucun verrou. Elle répond à « qui a fait ça ? » — la seule réponse
/// possible dans un produit sans compte — et elle est le seul chemin vers le
/// reste du catalogue pour quelqu'un qui n'a encore rien à nous demander.
///
/// Les choix repris de la passe Fajrunaa (`components/settings/AppSignature.tsx`) :
/// - ⭐ **la bordure porte l'affordance** : en pied de page, un libellé nu suivi
///   d'un logo ne se lit pas comme un lien ;
/// - ⚠️ **le logo garde l'orange de dev&din**, jamais l'accent de l'app hôte ;
///   seule l'encre suit le texte (d'où deux PDF, clair et sombre —
///   `private/assets/gen-ios-devndin-logo.py`) ;
/// - ⛔ **aucun évènement analytique** : un crédit d'éditeur n'a pas de palier.
final class BrowtherSignatureFooterView: UIView {
  static let url = URL(string: "https://devndin.com")!

  /// Plus marqué que `.separator`, trop pâle sur le fond groupé des Paramètres :
  /// c'est la bordure qui dit que ça se touche.
  private static var borderColor: UIColor { .tertiaryLabel }

  private let onTap: () -> Void

  private let pill = UIControl()

  init(onTap: @escaping () -> Void) {
    self.onTap = onTap
    super.init(frame: .zero)

    let label = UILabel()
    label.text = Strings.Browther.signatureLabel
    // La taille n'était pas le problème — c'était le CONTRASTE (retour Karim,
    // 2026-09-11 : agrandie, la pastille devenait trop grosse). Taille d'une
    // note de bas de page ; c'est l'encre du logo et la bordure qui portent.
    label.font = .preferredFont(forTextStyle: .footnote)
    label.adjustsFontForContentSizeCategory = true
    label.textColor = .secondaryLabel

    // Le logo est un mot : sa hauteur suit celle des minuscules du libellé,
    // pas la taille de la police.
    let logo = UIImageView(image: UIImage(named: "browther-devndin-logo", in: .module, with: nil))
    logo.contentMode = .scaleAspectFit
    logo.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      logo.heightAnchor.constraint(equalToConstant: 15),
      // Ratio du viewBox source (1262 × 565).
      logo.widthAnchor.constraint(equalTo: logo.heightAnchor, multiplier: 2.2331),
    ])

    let arrow = UIImageView(
      image: UIImage(
        systemName: "arrow.up.right",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
      )
    )
    arrow.tintColor = .secondaryLabel
    arrow.contentMode = .scaleAspectFit

    let stack = UIStackView(arrangedSubviews: [label, logo, arrow])
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 5
    stack.isUserInteractionEnabled = false
    stack.translatesAutoresizingMaskIntoConstraints = false

    pill.layer.borderColor = Self.borderColor.cgColor
    pill.layer.cornerCurve = .continuous
    pill.translatesAutoresizingMaskIntoConstraints = false
    pill.addSubview(stack)
    pill.addTarget(self, action: #selector(tapped), for: .touchUpInside)
    pill.addTarget(self, action: #selector(highlight), for: [.touchDown, .touchDragEnter])
    pill.addTarget(
      self,
      action: #selector(unhighlight),
      for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
    )
    pill.isAccessibilityElement = true
    pill.accessibilityLabel = "\(Strings.Browther.signatureLabel) dev&din"
    pill.accessibilityTraits = .link

    addSubview(pill)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: pill.topAnchor, constant: 6),
      stack.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -6),
      stack.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 14),
      stack.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -14),
      pill.topAnchor.constraint(equalTo: topAnchor, constant: 20),
      pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28),
      pill.centerXAnchor.constraint(equalTo: centerXAnchor),
      pill.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    pill.layer.cornerRadius = pill.bounds.height / 2
    // Filet d'un pixel physique ; l'échelle n'est connue qu'une fois à l'écran.
    pill.layer.borderWidth = 1 / max(traitCollection.displayScale, 1)
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    // Une couleur CGColor ne suit pas le thème toute seule.
    pill.layer.borderColor = Self.borderColor.cgColor
  }

  @objc private func tapped() {
    onTap()
  }

  @objc private func highlight() {
    pill.alpha = 0.6
  }

  @objc private func unhighlight() {
    pill.alpha = 1
  }
}
