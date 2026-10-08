// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import UIKit

// MARK: - La carte B9 « Onglets + barre » (2026-09-28)

/// Les images de la carte — passées en `UIImage` (⛔ pas `Image("…", bundle:)`
/// dans la vue) pour que `ImageRenderer` les dessine à coup sûr dans l'image du
/// statut, et que le banc de rendu (`private/scripts/ios-referral-tests/
/// render_card.sh`) puisse les fournir hors de l'app.
struct ReferralCardArt {
  let icon: UIImage
  let wordmark: UIImage
  /// Le logo dev&din CLAIR (la carte est sombre dans les deux thèmes).
  let devndin: UIImage

  /// Chargées une fois : la carte se redessine à chaque reflet.
  static let bundled: ReferralCardArt = {
    ReferralCardArt(
      icon: UIImage(named: "browther.app.icon", in: .module, with: nil) ?? UIImage(),
      wordmark: UIImage(named: "browther.wordmark.white", in: .module, with: nil) ?? UIImage(),
      devndin: fixed("browther-devndin-logo", style: .dark)
    )
  }()

  /// Une image du catalogue FIGÉE dans une apparence.
  ///
  /// 🔴 **Demander la variante sombre ne suffit pas** : l'image rendue par
  /// `UIImage(named:in:compatibleWith:)` reste liée au catalogue, et se
  /// re-résout selon le thème du TÉLÉPHONE au moment d'être dessinée. Sur la
  /// carte (sombre dans les deux thèmes), le logo dev&din sortait donc foncé
  /// sur fond noir dès que l'iPhone était en clair (recette Karim,
  /// 2026-10-08). On la redessine une fois, dans l'apparence voulue : le
  /// résultat est une image ordinaire, qui ne change plus.
  /// ⚠️ Grande exprès (le PDF garde son vecteur) : l'image du statut agrandit
  /// la carte.
  static func fixed(_ name: String, style: UIUserInterfaceStyle, height: CGFloat = 64) -> UIImage {
    let traits = UITraitCollection(userInterfaceStyle: style)
    guard let source = UIImage(named: name, in: .module, compatibleWith: traits),
      source.size.height > 0
    else { return UIImage() }
    let resolved = source.imageAsset?.image(with: traits) ?? source
    let size = CGSize(width: (height * resolved.size.width / resolved.size.height).rounded(.up), height: height)
    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    format.scale = 3
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      traits.performAsCurrent {
        resolved.draw(in: CGRect(origin: .zero, size: size))
      }
    }
  }
}

/// ⭐ **Une carte par produit** (`devndin/docs/PARRAINAGE-partage-statut.md` § 2) —
/// celle de Browther est la **B9** : la carte encre (dégradé `#22272a → #0f1110`,
/// vagues sauge et or) avec l'interface d'un navigateur DESSINÉE dessus :
/// pastilles du Mac, onglets « Parrainage » + « YouTube », flèches, barre
/// d'adresse. Jumeaux : `private/webui/referral/src/ui/CodeCard.tsx` (desktop),
/// `website/lib/statusImage.ts` (l'image du statut, site).
///
/// ⚠️ Cotée dans l'espace de la maquette (**330 × 208**) : l'appelant la met à
/// l'échelle (`scaleEffect`). Ainsi le lien tient EN ENTIER à toute largeur
/// (⛔ jamais « … » : la carte ne s'agrandit pas), et l'image du statut la
/// rend telle quelle, plus grande.
///
/// Deux faces :
/// - `.app` : le lien dans la barre d'adresse, « Copier » à sa droite ;
/// - `.status` : ⛔ ni lien ni « Copier » (rien n'y est cliquable) — la barre
///   dit ce que fait l'app, et « 1 mois de bonus » remplace le bouton.
///
/// ⚠️ Couleurs FIXES dans les deux thèmes : une carte n'a pas de thème. En
/// arabe (`rtl`), elle se lit en miroir ; le code reste de gauche à droite.
struct ReferralCardFace: View {
  enum Face {
    case app(link: String, copyLabel: String, copied: Bool, onCopy: () -> Void)
    case status(omni: String, gift: String)
  }

  static let size = CGSize(width: 330, height: 208)

  let code: String
  let face: Face
  let tab: String
  let label: String
  let tag: String
  let art: ReferralCardArt
  var rtl = false
  /// Le reflet qui balaie la carte (de −0,4 à 1) ; `nil` = pas de reflet.
  var shine: CGFloat?

  private static let ink = Color(red: 240 / 255, green: 241 / 255, blue: 237 / 255)
  private static let gold = Color(red: 196 / 255, green: 165 / 255, blue: 114 / 255)

  var body: some View {
    ZStack(alignment: .topLeading) {
      LinearGradient(
        stops: [
          .init(color: Color(red: 0x22 / 255, green: 0x27 / 255, blue: 0x2A / 255), location: 0),
          .init(color: Color(red: 0x16 / 255, green: 0x19 / 255, blue: 0x1A / 255), location: 0.5),
          .init(color: Color(red: 0x0F / 255, green: 0x11 / 255, blue: 0x10 / 255), location: 1),
        ],
        startPoint: UnitPoint(x: 0.18, y: 0),
        endPoint: UnitPoint(x: 0.82, y: 1)
      )
      ReferralCardWaves()
      LinearGradient(
        colors: [.white.opacity(0.16), .white.opacity(0)],
        startPoint: .topLeading,
        endPoint: UnitPoint(x: 0.4, y: 0.5)
      )
      if let shine {
        LinearGradient(
          colors: [.white.opacity(0), .white.opacity(0.22), .white.opacity(0)],
          startPoint: .leading,
          endPoint: .trailing
        )
        .frame(width: 110, height: 320)
        .rotationEffect(.degrees(18))
        .offset(x: shine * 594 - 66, y: -56)
        // 🔴 Le reflet est PLUS HAUT que la carte (320 contre 208) : sans ce
        // cadre il agrandissait la pile, que le cadre de la carte recentrait
        // ensuite — tout le contenu remontait de 56 points, onglets et barre
        // d'adresse rognés par le haut (recette Karim, 2026-10-08). Il
        // déborde désormais de SON cadre, pas de la mise en page.
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .allowsHitTesting(false)
      }
      content
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
    }
  }

  private var content: some View {
    ZStack(alignment: .topTrailing) {
      VStack(alignment: .leading, spacing: 0) {
        tabsRow
        barRow
          .padding(.top, 5)
        Spacer(minLength: 0)
        middle
        Spacer(minLength: 0)
        bottom
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 16)
      // La puce : entre le haut et le centre (centre à 40 % de la hauteur),
      // décollée du bord — à gauche en arabe.
      ReferralCardChip()
        .padding(.top, Self.size.height * 0.4 - 18)
        .padding(.trailing, 32)
    }
    .frame(width: Self.size.width, height: Self.size.height)
  }

  // 1ʳᵉ rangée : les pastilles du Mac, l'onglet actif, l'onglet YouTube.
  private var tabsRow: some View {
    HStack(spacing: 7) {
      HStack(spacing: 5) {
        ForEach([0xFF5F57, 0xFEBC2E, 0x28C840], id: \.self) { rgb in
          Circle()
            .fill(Color(cardRGB: rgb))
            .frame(width: 9, height: 9)
        }
      }
      HStack(spacing: 5) {
        Image(uiImage: art.icon)
          .resizable()
          .frame(width: 11, height: 11)
          .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        Text(tab)
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(Self.ink)
          .lineLimit(1)
      }
      .padding(.horizontal, 8)
      .frame(height: 19)
      .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
      HStack(spacing: 5) {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .fill(Color(cardRGB: 0xFF3B30))
          .frame(width: 10, height: 7)
        Text(verbatim: "YouTube")
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(Self.ink.opacity(0.5))
      }
      .padding(.horizontal, 8)
      Spacer(minLength: 0)
    }
  }

  // 2ᵉ rangée : ‹ › · la barre d'adresse · « Copier » (ou ce que donne le code).
  private var barRow: some View {
    HStack(spacing: 8) {
      HStack(spacing: 3) {
        Image(systemName: "chevron.left")
          .foregroundStyle(Self.ink.opacity(0.65))
        Image(systemName: "chevron.right")
          .foregroundStyle(Self.ink.opacity(0.23))
      }
      .font(.system(size: 9, weight: .bold))
      .flipsForRightToLeftLayoutDirection(true)
      switch face {
      case .app(let link, let copyLabel, let copied, let onCopy):
        addressBar(systemImage: "lock.fill") {
          Text(verbatim: link)
            .font(.system(size: 9, design: .monospaced))
            .environment(\.layoutDirection, .leftToRight)
        }
        Button(action: onCopy) {
          HStack(spacing: 4) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
              .font(.system(size: 9, weight: .semibold))
            Text(copyLabel)
              .font(.system(size: 10, weight: .semibold))
              .lineLimit(1)
          }
          .foregroundStyle(Color(cardRGB: 0xFAFBF9))
          .padding(.horizontal, 9)
          .frame(height: 19)
          .background(Color(cardRGB: 0x7C916F), in: Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
      case .status(let omni, let gift):
        addressBar(systemImage: "shield.fill") {
          Text(omni)
            .font(.system(size: 8.6, weight: .semibold))
        }
        Text(gift)
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(Self.gold)
          .lineLimit(1)
          .fixedSize()
      }
    }
  }

  private func addressBar<Label: View>(systemImage: String, @ViewBuilder label: () -> Label) -> some View {
    HStack(spacing: 6) {
      Image(systemName: systemImage)
        .font(.system(size: 7.5))
        .foregroundStyle(Color(cardRGB: 0xA5B299))
      label()
        .foregroundStyle(Color(cardRGB: 0xD9DBD5))
        .lineLimit(1)
        // ⛔ Jamais tronqué : au pire, un peu plus petit.
        .minimumScaleFactor(0.75)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 9)
    .frame(height: 21)
    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
    }
  }

  // Au centre : le libellé et le code (de gauche à droite, même en arabe).
  private var middle: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(rtl ? label : label.uppercased())
        .font(.system(size: rtl ? 10.5 : 9.5, weight: .semibold))
        .tracking(rtl ? 0 : 1.7)
        .foregroundStyle(Self.gold)
        .lineLimit(1)
      Text(verbatim: code)
        .font(.system(size: 27, weight: .bold))
        .tracking(27 * 0.17)
        .foregroundStyle(Self.ink)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityLabel(code.map(String.init).joined(separator: " "))
    }
  }

  // En bas : l'icône et le logotype, la pastille « Un projet dev&din ».
  private var bottom: some View {
    HStack(spacing: 8) {
      HStack(spacing: 8) {
        Image(uiImage: art.icon)
          .resizable()
          .frame(width: 30, height: 30)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
        Image(uiImage: art.wordmark)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(height: 20)
          .accessibilityLabel(Text(verbatim: "Browther"))
      }
      Spacer(minLength: 4)
      HStack(spacing: 6) {
        Text(tag)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color.white.opacity(0.82))
          .lineLimit(1)
        Image(uiImage: art.devndin)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(height: 16)
          .accessibilityLabel(Text(verbatim: "dev&din"))
      }
      .padding(.leading, 11)
      .padding(.trailing, 10)
      .frame(height: 26)
      .background(Color.white.opacity(0.08), in: Capsule())
      .overlay { Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1) }
      .fixedSize()
    }
  }
}

/// La puce : ce qui fait lire « carte » au premier coup d'œil.
private struct ReferralCardChip: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(
        LinearGradient(
          stops: [
            .init(color: Color(cardRGB: 0xEFDCB2), location: 0),
            .init(color: Color(cardRGB: 0xC4A572), location: 0.55),
            .init(color: Color(cardRGB: 0x8E6B30), location: 1),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .frame(width: 46, height: 36)
      .overlay {
        Path { path in
          let sx = 46.0 / 36
          let sy = 36.0 / 28
          for y in [9.5, 18.5] {
            path.move(to: CGPoint(x: 0, y: y * sy))
            path.addLine(to: CGPoint(x: 12 * sx, y: y * sy))
            path.move(to: CGPoint(x: 24 * sx, y: y * sy))
            path.addLine(to: CGPoint(x: 36 * sx, y: y * sy))
          }
          for x in [12.0, 24.0] {
            path.move(to: CGPoint(x: x * sx, y: 0))
            path.addLine(to: CGPoint(x: x * sx, y: 28 * sy))
          }
          path.move(to: CGPoint(x: 12 * sx, y: 14 * sy))
          path.addLine(to: CGPoint(x: 24 * sx, y: 14 * sy))
        }
        .stroke(Color.black.opacity(0.35), lineWidth: 1)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(Color.black.opacity(0.2))
      }
  }
}

/// Les vagues des créas de la régie (`waves` : base sauge à .20, une ligne sur
/// six en or à .38), dans l'espace 330 × 208.
private struct ReferralCardWaves: View {
  var body: some View {
    Canvas { context, size in
      let sx = size.width / 330
      let sy = size.height / 208
      let count = Int(((208.0 + 30) / 10).rounded(.up))
      for i in 0..<count {
        let base = -5 + Double(i) * 10
        let phase = Double(i) * 0.18
        var path = Path()
        var x = -10.0
        while x <= 340 {
          let u = x * 0.024
          let y = base + (sin(u + phase) * 5 + sin(u * 2.1 + phase * 1.7) * 2.5 + sin(u * 0.4) * 2)
          let point = CGPoint(x: x * sx, y: y * sy)
          if x == -10 { path.move(to: point) } else { path.addLine(to: point) }
          x += 6
        }
        let accent = i % 6 == 0
        context.stroke(
          path,
          with: .color(
            accent
              ? Color(red: 184 / 255, green: 140 / 255, blue: 62 / 255).opacity(0.38)
              : Color(red: 124 / 255, green: 145 / 255, blue: 111 / 255).opacity(0.20)
          ),
          lineWidth: (accent ? 0.8 : 0.6) * sx
        )
      }
    }
    .allowsHitTesting(false)
  }
}

extension Color {
  /// `0xRRGGBB` → couleur FIXE (ni thème, ni contraste accru).
  fileprivate init(cardRGB rgb: Int) {
    self.init(
      red: Double((rgb >> 16) & 0xFF) / 255,
      green: Double((rgb >> 8) & 0xFF) / 255,
      blue: Double(rgb & 0xFF) / 255
    )
  }
}
