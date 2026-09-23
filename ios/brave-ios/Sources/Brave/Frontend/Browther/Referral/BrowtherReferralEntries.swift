// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BraveUI
import BrowserMenu
import BrowtherReferral
import Static
import SwiftUI
import UIKit

/// Les **portes d'entrée** du parrainage, hors sollicitations : le menu « … »,
/// la ligne des Paramètres, et le rappel dans le panneau de la fonctionnalité
/// supplémentaire.
///
/// 🔴 **Le parrainage ne se trouvait qu'en BAS des Paramètres, dans « Aide »**
/// (recette Karim, 2026-09-22 : « il est quand même bien caché »). Or c'est la
/// seule façon d'avoir les fonctionnalités supplémentaires sans payer : une
/// porte qu'on ne trouve pas vaut une porte fermée. Trois entrées, et aucune
/// sur le Nouvel Onglet (déjà chargé, et c'est là que les écrans DATÉS du flow
/// s'ouvrent — `docs/PARRAINAGE.md` § 3.4).
extension Action.Identifier {
  /// ⭐ Le libellé dit ce qu'on FAIT, ⛔ pas le nom du dispositif : « Parrainage »
  /// ne donne envie à personne dans un menu (Karim, 2026-09-23 — le patron de
  /// « Offre Claude en cadeau »). L'icône est un **cadeau**.
  /// ⚠️ `sf:` = un SF Symbol : les 225 symboles Leo embarqués (`NalaAssets`)
  /// n'ont pas de cadeau, et un nom Leo absent donne une ligne SANS icône, sans
  /// erreur.
  static let browtherReferral: Self = .init(
    id: "BrowtherReferral",
    title: Strings.BrowtherReferral.menuInvite,
    braveSystemImage: "sf:gift.fill",
    // ⚠️ Les 4 premières actions visibles forment la rangée « MES ACTIONS »
    // (`numberOfQuickActions`) : à 250 le parrainage y poussait **Partager**
    // dehors — or partager est un geste rapide, il doit y rester (Karim,
    // 2026-09-23). À 650, il ouvre la LISTE, juste sous « Partager » (600).
    defaultRank: 650,
    defaultVisibility: .visible
  )
}

/// L'icône de la ligne des Paramètres : le cadeau doré, dans un carré arrondi —
/// le langage des icônes de réglages d'iOS. ⚠️ Dessinée en UIKit, parce que la
/// LIGNE doit rester une cellule standard : même police, même chevron, mêmes
/// marges que ses voisines (recette Karim, 2026-09-23 — une carte dessinée à la
/// main ne tombait juste ni sur la fonte, ni sur la flèche).
enum ReferralSettingsIcon {
  static func make() -> UIImage {
    let side: CGFloat = 30
    let renderer = UIGraphicsImageRenderer(size: .init(width: side, height: side))
    return renderer.image { context in
      let rect = CGRect(x: 0, y: 0, width: side, height: side)
      UIColor(ReferralPalette.goldFill).setFill()
      UIBezierPath(roundedRect: rect, cornerRadius: 7).fill()
      let symbol = UIImage(
        systemName: "gift.fill",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
      )?
      .withTintColor(UIColor(ReferralPalette.ink), renderingMode: .alwaysOriginal)
      symbol?.draw(
        in: CGRect(
          x: (side - (symbol?.size.width ?? 0)) / 2,
          y: (side - (symbol?.size.height ?? 0)) / 2,
          width: symbol?.size.width ?? 0,
          height: symbol?.size.height ?? 0
        )
      )
      _ = context
    }
  }
}

/// ⭐ Le rappel **dans le panneau de la fonctionnalité elle-même** (Karim,
/// 2026-09-23) : c'est au moment où l'on touche au retrait de la musique qu'on
/// veut savoir qu'elle se garde à vie en invitant, et pouvoir le faire tout de
/// suite.
///
/// ⚠️ Il ne dit rien tant que l'annonce dort (§ 12.11 : avant l'annonce, tout
/// est ouvert et rien ne se réclame), ni à qui a déjà l'accès à vie ou un
/// abonnement — il n'y aurait plus rien à gagner.
struct ReferralExtraCallout: View {
  @ObservedObject private var controller = BrowtherReferralController.shared

  var body: some View {
    if let line = controller.extraCalloutLine {
      Button {
        guard let host = BrowtherReferralPresenter.topController() else { return }
        controller.track("paywall_action", ["screen": "panel", "action": "invite"])
        BrowtherReferralPresenter.present(.support(locked: false), from: host)
      } label: {
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "gift.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(ReferralPalette.gold)
            .padding(.top, 1)
          VStack(alignment: .leading, spacing: 3) {
            Text(Strings.BrowtherReferral.panelExtraBadge)
              .font(.caption.weight(.semibold))
              .foregroundStyle(ReferralPalette.gold)
            Text(line)
              .font(.footnote)
              .foregroundStyle(Color(UIColor.braveLabel))
              .multilineTextAlignment(.leading)
              .fixedSize(horizontal: false, vertical: true)
            Text(Strings.BrowtherReferral.panelKeepForLife)
              .font(.footnote.weight(.semibold))
              .foregroundStyle(ReferralPalette.gold)
          }
          Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(ReferralPalette.goldSurface)
        )
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .padding(.horizontal)
    }
  }
}

/// La cellule : une `MultilineSubtitleCell` ordinaire — ⛔ rien n'est redessiné
/// (fond, police, chevron, marges viennent d'iOS) — avec le titre en or et
/// l'icône cadeau pour la faire ressortir, et la pastille verte quand une bonne
/// nouvelle attend.
///
/// ⚠️ **Le style se pose dans `layoutSubviews` / `didMoveToWindow`, ⛔ pas dans
/// `configure(row:)`** : ce dernier vient d'une extension de protocole
/// (`Static.Cell`), il n'est donc pas surchargeable — et c'est lui qui écrit le
/// chevron, donc il faut passer APRÈS lui.
final class BrowtherReferralCardCell: MultilineSubtitleCell {
  /// 🔴 **Ni aplat, ni liseré** (deux essais, deux échecs en recette le
  /// 2026-09-23) : l'aplat doré rendait le sous-titre gris illisible dans les
  /// deux thèmes, et le liseré d'une `backgroundConfiguration` se dessinait à
  /// côté de la carte ET disparaissait dès que la cellule était réutilisée (un
  /// retour de navigation suffisait — iOS refait la configuration tout seul).
  /// Ce qui reste est ce qu'on maîtrise : le **titre en or** et l'icône. L'or du
  /// TEXTE (§ 12.24) s'assombrit sur fond clair, donc le contraste tient des
  /// deux côtés.
  private func applyBrowtherStyle() {
    textLabel?.textColor = UIColor(ReferralPalette.gold)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // ⚠️ Ici, et pas seulement à la configuration : une cellule réutilisée
    // repart avec la couleur de texte par défaut.
    applyBrowtherStyle()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard window != nil else { return }
    applyBrowtherStyle()
    guard MainActor.assumeIsolated({ BrowtherReferralController.shared.hasFreshNews }) else {
      accessoryView = nil
      accessoryType = .disclosureIndicator
      return
    }
    // La pastille ne REMPLACE pas le chevron : elle se pose devant lui.
    let dot = UIView(frame: .init(x: 0, y: 5, width: 10, height: 10))
    dot.backgroundColor = UIColor(ReferralPalette.greenFill)
    dot.layer.cornerRadius = 5
    dot.isAccessibilityElement = true
    dot.accessibilityLabel = Strings.BrowtherReferral.settingsNews
    let chevron = UIImageView(
      image: UIImage(systemName: "chevron.right")?
        .withConfiguration(UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
    )
    chevron.tintColor = .tertiaryLabel
    chevron.frame = .init(x: 18, y: 2, width: 10, height: 16)
    let holder = UIView(frame: .init(x: 0, y: 0, width: 30, height: 20))
    holder.addSubview(dot)
    holder.addSubview(chevron)
    accessoryType = .none
    accessoryView = holder
  }
}
