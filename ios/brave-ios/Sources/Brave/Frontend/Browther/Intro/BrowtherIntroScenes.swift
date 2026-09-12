// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import Shared
import SwiftUI

// MARK: - Personnages de démonstration
//
// ⚠️ PROVISOIRE. Ces silhouettes remplacent la photo et la vidéo réelles, qui
// seront floutées à l'avance **par Basarunaa lui-même** pour que l'écran montre
// le vrai rendu (cf. `private/docs/ONBOARDING.md` § médias). Quand les médias
// arrivent : déposer `browther-intro-people.jpg` dans les ressources du module
// et `BrowtherIntroPeopleScene` les affiche à la place, sans rien changer
// ailleurs.

/// Une silhouette stylisée, dessinée : ni photo ni personne réelle.
struct BrowtherIntroFigure: View {
  enum Kind {
    case man
    case woman
  }

  let kind: Kind

  private var clothes: Color {
    switch kind {
    case .man: return Color(UIColor(rgb: 0x4F6B4D))
    case .woman: return Color(UIColor(rgb: 0xB88C3E))
    }
  }

  private var skin: Color {
    Color(UIColor(rgb: kind == .man ? 0xC99B74 : 0xD8AC86))
  }

  private var hair: Color {
    Color(UIColor(rgb: kind == .man ? 0x2B241F : 0x3A2A22))
  }

  var body: some View {
    GeometryReader { proxy in
      let w = proxy.size.width
      let h = proxy.size.height
      ZStack(alignment: .top) {
        // Cheveux longs (femme) — dessinés derrière la tête et les épaules.
        if kind == .woman {
          Capsule()
            .fill(hair)
            .frame(width: w * 0.62, height: h * 0.42)
            .offset(y: h * 0.02)
        }
        VStack(spacing: 0) {
          ZStack {
            Circle()
              .fill(skin)
              .frame(width: w * 0.36, height: w * 0.36)
            // Barbe (homme) : demi-disque sous le visage.
            if kind == .man {
              Circle()
                .fill(hair)
                .frame(width: w * 0.36, height: w * 0.36)
                .mask(alignment: .bottom) {
                  Rectangle().frame(height: w * 0.17)
                }
            }
            Circle()
              .fill(hair)
              .frame(width: w * 0.37, height: w * 0.37)
              .mask(alignment: .top) {
                Rectangle().frame(height: w * 0.13)
              }
          }
          .padding(.top, h * 0.06)
          // Buste et vêtement : robe longue pour la femme, chemise et pantalon
          // pour l'homme.
          if kind == .woman {
            Trapezoid(topInset: 0.28)
              .fill(clothes)
              .frame(width: w, height: h * 0.66)
          } else {
            RoundedRectangle(cornerRadius: w * 0.2, style: .continuous)
              .fill(clothes)
              .frame(width: w * 0.78, height: h * 0.3)
            HStack(spacing: w * 0.08) {
              Capsule().fill(Color(UIColor(rgb: 0x2E3440))).frame(width: w * 0.24)
              Capsule().fill(Color(UIColor(rgb: 0x2E3440))).frame(width: w * 0.24)
            }
            .frame(height: h * 0.32)
          }
        }
      }
      .frame(width: w, height: h, alignment: .top)
    }
    .accessibilityHidden(true)
  }
}

/// Trapèze — la robe, plus large en bas qu'aux épaules.
struct Trapezoid: Shape {
  /// Part de la largeur retirée de chaque côté, en haut.
  var topInset: CGFloat

  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + rect.width * topInset, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - rect.width * topInset, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

/// Le voile posé sur une personne : **le rendu de Basarunaa**, c'est-à-dire une
/// zone dépolie qui suit la personne, pas l'image entière assombrie.
struct BrowtherIntroVeil: View {
  let isBlurred: Bool

  var body: some View {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
      .fill(.ultraThinMaterial)
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
      }
      .overlay(alignment: .bottom) {
        Text(Strings.BrowtherIntro.blurredTag)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
          .padding(.bottom, 8)
      }
      .opacity(isBlurred ? 1 : 0)
      .animation(.easeOut(duration: 0.26), value: isBlurred)
  }
}

/// La scène de l'écran « Choisis qui flouter » : un décor, deux personnes, et
/// le voile sur celle(s) que la personne a choisie(s).
struct BrowtherIntroPeopleScene: View {
  let target: BrowtherBlurTarget

  private var blursWoman: Bool { target != .men }
  private var blursMan: Bool { target != .women }

  var body: some View {
    GeometryReader { proxy in
      let w = proxy.size.width
      let h = proxy.size.height
      ZStack(alignment: .bottom) {
        LinearGradient(
          colors: [Color(UIColor(rgb: 0xF2CF9E)), Color(UIColor(rgb: 0xF8ECD8))],
          startPoint: .top,
          endPoint: .bottom
        )
        // Arcades : le décor des fonds du Nouvel Onglet, en aplat.
        HStack(spacing: w * 0.05) {
          ForEach(0..<4, id: \.self) { _ in
            UnevenRoundedRectangle(
              topLeadingRadius: w * 0.07,
              bottomLeadingRadius: 0,
              bottomTrailingRadius: 0,
              topTrailingRadius: w * 0.07,
              style: .continuous
            )
            .fill(Color(UIColor(rgb: 0xBF9567)))
            .frame(height: h * 0.42)
          }
        }
        .padding(.horizontal, w * 0.04)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, h * 0.1)
        Rectangle()
          .fill(Color(UIColor(rgb: 0xC9AB83)))
          .frame(height: h * 0.12)
        // Les deux personnes, chacune sous son voile.
        HStack(alignment: .bottom, spacing: w * 0.1) {
          person(.man, width: w * 0.17, height: h * 0.62, blurred: blursMan)
          person(.woman, width: w * 0.18, height: h * 0.66, blurred: blursWoman)
        }
        .padding(.bottom, h * 0.08)
      }
      .frame(width: w, height: h)
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
  }

  @ViewBuilder
  private func person(
    _ kind: BrowtherIntroFigure.Kind,
    width: CGFloat,
    height: CGFloat,
    blurred: Bool
  ) -> some View {
    BrowtherIntroFigure(kind: kind)
      .frame(width: width, height: height)
      .overlay {
        BrowtherIntroVeil(isBlurred: blurred)
          .padding(.horizontal, -width * 0.16)
          .padding(.vertical, -height * 0.03)
      }
  }
}

// MARK: - Écran Pubs : la page web de démonstration

/// Une page de recette quelconque, avec sa pub avant la vidéo et sa bannière.
/// ⛔ Aucun nom de service réel : ce qui fait reconnaître la scène, c'est la
/// pré-roll et son « Passer dans 5 s », pas une marque (cf. règles stores).
struct BrowtherIntroWebPage: View {
  let blocked: Bool

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "lock.fill")
          .font(.system(size: 11))
          .foregroundStyle(BrowtherIntroPalette.inkSoft)
        Text(Strings.BrowtherIntro.demoSiteName)
          .font(.caption.weight(.semibold))
          .foregroundStyle(BrowtherIntroPalette.ink)
        Spacer()
        if blocked {
          HStack(spacing: 4) {
            Image(systemName: "shield.fill")
            Text(Strings.BrowtherIntro.demoBlockedCount)
          }
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(BrowtherIntroPalette.halal)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(BrowtherIntroPalette.halal.opacity(0.14), in: Capsule())
          .transition(.opacity)
        }
      }
      .padding(.horizontal, 12)
      .frame(height: 38)
      Divider()
      ZStack {
        LinearGradient(
          colors: [Color(UIColor(rgb: 0x2E3A31)), Color(UIColor(rgb: 0x161B18))],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        Image(systemName: "play.fill")
          .font(.system(size: 20))
          .foregroundStyle(.white)
          .frame(width: 44, height: 44)
          .background(Color.white.opacity(0.18), in: Circle())
        if !blocked {
          preroll
            .transition(.opacity.combined(with: .scale(scale: 1.04)))
        }
      }
      .frame(height: 132)
      .clipped()
      VStack(alignment: .leading, spacing: 8) {
        Text(Strings.BrowtherIntro.demoArticleTitle)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(BrowtherIntroPalette.ink)
        Text(Strings.BrowtherIntro.demoArticleBody)
          .font(.system(size: 12))
          .foregroundStyle(BrowtherIntroPalette.inkSoft)
          .lineLimit(2)
        if !blocked {
          banner
            .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      Spacer(minLength: 0)
    }
    .background(Color(UIColor.secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .animation(.smooth(duration: 0.32), value: blocked)
  }

  private var preroll: some View {
    ZStack {
      LinearGradient(
        colors: [Color(UIColor(rgb: 0x7B2D58)), Color(UIColor(rgb: 0xC55A3B))],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      Image(systemName: "photo")
        .font(.system(size: 40))
        .foregroundStyle(.white.opacity(0.4))
      VStack {
        HStack(spacing: 6) {
          Text(Strings.BrowtherIntro.demoAdCountdown)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(UIColor(rgb: 0xF5C542)), in: RoundedRectangle(cornerRadius: 6))
          HStack(spacing: 4) {
            Image(systemName: "music.note")
            Text(Strings.BrowtherIntro.demoAdSound)
          }
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
          Spacer()
        }
        Spacer()
        HStack {
          Spacer()
          Text(Strings.BrowtherIntro.demoAdSkip)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        }
      }
      .padding(8)
    }
  }

  private var banner: some View {
    HStack(spacing: 10) {
      Image(systemName: "photo")
        .font(.system(size: 20))
        .foregroundStyle(Color(UIColor(rgb: 0x9A5A3C)))
        .frame(width: 44, height: 44)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
      VStack(alignment: .leading, spacing: 2) {
        Text(Strings.BrowtherIntro.demoAdLabel)
          .font(.system(size: 12, weight: .bold))
        Text(Strings.BrowtherIntro.demoAdSponsored)
          .font(.system(size: 11))
      }
      .foregroundStyle(Color(UIColor(rgb: 0x5B2D1C)))
      Spacer()
    }
    .padding(.horizontal, 10)
    .frame(height: 62)
    .background(
      LinearGradient(
        colors: [Color(UIColor(rgb: 0xF4DAC8)), Color(UIColor(rgb: 0xE3AB91))],
        startPoint: .leading,
        endPoint: .trailing
      ),
      in: RoundedRectangle(cornerRadius: 10, style: .continuous)
    )
  }
}

// MARK: - Écran Musique : le lecteur et ses deux pistes

/// Les deux pistes du lecteur : la voix reste, la musique s'aplatit quand
/// Browther est allumé. Dessinées, pas enregistrées — le vrai extrait audio
/// viendra remplacer l'animation (cf. § médias).
struct BrowtherIntroLanes: View {
  let musicRemoved: Bool

  private let bars = 34

  var body: some View {
    VStack(spacing: 12) {
      lane(
        title: Strings.BrowtherIntro.musicLaneVoice,
        color: BrowtherIntroPalette.sage,
        scale: 1,
        seed: 0.7
      )
      lane(
        title: Strings.BrowtherIntro.musicLaneMusic,
        color: BrowtherIntroPalette.gold,
        scale: musicRemoved ? 0.04 : 1,
        seed: 1.9,
        trailing: musicRemoved ? Strings.BrowtherIntro.musicRemoved : nil
      )
    }
  }

  @ViewBuilder
  private func lane(
    title: String,
    color: Color,
    scale: CGFloat,
    seed: Double,
    trailing: String? = nil
  ) -> some View {
    HStack(spacing: 10) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white.opacity(0.72))
        .frame(width: 62, alignment: .leading)
      TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
        Canvas { context2D, size in
          let time = context.date.timeIntervalSinceReferenceDate
          let gap: CGFloat = 3
          let width = (size.width - gap * CGFloat(bars - 1)) / CGFloat(bars)
          for index in 0..<bars {
            let phase = time * 4.2 + Double(index) * seed * 0.3
            let amplitude = CGFloat(0.35 + 0.65 * abs(sin(phase))) * scale
            let height = max(3, size.height * amplitude)
            let rect = CGRect(
              x: CGFloat(index) * (width + gap),
              y: (size.height - height) / 2,
              width: width,
              height: height
            )
            context2D.fill(
              Path(roundedRect: rect, cornerRadius: min(width / 2, 3)),
              with: .color(color)
            )
          }
        }
      }
      .frame(height: 28)
      if let trailing {
        Text(trailing)
          .font(.caption.weight(.semibold))
          .foregroundStyle(BrowtherIntroPalette.halal)
          .transition(.opacity)
      }
    }
    .animation(.smooth(duration: 0.4), value: scale)
  }
}
