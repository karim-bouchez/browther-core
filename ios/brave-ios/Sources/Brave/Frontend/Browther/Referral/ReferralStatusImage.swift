// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import SwiftUI
import UIKit

/// L'image du **statut WhatsApp** qui porte le code (1080 × 1920) —
/// `devndin/docs/PARRAINAGE-partage-statut.md`, jumeau de
/// `website/lib/statusImage.ts` (le même dessin, validé par Karim sur Sawtunaa
/// le 2026-09-29).
///
/// De haut en bas : le texte au « tu » (au pluriel en arabe), style
/// surligneur · la carte B9 inclinée (−4°, +4° en arabe), ⛔ SANS lien ni
/// « Copier » · l'étiquette « Clique sur le lien en dessous 👇 », droite,
/// posée juste au-dessus de la légende — qui ne contient QUE le lien
/// (`ReferralSharing.shareStatus` : l'image + le lien en texte).
///
/// 🔴 WhatsApp pose la légende PAR-DESSUS le bas de l'image, et « N vues »
/// dessous : ~250 px du bas sont couverts (recette iPhone Sawtunaa du
/// 2026-09-29). L'étiquette est à 270 px du bas — ⛔ ne pas la redescendre.
///
/// Police : celle du système (SF, et SF Arabic pour l'arabe) — ⚠️ le site
/// dessine en Inter Tight / Alexandria : mêmes cotes, lignes coupées un peu
/// différemment.
@MainActor
enum ReferralStatusImage {
  static let size = CGSize(width: 1080, height: 1920)
  private static let margin: CGFloat = 72

  private static let sage = UIColor(red: 0x5F / 255, green: 0x74 / 255, blue: 0x54 / 255, alpha: 1)
  private static let gold = UIColor(red: 0xC4 / 255, green: 0xA5 / 255, blue: 0x72 / 255, alpha: 1)

  static func render(
    code: String,
    texts: Strings.BrowtherReferral.StatusImage,
    art: ReferralCardArt = .bundled
  ) -> UIImage {
    let rtl = texts.isRTL
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      let cg = context.cgContext
      UIColor(red: 0x13 / 255, green: 0x13 / 255, blue: 0x16 / 255, alpha: 1).setFill()
      cg.fill(CGRect(origin: .zero, size: size))
      let glow = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
          UIColor(red: 124 / 255, green: 145 / 255, blue: 111 / 255, alpha: 0.30).cgColor,
          UIColor(red: 124 / 255, green: 145 / 255, blue: 111 / 255, alpha: 0).cgColor,
        ] as CFArray,
        locations: [0, 1]
      )
      if let glow {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.36)
        cg.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: size.width * 0.95, options: [])
      }

      // Le haut reste libre : WhatsApp y pose le nom et l'heure.
      let textBottom = drawParagraphs(texts.paragraphs, rtl: rtl, top: 170)

      // L'étiquette, droite, juste au-dessus de la légende (le lien).
      let stickerFont = UIFont.systemFont(ofSize: 54, weight: .heavy)
      let sticker = NSAttributedString(
        string: texts.sticker,
        attributes: [.font: stickerFont, .foregroundColor: UIColor(white: 0.07, alpha: 1)]
      )
      let stickerSize = sticker.size()
      let stW = stickerSize.width + 64
      let stH: CGFloat = 54 * 1.75
      let stY = size.height - 270 - stH
      let stRect = CGRect(x: (size.width - stW) / 2, y: stY, width: stW, height: stH)
      cg.saveGState()
      cg.setShadow(offset: CGSize(width: 0, height: 16), blur: 40, color: UIColor.black.withAlphaComponent(0.35).cgColor)
      UIColor.white.setFill()
      UIBezierPath(roundedRect: stRect, cornerRadius: 26).fill()
      cg.restoreGState()
      sticker.draw(at: CGPoint(x: stRect.midX - stickerSize.width / 2, y: stRect.midY - stickerSize.height / 2 + 2))

      // La carte, inclinée, dans l'espace entre le texte et l'étiquette.
      let room = stY - 70 - (textBottom + 90)
      let cw = max(560, min(860, room / (1 / 1.586 + 0.12)))
      let ch = cw / 1.586
      let cy = textBottom + 90 + (room - ch) / 2 + ch / 2
      let face = ReferralCardFace(
        code: code,
        face: .status(omni: texts.cardOmni, gift: texts.cardGift),
        tab: texts.cardTab,
        label: texts.cardLabel,
        tag: texts.tag,
        art: art,
        rtl: rtl
      )
      .environment(\.colorScheme, .dark)
      let renderer = ImageRenderer(content: face)
      renderer.scale = cw / ReferralCardFace.size.width
      if let card = renderer.uiImage {
        cg.saveGState()
        cg.translateBy(x: size.width / 2, y: cy)
        cg.rotate(by: (rtl ? 4 : -4) * .pi / 180)
        cg.setShadow(offset: CGSize(width: 0, height: 36), blur: 70, color: UIColor.black.withAlphaComponent(0.65).cgColor)
        card.draw(in: CGRect(x: -cw / 2, y: -ch / 2, width: cw, height: ch))
        cg.restoreGState()
      }
    }
  }

  // MARK: - Le texte, style surligneur

  private enum Mark { case none, highlight, gold }

  private struct Word {
    let text: String
    let mark: Mark
    /// Collé au mot d'avant, sans espace (« bonus]]. » → le point suit le surligné).
    let glue: Bool
    var width: CGFloat = 0
  }

  /// `[[a]] b {{c}}` → mots marqués. Même découpe que `parseWords` du site.
  private static func words(_ paragraph: String) -> [Word] {
    var result: [Word] = []
    var rest = Substring(paragraph)
    var previousEndsWithSpace = true
    while !rest.isEmpty {
      let chunk: Substring
      let mark: Mark
      if rest.hasPrefix("[["), let end = rest.range(of: "]]") {
        chunk = rest[rest.index(rest.startIndex, offsetBy: 2)..<end.lowerBound]
        mark = .highlight
        rest = rest[end.upperBound...]
      } else if rest.hasPrefix("{{"), let end = rest.range(of: "}}") {
        chunk = rest[rest.index(rest.startIndex, offsetBy: 2)..<end.lowerBound]
        mark = .gold
        rest = rest[end.upperBound...]
      } else {
        let next = [rest.range(of: "[["), rest.range(of: "{{")].compactMap { $0?.lowerBound }.min() ?? rest.endIndex
        let stop = next == rest.startIndex ? rest.index(after: rest.startIndex) : next
        chunk = rest[..<stop]
        mark = .none
        rest = rest[stop...]
      }
      let glueFirst = !previousEndsWithSpace && !chunk.hasPrefix(" ")
      for (i, piece) in chunk.split(separator: " ", omittingEmptySubsequences: false).enumerated() where !piece.isEmpty {
        result.append(Word(text: String(piece), mark: mark, glue: i == 0 && glueFirst && !result.isEmpty))
      }
      previousEndsWithSpace = chunk.hasSuffix(" ")
    }
    return result
  }

  /// Le texte, mot à mot : le surligné se pose derrière des groupes de mots, ligne par ligne.
  /// Rend la ligne de base de la dernière ligne.
  private static func drawParagraphs(_ paragraphs: [String], rtl: Bool, top: CGFloat) -> CGFloat {
    let fontSize: CGFloat = rtl ? 46 : 50
    let lineHeight = fontSize * (rtl ? 1.75 : 1.42)
    let paragraphGap = fontSize * 0.8
    let maxWidth = size.width - 2 * margin
    let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
    let space = NSAttributedString(string: " ", attributes: [.font: font]).size().width
    let pad = fontSize * 0.18
    var y = top

    for paragraph in paragraphs {
      let measured = words(paragraph).map { word -> Word in
        var word = word
        word.width = NSAttributedString(string: word.text, attributes: [.font: font]).size().width
        return word
      }
      var lines: [[Word]] = []
      var current: [Word] = []
      var currentWidth: CGFloat = 0
      for word in measured {
        let next = current.isEmpty ? word.width : currentWidth + (word.glue ? 0 : space) + word.width
        if !current.isEmpty && next > maxWidth - pad * 2 {
          lines.append(current)
          current = [word]
          currentWidth = word.width
        } else {
          current.append(word)
          currentWidth = next
        }
      }
      if !current.isEmpty { lines.append(current) }

      for line in lines {
        y += lineHeight
        // Position de chaque mot (de droite à gauche en arabe).
        var x = rtl ? size.width - margin - pad : margin + pad
        var previous: Mark?
        var placed: [(word: Word, x0: CGFloat)] = []
        for (i, word) in line.enumerated() {
          let edge = (word.mark != previous && (word.mark != .none || (previous ?? .none) != .none)) ? pad : 0
          let gap = i == 0 ? 0 : (word.glue ? edge : space + edge)
          previous = word.mark
          let x0 = rtl ? x - gap - word.width : x + gap
          x = rtl ? x0 : x0 + word.width
          placed.append((word, x0))
        }
        // Les surlignés : un bloc par suite de mots de même marque.
        var i = 0
        while i < placed.count {
          let mark = placed[i].word.mark
          var j = i
          while j + 1 < placed.count && placed[j + 1].word.mark == mark { j += 1 }
          if mark != .none {
            let left = min(placed[i].x0, placed[j].x0)
            let right = max(placed[i].x0 + placed[i].word.width, placed[j].x0 + placed[j].word.width)
            let rect = CGRect(x: left - pad, y: y - fontSize * 0.98, width: right - left + pad * 2, height: fontSize * 1.3)
            (mark == .gold ? gold : sage).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: fontSize * 0.16).fill()
          }
          i = j + 1
        }
        for (word, x0) in placed {
          let color = word.mark == .gold ? UIColor(red: 0x16 / 255, green: 0x19 / 255, blue: 0x1A / 255, alpha: 1) : .white
          // `draw(at:)` pose le HAUT de la ligne : on remonte de l'ascendante pour tomber sur la ligne de base.
          NSAttributedString(string: word.text, attributes: [.font: font, .foregroundColor: color])
            .draw(at: CGPoint(x: x0, y: y - font.ascender))
        }
      }
      y += paragraphGap
    }
    return y - paragraphGap
  }
}
