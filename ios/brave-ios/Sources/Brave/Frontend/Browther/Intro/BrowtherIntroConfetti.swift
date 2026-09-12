// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// La récompense du geste : quand l'interrupteur passe sur ON, une gerbe de
/// confettis tombe du haut de l'écran et **s'éteint en chemin**.
///
/// Le patron est celui des « falling confetti » : chaque confetti a sa propre
/// durée de vie, sa vitesse initiale et sa pesanteur, il dérive latéralement,
/// tourne sur lui-même et bascule (le rectangle s'aplatit puis se rouvre,
/// comme une languette de papier), et son opacité décroît à partir de
/// mi-vie. ⛔ Ce qu'il ne faut PAS faire : une chute uniforme de haut en bas
/// avec disparition au bord — le champ glisse alors d'un bloc au lieu de
/// s'éteindre, c'est le défaut relevé à la recette.
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

  private static let count = 160
  /// Bornes de la gerbe : chaque confetti a sa propre durée de vie dans cet
  /// intervalle, et son propre retard au départ.
  private static let maxLifetime = 2.3
  private static let maxDelay = 0.7

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
        guard elapsed > 0, elapsed < Self.maxDelay + Self.maxLifetime else { return }
        for piece in pieces {
          let age = elapsed - piece.delay
          guard age > 0 else { continue }
          let life = age / piece.lifetime
          guard life < 1 else { continue }

          // Chute : une vitesse initiale propre, puis la pesanteur. Les
          // confettis ne tombent donc pas en bloc, et beaucoup s'effacent
          // avant d'avoir atteint le bas.
          let travel = piece.speed * life + 0.5 * piece.gravity * life * life
          let y = -30 + travel * size.height
          // Dérive : sans elle, ce sont des cailloux, pas du papier.
          let x = piece.x * size.width + sin(life * piece.swayRate + piece.swayPhase)
            * piece.swayWidth

          // ⚠️ Le fondu commence à mi-vie et court jusqu'à zéro : c'est ce qui
          // fait qu'une gerbe **s'éteint** au lieu de traverser l'écran et de
          // disparaître d'un coup au bord (défaut relevé à la recette).
          let fade = life < 0.45 ? 1 : pow(max(0, (1 - life) / 0.55), 0.85)
          guard fade > 0.02 else { continue }

          // Rotation dans le plan + bascule sur l'axe vertical : le rectangle
          // s'aplatit et se rouvre, comme une languette de papier qui tourne.
          let flip = max(0.12, abs(cos(life * piece.flipRate + piece.flipPhase)))
          var rectangle = Path(
            CGRect(
              x: -piece.size.width / 2,
              y: -piece.size.height / 2,
              width: piece.size.width,
              height: piece.size.height
            )
          )
          rectangle = rectangle.applying(
            CGAffineTransform(scaleX: flip, y: 1)
              .concatenating(CGAffineTransform(rotationAngle: piece.spin * life))
              .concatenating(CGAffineTransform(translationX: x, y: y))
          )
          context.fill(rectangle, with: .color(piece.color.opacity(fade)))
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
    let lifetime: Double
    /// Vitesse initiale et pesanteur, en fractions de hauteur.
    let speed: Double
    let gravity: Double
    let swayWidth: Double
    let swayRate: Double
    let swayPhase: Double
    let flipRate: Double
    let flipPhase: Double

    init(using generator: inout SeededGenerator) {
      x = Double.random(in: -0.02...1.02, using: &generator)
      let width = Double.random(in: 5...10, using: &generator)
      size = CGSize(width: width, height: width * Double.random(in: 0.45...1.5, using: &generator))
      color = Self.palette.randomElement(using: &generator) ?? .green
      spin = Double.random(in: -9...9, using: &generator)
      delay = Double.random(in: 0...BrowtherIntroConfetti.maxDelay, using: &generator)
      lifetime = Double.random(in: 1.1...BrowtherIntroConfetti.maxLifetime, using: &generator)
      speed = Double.random(in: 0.18...0.5, using: &generator)
      gravity = Double.random(in: 0.7...1.5, using: &generator)
      swayWidth = Double.random(in: 10...42, using: &generator)
      swayRate = Double.random(in: 4...10, using: &generator)
      swayPhase = Double.random(in: 0...(2 * .pi), using: &generator)
      flipRate = Double.random(in: 6...16, using: &generator)
      flipPhase = Double.random(in: 0...(2 * .pi), using: &generator)
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
