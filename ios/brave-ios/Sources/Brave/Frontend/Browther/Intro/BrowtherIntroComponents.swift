// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import Shared
import SwiftUI
import UIKit

// MARK: - Couleurs

/// Les couleurs propres à l'introduction. Le reste suit les couleurs système
/// (fond, libellés) : seules les teintes de marque sont posées ici, et chacune
/// a sa variante sombre — sur fond noir, les valeurs claires du site tombent
/// sous le seuil de contraste.
enum BrowtherIntroPalette {
  static let sage = dynamic(light: 0x5A7858, dark: 0xA5B299)
  static let gold = dynamic(light: 0xB88C3E, dark: 0xD4A857)
  static let halal = dynamic(light: 0x1C5A3A, dark: 0x2A8F5A)
  static let haram = dynamic(light: 0x8B2C2C, dark: 0xC44545)
  /// Fond des maquettes (page web, fil d'images) : le crème du site en clair,
  /// une surface élevée en sombre.
  static let canvas = dynamic(light: 0xF8F3EA, dark: 0x1C1F1C)
  static let ink = Color(UIColor.label)
  static let inkSoft = Color(UIColor.secondaryLabel)

  static func dynamic(light: Int, dark: Int) -> Color {
    Color(
      UIColor { trait in
        UIColor(rgb: trait.userInterfaceStyle == .dark ? dark : light)
      }
    )
  }
}

// MARK: - Tampons halal / haram

/// Le disque dentelé des tampons du site (24 pointes, cf.
/// `website/components/sections/before-after.tsx`).
struct BrowtherStampShape: Shape {
  var spikes: Int = 24
  var innerRatio: CGFloat = 0.89

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let outer = min(rect.width, rect.height) / 2
    let inner = outer * innerRatio
    for i in 0..<(spikes * 2) {
      let radius = i.isMultiple(of: 2) ? outer : inner
      let angle = (Double(i) * .pi / Double(spikes)) - .pi / 2
      let point = CGPoint(
        x: center.x + CGFloat(cos(angle)) * radius,
        y: center.y + CGFloat(sin(angle)) * radius
      )
      if i == 0 {
        path.move(to: point)
      } else {
        path.addLine(to: point)
      }
    }
    path.closeSubpath()
    return path
  }
}

/// Le tampon « halal » ou « haram », repris du site pour que le contraste se
/// lise sans lire : c'est lui qui dit ce que Browther change sur la page.
///
/// ⛔ Pas de texte en arc comme sur le site : à cette taille il serait illisible,
/// et l'arc SVG n'a pas d'équivalent simple en SwiftUI. On garde le disque, les
/// deux cercles, les étoiles et les deux mots.
struct BrowtherStamp: View {
  enum Kind {
    case halal
    case haram

    var color: Color {
      switch self {
      case .halal: return BrowtherIntroPalette.halal
      case .haram: return BrowtherIntroPalette.haram
      }
    }

    var arabic: String {
      switch self {
      case .halal: return "حلال"
      case .haram: return "حرام"
      }
    }

    var latin: String {
      switch self {
      case .halal: return Strings.BrowtherIntro.stampHalal
      case .haram: return Strings.BrowtherIntro.stampHaram
      }
    }
  }

  let kind: Kind
  var size: CGFloat = 88

  var body: some View {
    ZStack {
      BrowtherStampShape().fill(kind.color)
      Circle()
        .strokeBorder(Color.white.opacity(0.92), lineWidth: size * 0.026)
        .padding(size * 0.085)
      Circle()
        .strokeBorder(Color.white.opacity(0.92), lineWidth: size * 0.014)
        .padding(size * 0.155)
      VStack(spacing: size * 0.01) {
        Text(kind.arabic)
          .font(.system(size: size * 0.28, weight: .bold))
          .environment(\.layoutDirection, .rightToLeft)
        Text(kind.latin)
          .font(.system(size: size * 0.12, weight: .heavy))
          .tracking(size * 0.012)
      }
      .foregroundStyle(.white)
      HStack {
        Text("★")
        Spacer()
        Text("★")
      }
      .font(.system(size: size * 0.07))
      .foregroundStyle(.white.opacity(0.94))
      .padding(.horizontal, size * 0.17)
      .padding(.top, size * 0.16)
    }
    .frame(width: size, height: size)
    .shadow(color: .black.opacity(0.28), radius: 6, y: 4)
    .accessibilityHidden(true)
  }
}

/// Les deux tampons superposés : le haram se décolle, le halal claque.
/// Transitions plutôt qu'animations à images clés — on peut basculer
/// l'interrupteur deux fois par seconde sans que le tampon reparte de zéro.
struct BrowtherStampPair: View {
  let isOn: Bool
  var size: CGFloat = 88

  var body: some View {
    ZStack {
      BrowtherStamp(kind: .haram, size: size)
        .rotationEffect(.degrees(isOn ? -4 : -12))
        .scaleEffect(isOn ? 0.62 : 1)
        .opacity(isOn ? 0 : 0.95)
      BrowtherStamp(kind: .halal, size: size)
        .rotationEffect(.degrees(isOn ? -12 : -34))
        .scaleEffect(isOn ? 1 : 1.9)
        .opacity(isOn ? 0.96 : 0)
    }
    .animation(.snappy(duration: 0.42, extraBounce: 0.25), value: isOn)
  }
}

// MARK: - Pastilles d'état

struct BrowtherIntroPill: View {
  enum Tone {
    case active
    case soon
  }

  let tone: Tone
  let label: String

  private var color: Color {
    switch tone {
    case .active: return BrowtherIntroPalette.halal
    case .soon: return BrowtherEarlyAccess.amber
    }
  }

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: tone == .active ? "checkmark" : "testtube.2")
        .font(.system(size: 11, weight: .semibold))
      Text(label)
        .font(.footnote.weight(.semibold))
    }
    .foregroundStyle(color)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(color.opacity(0.13), in: Capsule())
  }
}

// MARK: - Boutons

struct BrowtherIntroPrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.semibold))
      .foregroundStyle(Color(UIColor.systemBackground))
      .frame(maxWidth: .infinity, minHeight: 52)
      .background(Color(UIColor.label), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .opacity(configuration.isPressed ? 0.85 : 1)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct BrowtherIntroGhostButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.semibold))
      .foregroundStyle(BrowtherIntroPalette.inkSoft)
      .frame(maxWidth: .infinity, minHeight: 44)
      .opacity(configuration.isPressed ? 0.6 : 1)
  }
}

// MARK: - Rangée d'interrupteur (écrans Pubs et Musique)

/// La commande des démonstrations : le **gros interrupteur des panels**
/// (`ShieldsSwitchView`), pas un `Toggle` système. C'est le geste que la
/// personne refera dans Browther, elle l'apprend ici.
struct BrowtherIntroSwitchRow: View {
  /// L'icône que la personne retrouvera dans l'app — c'est elle qui relie
  /// l'écran au moteur. Sans ça, « Basarunaa » n'est qu'un mot de plus.
  let icon: String
  let title: String
  let offLabel: String
  let onLabel: String
  @Binding var isOn: Bool

  var body: some View {
    HStack(spacing: 12) {
      Image(icon, bundle: .module)
        .resizable()
        .renderingMode(.template)
        .aspectRatio(contentMode: .fit)
        .frame(width: 24, height: 24)
        .foregroundStyle(isOn ? BrowtherIntroPalette.halal : BrowtherIntroPalette.inkSoft)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.callout.weight(.semibold))
          .foregroundStyle(BrowtherIntroPalette.ink)
        Text(isOn ? onLabel : offLabel)
          .font(.footnote)
          .foregroundStyle(isOn ? BrowtherIntroPalette.halal : BrowtherIntroPalette.inkSoft)
          .contentTransition(.opacity)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      ShieldsSwitchView(isEnabled: $isOn)
        .frame(width: 100, height: 60)
        .accessibilityLabel(title)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .animation(.smooth(duration: 0.25), value: isOn)
  }
}

// MARK: - Bouton d'avancement conditionné

/// Le bouton de bas d'écran, **éteint tant que l'interrupteur n'est pas sur
/// ON**. L'écran demande un geste ; le laisser franchir sans le faire, c'est
/// laisser partir quelqu'un qui n'a rien vu fonctionner.
struct BrowtherIntroAdvanceButton: View {
  let title: String
  let enabled: Bool
  let action: () -> Void

  var body: some View {
    VStack(spacing: 6) {
      Button(title, action: action)
        .buttonStyle(BrowtherIntroPrimaryButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .saturation(enabled ? 1 : 0)
        .animation(.smooth(duration: 0.3), value: enabled)
      Text(Strings.BrowtherIntro.turnOnToContinue)
        .font(.footnote)
        .foregroundStyle(BrowtherIntroPalette.inkSoft)
        .opacity(enabled ? 0 : 1)
        .frame(height: enabled ? 0 : nil)
        .animation(.smooth(duration: 0.3), value: enabled)
    }
  }
}

// MARK: - Signature de l'éditeur

/// `SURFACES-COMMUNES.md` §6, en version **muette** : la pastille, mais ni
/// flèche ni geste — ouvrir devndin.com ferait sortir de l'introduction. La
/// version tapable reste au pied des Paramètres.
struct BrowtherIntroSignature: View {
  var body: some View {
    HStack(spacing: 6) {
      Text(Strings.Browther.signatureLabel)
        .font(.footnote)
      Image("browther-devndin-logo", bundle: .module)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 33.5, height: 15)
    }
    .foregroundStyle(.white.opacity(0.62))
    .padding(.horizontal, 14)
    .padding(.vertical, 7)
    .background(Color.white.opacity(0.07), in: Capsule())
    .overlay {
      Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Point d'état

/// Le point vert ou ambre des trois protections. Le halo n'est pas décoratif :
/// à 7 px sur une photo, un aplat mat se perd dans le fond.
struct BrowtherIntroStatusDot: View {
  let soon: Bool

  private var color: Color {
    soon ? Color(UIColor(rgb: 0xF59E0B)) : Color(UIColor(rgb: 0x34C759))
  }

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 7, height: 7)
      .shadow(color: color.opacity(0.9), radius: 4)
      .shadow(color: color.opacity(0.5), radius: 8)
  }
}
