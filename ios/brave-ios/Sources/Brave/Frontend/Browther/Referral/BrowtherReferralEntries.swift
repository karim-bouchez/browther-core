// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
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
  /// ⚠️ L'icône se prend dans les 225 symboles Leo **embarqués** (`NalaAssets`) :
  /// `leo.gift` existe dans le paquet npm mais PAS dans le catalogue compilé —
  /// un nom absent donne une ligne sans icône, sans erreur.
  static let browtherReferral: Self = .init(
    id: "BrowtherReferral",
    title: Strings.BrowtherReferral.homeTitle,
    braveSystemImage: "leo.heart.outline",
    // ⚠️ Les 4 premières actions visibles forment la rangée « MES ACTIONS »
    // (`numberOfQuickActions`) : à 250 le parrainage y poussait **Partager**
    // dehors — or partager est un geste rapide, il doit y rester (Karim,
    // 2026-09-23). À 650, il ouvre la LISTE, juste sous « Partager » (600).
    defaultRank: 650,
    defaultVisibility: .visible
  )
}

/// La ligne des Paramètres : une carte, pas une ligne de liste — c'est la porte
/// qui rapporte des mois, elle se voit (Karim, 2026-09-23 : « un rendu un peu
/// plus stylé »). La pastille ne s'allume que quand une bonne nouvelle attend.
struct ReferralSettingsCard: View {
  let action: () -> Void

  @ObservedObject private var controller = BrowtherReferralController.shared

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(ReferralPalette.goldFill)
            .frame(width: 30, height: 30)
          Image(systemName: "gift.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(ReferralPalette.ink)
        }
        VStack(alignment: .leading, spacing: 1) {
          Text(Strings.BrowtherReferral.homeTitle)
            .font(.body)
            .foregroundStyle(Color(UIColor.braveLabel))
          Text(Strings.BrowtherReferral.settingsSubtitle)
            .font(.footnote)
            .foregroundStyle(Color(UIColor.secondaryBraveLabel))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 8)
        if controller.hasFreshNews {
          Circle()
            .fill(ReferralPalette.greenFill)
            .frame(width: 9, height: 9)
            .accessibilityLabel(Strings.BrowtherReferral.settingsNews)
        }
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color(UIColor.braveSeparator))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
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

/// La cellule qui porte la carte dans la table des Paramètres.
/// ⚠️ `UIHostingConfiguration` (iOS 16+) plutôt qu'un `UIHostingController`
/// posé à la main : pas de contrôleur orphelin à gérer, et la cellule se
/// redimensionne toute seule quand le texte grossit.
final class BrowtherReferralCardCell: UITableViewCell, Cell {
  func configure(row: Row) {
    selectionStyle = .none
    // 🔴 L'arrondi et la largeur viennent de `listGroupedCell()` — donc EXACTEMENT
    // ceux des autres sections (Karim, 2026-09-23 : « même format que les
    // autres »). Une carte dessinée à la main dans la cellule était plus
    // étroite et plus ronde que ses voisines. L'or ne fait que teinter le fond.
    var background = UIBackgroundConfiguration.listGroupedCell()
    background.backgroundColor = UIColor(ReferralPalette.goldSurfaceSolid)
    backgroundConfiguration = background
    contentConfiguration = UIHostingConfiguration {
      ReferralSettingsCard(action: { row.selection?() })
    }
  }
}
