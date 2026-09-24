// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BrowtherReferral
import SwiftUI
import UIKit

// MARK: - Couleurs (§ 12.24 : « l'or a deux rôles »)

/// Les couleurs du parrainage, sur la palette de l'introduction Browther.
///
/// 🔴 **Deux ors, deux rôles** : `gold` est un TEXTE (or foncé sur fond clair,
/// or vif sur fond sombre) ; `goldFill` est un APLAT (le curseur tiré, la
/// carte « À vie » allumée) qui ne porte que de l'encre sombre (`ink`) — ⛔
/// jamais de l'or sur de l'or, ⛔ jamais l'or vif en texte sur fond clair.
/// ⭐ Au repos la jauge dit ce qu'on A (vert) ; tirée, ce qu'on AURAIT (or).
enum ReferralPalette {
  static let green = BrowtherIntroPalette.halalText
  static let greenFill = BrowtherIntroPalette.dynamic(light: 0x2A8F5A, dark: 0x2A8F5A)
  static let greenSurface = BrowtherIntroPalette.dynamic(light: 0x2A8F5A, dark: 0x6FD79B).opacity(0.13)
  static let gold = BrowtherIntroPalette.dynamic(light: 0x9A5A0C, dark: 0xE2B95C)
  static let goldFill = Color(UIColor(rgb: 0xE2B95C))
  static let goldSurface = BrowtherIntroPalette.dynamic(light: 0xE2B95C, dark: 0xE2B95C).opacity(0.16)
  static let ink = Color(UIColor(rgb: 0x2A1B05))
  static let track = Color(UIColor.systemFill)
  /// 🔴 **La palette de BRAVE, ⛔ pas celle du système** : les écrans du
  /// parrainage vivent dans les Paramètres, et le gris-bleu de Brave y saute
  /// aux yeux à côté du noir pur d'iOS (recette Karim, 2026-09-23).
  static let panel = Color(UIColor.secondaryBraveGroupedBackground)
  /// Le fond de page (celui des écrans de réglages).
  static let screen = Color(UIColor.braveGroupedBackground)
  /// L'aplat doré de la carte des Paramètres : un or DISCRET, qui tient sur les
  /// deux thèmes (l'`opacity` d'un `Color` ne se convertit pas en `UIColor`).
  static let goldSurfaceSolid = BrowtherIntroPalette.dynamic(light: 0xFBF1DA, dark: 0x332814)
  static let line = Color.primary.opacity(0.1)
}

// MARK: - Boutons (la grammaire de l'introduction)

/// Le bouton principal : un aplat plein, la sous-ligne éventuelle DANS le
/// bouton (« Inviter un proche — Et tenter d'avoir l'accès gratuit à vie »).
struct ReferralPrimaryButton: View {
  let label: String
  var sub: String?
  var systemImage: String?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 2) {
        HStack(spacing: 8) {
          if let systemImage {
            Image(systemName: systemImage)
              .font(.system(size: 16, weight: .semibold))
          }
          // ⚠️ Sans `multilineTextAlignment`, un libellé long passe à la ligne
          // et se cale à GAUCHE dans un bouton centré — ça se voit
          // (« Régler Browther comme navigateur par défaut », recette Karim
          // 2026-09-24).
          Text(label)
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let sub {
          Text(sub)
            .font(.footnote)
            .opacity(0.75)
            .multilineTextAlignment(.center)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
    }
    .buttonStyle(BrowtherIntroPrimaryButtonStyle())
  }
}

/// ⭐ **Le bouton principal allumé au palier « à vie »** (§ 12.30) : il reprend
/// le langage de la carte « À vie » — aplat doré sous encre sombre (⛔ jamais
/// de l'or sur de l'or, § 12.24), ∞, et un halo qui pulse DEUX fois (⛔ pas en
/// boucle). ⚠️ Mêmes cotes que `ReferralPrimaryButton` : s'allumer ne fait pas
/// sauter le pied de l'écran. Mouvement réduit : il s'allume, rien ne bouge.
struct ReferralLifetimeButton: View {
  let label: String
  var sub: String?
  let action: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var halo = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: 2) {
        HStack(spacing: 8) {
          Image(systemName: "infinity")
            .font(.system(size: 16, weight: .semibold))
          Text(label)
            .font(.body.weight(.semibold))
        }
        if let sub {
          Text(sub)
            .font(.footnote)
            .opacity(0.75)
            .multilineTextAlignment(.center)
        }
      }
      .foregroundStyle(ReferralPalette.ink)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 16)
      .padding(.vertical, sub == nil ? 16 : 12)
      .background(ReferralPalette.goldFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(ReferralPalette.goldFill.opacity(halo ? 0 : 0.9), lineWidth: halo ? 10 : 0)
          .blur(radius: 6)
          .allowsHitTesting(false)
      }
    }
    .buttonStyle(.plain)
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.easeOut(duration: 0.9).repeatCount(2, autoreverses: false)) { halo = true }
    }
  }
}

/// L'alternative : un contour.
struct ReferralSecondaryButton: View {
  let label: String
  let action: () -> Void

  var body: some View {
    Button(label, action: action)
      .buttonStyle(BrowtherIntroOutlineButtonStyle())
  }
}

/// Une sortie en toutes lettres (« Plus tard », la du'a, « Retour »).
/// 🔴 **Cliquable sur le texte et juste autour, ⛔ jamais sur toute la largeur**
/// (§ 12.9) : une fenêtre qui attend une action ne se ferme que par elle.
struct ReferralTextExit: View {
  let label: String
  var italic = false
  var back = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        if back {
          Image(systemName: "chevron.left")
            .font(.system(size: 13, weight: .semibold))
        }
        Text(label)
          .italic(italic)
          .multilineTextAlignment(.center)
      }
      .font(.subheadline.weight(.medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .frame(minHeight: 44)
  }
}

struct ReferralOrSeparator: View {
  var body: some View {
    HStack(spacing: 10) {
      Rectangle().fill(ReferralPalette.line).frame(height: 1)
      Text(Strings.BrowtherReferral.supportOr)
        .font(.footnote)
        .foregroundStyle(.secondary)
      Rectangle().fill(ReferralPalette.line).frame(height: 1)
    }
    .padding(.vertical, 2)
  }
}

/// Une icône dans un rond : les fenêtres du flow ont une icône en tête
/// (§ 12.26, « bof le layout, il manque un icon »).
struct ReferralRoundIcon: View {
  let systemName: String
  var tone: Tone = .gold
  var size: CGFloat = 64

  enum Tone { case gold, green }

  var body: some View {
    Circle()
      .fill(tone == .gold ? ReferralPalette.goldSurface : ReferralPalette.greenSurface)
      .frame(width: size, height: size)
      .overlay {
        Image(systemName: systemName)
          .font(.system(size: size * 0.42, weight: .semibold))
          .foregroundStyle(tone == .gold ? ReferralPalette.gold : ReferralPalette.green)
      }
  }
}

/// Un texte à balises `**…**` (gras) — le seul formatage des textes du flow.
struct ReferralRichText: View {
  let text: String

  var body: some View {
    if let attributed = try? AttributedString(
      markdown: text,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) {
      Text(attributed)
    } else {
      Text(text)
    }
  }
}

// MARK: - Le composant « fonctionnalités » (§ 2.2)

/// Neutre, sans le thème de l'app, réutilisé sur l'annonce, J−3, J0 et
/// l'abonnement, avec l'état qui va. ⛔ Rien de ce qui est « disponible, pour
/// toujours » n'y porte jamais « en pause ».
struct ReferralFeatureList: View {
  let extras: ExtrasState
  /// Sur l'abonnement : ce qu'on DÉBLOQUE, pas ce qu'on a déjà (§ 2.2).
  var extrasOnly = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if !extrasOnly {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 6) {
            Text(Strings.BrowtherReferral.featuresFreeHead)
              .font(.footnote.weight(.semibold))
            // ⚠️ La formule arabe porte sa PROPRE langue (§ 2.2) : une police
            // latine n'a pas de glyphe arabe.
            Text(Strings.BrowtherReferral.featuresFreeHeadDua)
              .font(.footnote)
              .environment(\.locale, Locale(identifier: "ar"))
              .foregroundStyle(.secondary)
          }
          ForEach(EssentialFeature.allCases, id: \.self) { feature in
            row(symbol: feature.symbol, name: Self.name(feature)) {
              Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ReferralPalette.green)
            }
          }
        }
      }
      VStack(alignment: .leading, spacing: 8) {
        Text(extrasOnly ? Strings.BrowtherReferral.featuresGainHead : Strings.BrowtherReferral.featuresExtrasHead)
          .font(.footnote.weight(.semibold))
        ForEach(ExtraFeature.allCases, id: \.self) { feature in
          row(symbol: feature.symbol, name: Self.name(feature)) {
            statePill
          }
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(ReferralPalette.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func row<Trailing: View>(
    symbol: String,
    name: String,
    @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 14))
        .frame(width: 22)
        .foregroundStyle(.secondary)
      Text(name)
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      trailing()
    }
  }

  @ViewBuilder
  private var statePill: some View {
    let (label, tone): (String, Color) = {
      switch extras {
      case .offered: return (Strings.BrowtherReferral.featuresOffered, ReferralPalette.green)
      case .until(let date):
        return (Strings.BrowtherReferral.featuresUntil(BrowtherReferralController.formatDate(date)), ReferralPalette.green)
      case .soon(let days): return (Strings.BrowtherReferral.featuresSoon(days), ReferralPalette.gold)
      case .paused: return (Strings.BrowtherReferral.featuresPaused, ReferralPalette.gold)
      case .included: return (Strings.BrowtherReferral.featuresIncluded, ReferralPalette.green)
      }
    }()
    Text(label)
      .font(.caption.weight(.semibold))
      .foregroundStyle(tone)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(tone.opacity(0.12), in: Capsule())
      .fixedSize()
  }

  static func name(_ feature: EssentialFeature) -> String {
    switch feature {
    case .blur: return Strings.BrowtherReferral.featureBlur
    case .shields: return Strings.BrowtherReferral.featureShields
    case .browsing: return Strings.BrowtherReferral.featureBrowsing
    }
  }

  static func name(_ feature: ExtraFeature) -> String {
    switch feature {
    case .musicRemoval: return Strings.BrowtherReferral.featureMusicRemoval
    }
  }
}

// MARK: - Le code : une carte qu'on tient (§ 12.3, § 12.24)

/// ⭐ Le code se **dicte** à un proche : il se lit comme un objet qu'on montre,
/// ⛔ pas comme un encadré en pointillés. Format carte bancaire (85,6 × 54 mm),
/// or brossé, puce, guillochis, le nom du produit en encre SOMBRE.
/// ⚠️ **Couleurs FIXES dans les deux thèmes** : une carte n'a pas de thème.
/// ⚠️ « Copier » est une pastille SOMBRE sur l'or (contraste). Il copie le
/// MESSAGE complet, et c'est un partage ABOUTI (§ 12.20) : `onCopied` le dit.
struct ReferralCodeCard: View {
  let status: ReferralStatus
  var onCopied: (() -> Void)?

  @State private var copied = false
  @State private var shine: CGFloat = -0.4
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var code: String { status.referral.code.uppercased() }
  private var link: String { ReferralShare.link(code: code, url: status.referral.url) }

  var body: some View {
    ZStack {
      LinearGradient(
        stops: [
          .init(color: Color(UIColor(rgb: 0xF8DC97)), location: 0),
          .init(color: Color(UIColor(rgb: 0xE9B551)), location: 0.36),
          .init(color: Color(UIColor(rgb: 0xCF922F)), location: 0.68),
          .init(color: Color(UIColor(rgb: 0xA86B17)), location: 1),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      LinearGradient(
        colors: [.white.opacity(0.4), .white.opacity(0)],
        startPoint: .topLeading,
        endPoint: UnitPoint(x: 0.4, y: 0.45)
      )
      // Le guillochis : assez marqué pour se voir sur une carte de 300 pt.
      GeometryReader { geometry in
        ZStack {
          ForEach([20, 36, 52, 68, 84, 100], id: \.self) { radius in
            Circle()
              .stroke(ReferralPalette.ink, lineWidth: 1.8)
              .frame(width: CGFloat(radius) * 2.4, height: CGFloat(radius) * 2.4)
          }
        }
        .opacity(0.3)
        // ⚠️ Le centre est DANS la carte (60 pt du bord droit, 42 pt du bas) —
        // les mêmes cotes que Fajrunaa (`ReferralCodeCard.tsx`, `guilloche` :
        // un carré de 240 posé à right −60 / bottom −78). Centré sur le coin,
        // le guillochis n'en montrait que des quarts de cercle décalés.
        .position(x: geometry.size.width - 60, y: geometry.size.height - 42)
      }
      .allowsHitTesting(false)
      // Un reflet la balaie à l'arrivée et à la copie.
      if !reduceMotion {
        GeometryReader { geometry in
          LinearGradient(
            colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)],
            startPoint: .leading,
            endPoint: .trailing
          )
          .frame(width: geometry.size.width * 0.35)
          .rotationEffect(.degrees(18))
          .offset(x: shine * geometry.size.width * 1.8 - geometry.size.width * 0.2)
          .frame(maxHeight: .infinity)
        }
        .allowsHitTesting(false)
      }
      content
    }
    .aspectRatio(1.586, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(Color.black.opacity(0.12))
    }
    // ⚠️ Le plafond sur la carte ENTIÈRE, le ratio sur son contenu (§ 12.24).
    .frame(maxWidth: 320)
    .frame(maxWidth: .infinity)
    // Un code se lit de gauche à droite, même en arabe.
    .environment(\.layoutDirection, .leftToRight)
    .onAppear { sweep(delay: 0.25) }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top) {
        Text("Browther")
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(ReferralPalette.ink)
        Spacer()
        chip
      }
      Spacer(minLength: 6)
      Text(Strings.BrowtherReferral.cardCodeHead.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .tracking(1.8)
        .foregroundStyle(ReferralPalette.ink.opacity(0.6))
      Text(code)
        .font(.system(size: 28, weight: .semibold, design: .monospaced))
        .tracking(7)
        .foregroundStyle(ReferralPalette.ink)
        .shadow(color: .white.opacity(0.55), radius: 0, y: 1)
        .textSelection(.enabled)
        .accessibilityLabel(code.map(String.init).joined(separator: " "))
      Spacer(minLength: 6)
      HStack(spacing: 8) {
        // ⚠️ Coupé AU MILIEU s'il déborde : la fin du lien porte le code.
        Text(link.replacingOccurrences(of: "https://", with: ""))
          .font(.system(size: 10.5))
          .foregroundStyle(ReferralPalette.ink.opacity(0.65))
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer(minLength: 4)
        Button(action: copy) {
          HStack(spacing: 6) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
              .font(.system(size: 12, weight: .semibold))
            Text(copied ? Strings.BrowtherReferral.cardCopied : Strings.BrowtherReferral.cardCopy)
              .font(.footnote.weight(.semibold))
          }
          .foregroundStyle(Color(UIColor(rgb: 0xFBE6AD)))
          .padding(.horizontal, 12)
          .frame(height: 32)
          .background(ReferralPalette.ink, in: Capsule())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(16)
  }

  /// La puce : ce qui fait lire « carte » au premier coup d'œil.
  private var chip: some View {
    RoundedRectangle(cornerRadius: 5, style: .continuous)
      .fill(
        LinearGradient(
          colors: [Color(UIColor(rgb: 0xFFF4D3)), Color(UIColor(rgb: 0xE2B457)), Color(UIColor(rgb: 0xB98124))],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .frame(width: 38, height: 29)
      .overlay {
        Path { path in
          for y in [9.5, 18.5] {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: 12.5, y: y))
            path.move(to: CGPoint(x: 25.5, y: y))
            path.addLine(to: CGPoint(x: 38, y: y))
          }
          for x in [12.5, 25.5] {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: 29))
          }
          path.move(to: CGPoint(x: 12.5, y: 14.5))
          path.addLine(to: CGPoint(x: 25.5, y: 14.5))
        }
        .stroke(ReferralPalette.ink.opacity(0.35), lineWidth: 1)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .strokeBorder(Color.black.opacity(0.2))
      }
  }

  private func copy() {
    UIPasteboard.general.string = ReferralSharing.message(for: status)
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    copied = true
    sweep(delay: 0)
    onCopied?()
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
  }

  private func sweep(delay: Double) {
    guard !reduceMotion else { return }
    shine = -0.4
    withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.9).delay(delay)) {
      shine = 1
    }
  }
}

// MARK: - La carte « À vie » (§ 12.5)

/// ⭐ **Elle brille toujours** (un reflet la balaie, puis un temps) ; **elle
/// s'allume au palier « à vie »** : fond et bord dorés, un grossissement à
/// peine, un halo qui pulse **deux fois** (⛔ jamais en boucle).
/// 🔴 Allumée, elle reste LISIBLE (§ 12.24) : l'or en halo DERRIÈRE, le texte
/// dans l'encre normale. Mouvement réduit : elle s'allume, c'est tout.
struct ReferralLifetimeCard: View {
  let count: Int
  let lit: Bool
  let lifetimeAt: Int

  @State private var halo: Double = 0
  @State private var shimmer: CGFloat = -0.5
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(lit ? ReferralPalette.goldFill : ReferralPalette.goldSurface)
        .frame(width: 32, height: 32)
        .overlay {
          Image(systemName: "infinity")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(lit ? ReferralPalette.ink : ReferralPalette.gold)
        }
      VStack(alignment: .leading, spacing: 2) {
        Text(Strings.BrowtherReferral.gaugeLifeTitle)
          .font(.headline)
          .foregroundStyle(ReferralPalette.gold)
        Text(lit ? Strings.BrowtherReferral.gaugeLifeReached : Strings.BrowtherReferral.gaugeLifeSub(lifetimeAt))
          .font(.footnote)
          .foregroundStyle(lit ? Color.primary : Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 4)
      HStack(spacing: 0) {
        Text("\(min(count, lifetimeAt))")
          .contentTransition(.numericText(value: Double(min(count, lifetimeAt))))
        Text("/\(lifetimeAt)")
      }
      .font(.footnote.weight(.semibold).monospacedDigit())
      .foregroundStyle(lit ? ReferralPalette.gold : Color.secondary)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .overlay(Capsule().strokeBorder(lit ? ReferralPalette.gold : ReferralPalette.line))
      // Un compteur se lit de gauche à droite, même en arabe.
      .environment(\.layoutDirection, .leftToRight)
    }
    .padding(12)
    .background {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(lit ? ReferralPalette.goldSurface : ReferralPalette.panel)
    }
    .overlay {
      if !reduceMotion {
        GeometryReader { geometry in
          LinearGradient(
            colors: [.white.opacity(0), .white.opacity(0.16), .white.opacity(0)],
            startPoint: .leading,
            endPoint: .trailing
          )
          .frame(width: geometry.size.width * 0.4)
          .offset(x: shimmer * geometry.size.width * 1.6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .allowsHitTesting(false)
      }
    }
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(lit ? ReferralPalette.gold : ReferralPalette.line)
    }
    .background {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(ReferralPalette.goldFill.opacity(0.35))
        .blur(radius: 14)
        .opacity(halo)
    }
    .scaleEffect(lit && !reduceMotion ? 1.02 : 1)
    .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.3), value: lit)
    .onChange(of: lit) { _, isLit in pulse(isLit) }
    .onAppear {
      if lit { halo = 0.4 }
    }
    // Un balayage, puis un long repos : un reflet permanent fatiguerait l'œil.
    // ⚠️ Une tâche attachée à la vue : elle s'arrête avec elle.
    .task {
      guard !reduceMotion else { return }
      while !Task.isCancelled {
        shimmer = -0.5
        try? await Task.sleep(for: .milliseconds(400))
        withAnimation(.easeInOut(duration: 1.3)) { shimmer = 1.1 }
        try? await Task.sleep(for: .milliseconds(1300 + 3200))
      }
    }
  }

  /// Deux pulsations, puis une lueur qui reste — ⛔ pas une boucle.
  private func pulse(_ isLit: Bool) {
    guard !reduceMotion else { return }
    guard isLit else {
      withAnimation(.easeOut(duration: 0.2)) { halo = 0 }
      return
    }
    withAnimation(.easeOut(duration: 0.42)) { halo = 1 }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
      withAnimation(.easeInOut(duration: 0.42)) { halo = 0.35 }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.84) {
      withAnimation(.easeOut(duration: 0.42)) { halo = 1 }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.26) {
      withAnimation(.easeInOut(duration: 0.6)) { halo = 0.4 }
    }
  }
}
