// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// La récompense du geste : quand l'interrupteur passe sur ON, une pluie de
/// confettis traverse **tout l'écran**, du haut vers le bas.
///
/// ⚠️ La date de départ est passée en paramètre, jamais retenue dans un cache
/// interne. La version précédente indexait les dates par numéro de gerbe : les
/// trois écrans tirant tous la gerbe n° 1, seul le premier la voyait — les deux
/// suivants héritaient d'une date déjà expirée et ne dessinaient rien. C'est le
/// défaut « je ne les ai vus qu'une fois » de la recette.
///
/// `Canvas` dans un `TimelineView` plutôt que N vues animées : cent cinquante
/// particules en une seule passe de dessin, sans créer d'arborescence.
struct BrowtherIntroConfetti: View {
  /// L'instant du tir. Changer cette valeur relance la gerbe.
  let start: Date

  private static let count = 150
  private static let duration = 2.6

  private var pieces: [Piece] {
    var generator = SeededGenerator(
      seed: UInt64(bitPattern: Int64(start.timeIntervalSinceReferenceDate * 1000))
    )
    return (0..<Self.count).map { _ in Piece(using: &generator) }
  }

  var body: some View {
    TimelineView(.animation) { timeline in
      Canvas { context, size in
        let elapsed = timeline.date.timeIntervalSince(start)
        guard elapsed > 0, elapsed < Self.duration else { return }
        for piece in pieces {
          let progress = (elapsed - piece.delay) / (Self.duration - piece.delay)
          guard progress > 0 else { continue }
          // Chute libre depuis le haut, avec un flottement latéral : sans lui
          // les confettis tombent comme des cailloux.
          let fall = progress * progress * 0.75 + progress * 0.45
          let y = -40 + fall * (size.height + 120)
          let sway = sin(progress * piece.swayRate + piece.swayPhase) * piece.swayWidth
          let x = piece.x * size.width + sway
          let opacity = progress > 0.75 ? max(0, (1 - progress) / 0.25) : 1
          guard opacity > 0.01 else { continue }
          var rectangle = Path(
            CGRect(
              x: -piece.size.width / 2,
              y: -piece.size.height / 2,
              width: piece.size.width,
              height: piece.size.height
            )
          )
          rectangle = rectangle.applying(
            CGAffineTransform(rotationAngle: piece.spin * progress)
              .concatenating(CGAffineTransform(translationX: x, y: y))
          )
          context.fill(rectangle, with: .color(piece.color.opacity(opacity)))
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private struct Piece {
    /// Position horizontale, en fraction de la largeur : la pluie couvre tout
    /// l'écran, pas une colonne.
    let x: Double
    let size: CGSize
    let color: Color
    let spin: Double
    let delay: Double
    let swayWidth: Double
    let swayRate: Double
    let swayPhase: Double

    init(using generator: inout SeededGenerator) {
      x = Double.random(in: -0.02...1.02, using: &generator)
      let width = Double.random(in: 5...10, using: &generator)
      size = CGSize(width: width, height: width * Double.random(in: 0.45...1.5, using: &generator))
      color = Self.palette.randomElement(using: &generator) ?? .green
      spin = Double.random(in: -14...14, using: &generator)
      delay = Double.random(in: 0...0.55, using: &generator)
      swayWidth = Double.random(in: 8...34, using: &generator)
      swayRate = Double.random(in: 5...11, using: &generator)
      swayPhase = Double.random(in: 0...(2 * .pi), using: &generator)
    }

    /// Les teintes de la marque, plus un blanc cassé pour la lumière.
    static let palette: [Color] = [
      BrowtherIntroPalette.sage,
      BrowtherIntroPalette.gold,
      BrowtherIntroPalette.halal,
      Color(UIColor(rgb: 0xF8F3EA)),
      Color(UIColor(rgb: 0x34C759)),
    ]
  }

  /// Générateur reproductible : la même gerbe doit se redessiner à l'identique
  /// à chaque image, sinon les particules sautent.
  private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
      state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
      state ^= state << 13
      state ^= state >> 7
      state ^= state << 17
      return state
    }
  }
}
