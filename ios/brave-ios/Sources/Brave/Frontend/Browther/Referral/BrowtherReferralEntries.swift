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

/// ⭐ **La carte du parrainage dans les Paramètres — dessinée par nous.**
///
/// 🔴 Trois essais ont échoué avant (recette Karim, 2026-09-23), et chacun pour
/// la même raison : **ce qu'iOS dessine, iOS le redessine**. Un aplat doré posé
/// en `backgroundConfiguration` rendait le sous-titre gris illisible ; un
/// liseré se traçait à côté de la carte et disparaissait dès que la cellule
/// était réutilisée (un simple retour de navigation suffisait). D'où celle-ci :
/// la cellule n'a plus AUCUN fond système (`.clear()`), et la carte — fond,
/// contour, textes, chevron — est à nous. ⚠️ Le prix assumé (Karim) : si iOS
/// change les cotes de ses listes, il faudra revenir ici.
///
/// Les couleurs sont à nous aussi, donc le contraste est garanti des deux
/// côtés : un fond chaud très sombre / très clair, un titre en or, un
/// sous-titre assez contrasté (⛔ pas le gris secondaire d'iOS, illisible sur
/// un fond teinté).
struct ReferralSettingsCard: View {
  @ObservedObject private var controller = BrowtherReferralController.shared

  private static let subtitle = BrowtherIntroPalette.dynamic(light: 0x6B5A38, dark: 0xCDBC98)

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(
            LinearGradient(
              colors: [ReferralPalette.goldFill, ReferralPalette.goldFill.opacity(0.78)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: 32, height: 32)
        Image(systemName: "gift.fill")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(ReferralPalette.ink)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(Strings.BrowtherReferral.homeTitle)
          .font(.body.weight(.semibold))
          .foregroundStyle(ReferralPalette.gold)
        Text(Strings.BrowtherReferral.settingsSubtitle)
          .font(.footnote)
          .foregroundStyle(Self.subtitle)
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
        .foregroundStyle(ReferralPalette.gold.opacity(0.6))
    }
    .padding(.vertical, 2)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
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

/// La cellule ne porte plus que notre carte : aucun fond système, aucune
/// étiquette système. ⚠️ Le style est (re)posé à chaque passage de layout : une
/// cellule réutilisée repart sinon avec la configuration par défaut — c'est
/// exactement ce qui faisait disparaître le liseré au retour de navigation.
final class BrowtherReferralCardCell: UITableViewCell, Cell {
  private var styled = false

  func configure(row: Row) {
    selectionStyle = .none
    styled = false
    applyBrowtherStyle()
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    styled = false
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    applyBrowtherStyle()
  }

  private func applyBrowtherStyle() {
    guard !styled else { return }
    styled = true
    // 🔴 **La carte est celle du système, et elle le reste.** Cinq tentatives
    // pour teinter cette ligne ont échoué (recette Karim, 2026-09-23) : aplat
    // doré (effacé par la mise à jour automatique de la configuration), liseré
    // (dessiné à côté, puis perdu à la réutilisation), carte redessinée par
    // nous (les coins du système dépassaient derrière), teinte posée sur la
    // configuration système (ignorée, même transformateurs coupés). ⇒ On ne
    // touche plus au FOND : la forme, l'arrondi et les marges viennent de la
    // liste, donc ils sont justes, et la ligne se distingue par ce qu'on
    // maîtrise vraiment — l'icône cadeau et le titre en or.
    // ⛔ Ne pas retenter une teinte de fond sans avoir inspecté la hiérarchie
    // des vues sur l'appareil : quelque chose, dans cette table, gagne toujours.
    contentConfiguration = UIHostingConfiguration { ReferralSettingsCard() }
  }
}
