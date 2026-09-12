// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import Shared
import SwiftUI

// MARK: - Écran Pubs : la page web de démonstration

/// Une page de recette quelconque, avec sa pub avant la vidéo et sa bannière.
/// ⛔ Aucun nom de service réel : ce qui fait reconnaître la scène, c'est la
/// pré-roll et son « Passer dans 5 s », pas une marque (cf. règles stores).
struct BrowtherIntroWebPage: View {
  let blocked: Bool

  /// Le cycle de la page quand Browther est éteint : la pub tient l'écran,
  /// puis la vidéo démarre enfin, puis la pub revient. C'est ça, l'expérience
  /// qu'on décrit — elle se raconte mal, elle se montre bien.
  private static let adDuration: Double = 5
  private static let videoDuration: Double = 4
  private static let cycle = adDuration + videoDuration

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.25)) { context in
      let phase = context.date.timeIntervalSinceReferenceDate
        .truncatingRemainder(dividingBy: Self.cycle)
      page(adElapsed: blocked ? nil : (phase < Self.adDuration ? phase : nil))
    }
  }

  /// `adElapsed` non nul = la pub occupe l'écran, depuis tant de secondes.
  @ViewBuilder
  private func page(adElapsed: Double?) -> some View {
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
          .foregroundStyle(BrowtherIntroPalette.halalText)
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
        if let adElapsed {
          preroll(elapsed: adElapsed)
            .transition(.opacity.combined(with: .scale(scale: 1.04)))
        } else {
          // La vidéo tourne : une barre qui avance suffit à le dire.
          VStack {
            Spacer()
            ProgressView(
              value: blocked ? 0.42 : 0.18,
              total: 1
            )
            .progressViewStyle(.linear)
            .tint(.white)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
          }
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

  private func preroll(elapsed: Double) -> some View {
    // Le compte à rebours descend vraiment : 0:15 → 0:10 pour l'annonce,
    // 5 → 0 pour le bouton « Passer ».
    let remainingAd = max(0, 15 - Int(elapsed))
    let remainingSkip = max(0, Int((Self.adDuration - elapsed).rounded(.up)))
    return preroll(remainingAd: remainingAd, remainingSkip: remainingSkip)
  }

  private func preroll(remainingAd: Int, remainingSkip: Int) -> some View {
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
          Text(
            verbatim: "\(Strings.BrowtherIntro.demoAdLabel) \u{00B7} 0:"
              + String(format: "%02d", remainingAd)
          )
          .font(.system(size: 11, weight: .bold))
          .monospacedDigit()
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
          Text(
            remainingSkip > 0
              ? String(format: Strings.BrowtherIntro.demoAdSkipFormat, remainingSkip)
              : Strings.BrowtherIntro.demoAdSkipNow
          )
          .font(.system(size: 11, weight: .semibold))
          .monospacedDigit()
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
          .foregroundStyle(BrowtherIntroPalette.halalText)
          .transition(.opacity)
      }
    }
    .animation(.smooth(duration: 0.4), value: scale)
  }
}
