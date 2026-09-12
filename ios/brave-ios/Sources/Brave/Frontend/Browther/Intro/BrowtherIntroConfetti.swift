// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// La récompense du geste : quand l'interrupteur passe sur ON, une gerbe part
/// de lui. C'est la seule animation gratuite de l'introduction, et elle est
/// là pour ça — l'écran demande un geste, il doit le fêter.
///
/// `Canvas` dans un `TimelineView` plutôt que N vues animées : une centaine de
/// particules en une seule passe de dessin, sans créer d'arborescence.
struct BrowtherIntroConfetti: View {
  /// Change de valeur pour tirer une nouvelle gerbe.
  let trigger: Int

  private static let count = 90
  private static let duration = 1.5

  /// Les particules sont tirées une fois par gerbe : même graine, même gerbe
  /// pendant toute son animation.
  private var pieces: [Piece] {
    var generator = SeededGenerator(seed: UInt64(truncatingIfNeeded: trigger &* 2_654_435_761))
    return (0..<Self.count).map { _ in Piece(using: &generator) }
  }

  var body: some View {
    TimelineView(.animation) { timeline in
      Canvas { context, size in
        let elapsed = timeline.date.timeIntervalSince(start)
        guard elapsed < Self.duration else { return }
        let origin = CGPoint(x: size.width / 2, y: size.height)
        for piece in pieces {
          let progress = max(0, (elapsed - piece.delay) / (Self.duration - piece.delay))
          guard progress > 0 else { continue }
          let time = progress * 1.6
          // Tir balistique : impulsion initiale, puis la pesanteur reprend.
          let x = origin.x + piece.velocity.dx * time * size.width
          let y = origin.y + piece.velocity.dy * time * size.height + 900 * time * time
          let opacity = max(0, 1 - progress * progress)
          guard opacity > 0.01 else { continue }
          var rectangle = Path(
            CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2,
                   width: piece.size.width, height: piece.size.height)
          )
          rectangle = rectangle.applying(
            CGAffineTransform(rotationAngle: piece.spin * time)
              .concatenating(CGAffineTransform(translationX: x, y: y))
          )
          context.fill(rectangle, with: .color(piece.color.opacity(opacity)))
        }
      }
    }
    .allowsHitTesting(false)
    .id(trigger)
  }

  private var start: Date { Self.starts.value(for: trigger) }

  /// L'instant de départ de chaque gerbe : `TimelineView` ne donne que l'heure
  /// courante, il faut une origine à laquelle la rapporter.
  private final class Starts: @unchecked Sendable {
    private let lock = NSLock()
    private var dates: [Int: Date] = [:]

    func value(for trigger: Int) -> Date {
      lock.lock()
      defer { lock.unlock() }
      if let date = dates[trigger] { return date }
      let date = Date()
      dates[trigger] = date
      return date
    }
  }

  private static let starts = Starts()

  private struct Piece {
    let velocity: CGVector
    let size: CGSize
    let color: Color
    let spin: Double
    let delay: Double

    init(using generator: inout SeededGenerator) {
      let angle = Double.random(in: (-.pi * 0.86)...(-.pi * 0.14), using: &generator)
      let speed = Double.random(in: 0.5...1.25, using: &generator)
      velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed * 1.4)
      let width = Double.random(in: 4...8, using: &generator)
      size = CGSize(width: width, height: width * Double.random(in: 0.5...1.4, using: &generator))
      color = Self.palette.randomElement(using: &generator) ?? .green
      spin = Double.random(in: -8...8, using: &generator)
      delay = Double.random(in: 0...0.14, using: &generator)
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
