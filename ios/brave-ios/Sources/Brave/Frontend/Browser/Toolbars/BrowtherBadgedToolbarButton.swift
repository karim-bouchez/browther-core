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

  /// Compte à rebours « 2 min » de Sawtunaa : un anneau autour de l'icône qui
  /// se vide, à la place du dot (cf. `FeatureTemporarySwitch`). Animé par
  /// Core Animation sur toute la durée restante : aucun travail par image.
  private let countdownTrack = CAShapeLayer()
  private let countdownRing = CAShapeLayer()
  private var countdownActive = false
  /// Chargement (Sawtunaa : vidéo coupée, son traité pas encore audible) : un
  /// arc qui tourne autour de l'icône, prioritaire sur l'anneau et le dot.
  private let loadingArc = CAShapeLayer()
  private var loadingActive = false

  override init() {
    super.init()
    statusBadge.isUserInteractionEnabled = false
    statusBadge.layer.borderWidth = 1
    statusBadge.layer.borderColor = UIColor.white.cgColor
    addSubview(statusBadge)
    for ring in [countdownTrack, countdownRing] {
      ring.fillColor = nil
      ring.lineWidth = 1.5
      ring.lineCap = .round
      ring.isHidden = true
      layer.addSublayer(ring)
    }
    countdownTrack.strokeColor = UIColor.systemGray3.cgColor
    loadingArc.fillColor = nil
    loadingArc.lineWidth = 1.5
    loadingArc.lineCap = .round
    loadingArc.strokeStart = 0
    loadingArc.strokeEnd = 0.28
    loadingArc.isHidden = true
    layer.addSublayer(loadingArc)
  }

  func setLoading(_ loading: Bool, color: UIColor) {
    guard loading != loadingActive else { return }
    loadingActive = loading
    loadingArc.isHidden = !loading
    loadingArc.removeAnimation(forKey: "spin")
    if loading {
      loadingArc.strokeColor = color.cgColor
      let spin = CABasicAnimation(keyPath: "transform.rotation.z")
      spin.fromValue = 0
      spin.toValue = 2 * Double.pi
      spin.duration = 0.9
      spin.repeatCount = .infinity
      loadingArc.add(spin, forKey: "spin")
    }
    setNeedsLayout()
  }

  /// `remaining` nil ou ≤ 0 : retour au dot.
  func setCountdown(remaining: TimeInterval?, total: TimeInterval, color: UIColor) {
    countdownRing.removeAnimation(forKey: "countdown")
    guard let remaining, remaining > 0, total > 0 else {
      countdownActive = false
      countdownTrack.isHidden = true
      countdownRing.isHidden = true
      setNeedsLayout()
      return
    }
    countdownActive = true
    countdownTrack.isHidden = false
    countdownRing.isHidden = false
    countdownRing.strokeColor = color.cgColor
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    countdownRing.strokeEnd = 0
    CATransaction.commit()
    let animation = CABasicAnimation(keyPath: "strokeEnd")
    animation.fromValue = min(1, remaining / total)
    animation.toValue = 0
    animation.duration = remaining
    countdownRing.add(animation, forKey: "countdown")
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let imageView, imageView.bounds.width > 0 else {
      statusBadge.isHidden = true
      return
    }
    // Géométrie SANS la réduction ci-dessous (`frame` suivrait la transform).
    let iconSize = imageView.bounds.size
    let iconCenter = imageView.center
    let iconFrame = CGRect(
      x: iconCenter.x - iconSize.width / 2, y: iconCenter.y - iconSize.height / 2,
      width: iconSize.width, height: iconSize.height)
    let ringing = countdownActive || loadingActive
    // Anneau ou chargement : l'icône rétrécit et l'anneau tient dans sa place
    // habituelle. À +4 pt autour de l'icône pleine taille, il touchait le
    // dessin ET l'anneau du bouton voisin (recette Karim 2026-10-02).
    imageView.transform = ringing ? CGAffineTransform(scaleX: 0.68, y: 0.68) : .identity
    statusBadge.isHidden = ringing
    countdownTrack.opacity = loadingActive ? 0 : 1
    countdownRing.opacity = loadingActive ? 0 : 1
    let radius = max(iconFrame.width, iconFrame.height) / 2
    let ring = UIBezierPath(
      arcCenter: CGPoint(x: iconFrame.midX, y: iconFrame.midY),
      radius: radius,
      startAngle: -.pi / 2,
      endAngle: 1.5 * .pi,
      clockwise: true
    ).cgPath
    countdownTrack.path = ring
    countdownRing.path = ring
    // L'arc tourne autour de son propre centre : calque centré sur l'icône,
    // chemin dans ses coordonnées (la rotation se fait autour de l'anchorPoint).
    loadingArc.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
    loadingArc.position = CGPoint(x: iconFrame.midX, y: iconFrame.midY)
    loadingArc.path = UIBezierPath(
      arcCenter: CGPoint(x: radius, y: radius),
      radius: radius,
      startAngle: -.pi / 2,
      endAngle: 1.5 * .pi,
      clockwise: true
    ).cgPath
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
