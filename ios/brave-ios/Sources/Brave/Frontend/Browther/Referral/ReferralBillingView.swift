// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BrowtherReferral
import Shared
import SwiftUI
import UIKit

/// Soutenir financièrement (écran 7) — ce qu'on débloque, annuel / mensuel,
/// « Je soutiens · … », restaurer — `docs/PARRAINAGE.md` § 3, pendant de
/// `fajrunaa/components/referral/Billing.tsx`.
///
/// ⭐ **Deux habits, une seule rédaction** : la fenêtre du flow (par-dessus les
/// trois façons) et l'onglet « Soutenir » de l'écran Parrainage (§ 12.26 : un
/// onglet CHOISI montre directement les formules). Le corps et le bouton sont
/// séparés parce que chaque habit pose le bouton à sa façon.
///
/// 🔴 **Le prix affiché est celui du STORE** : Apple convertit pour chaque pays,
/// et le prix montré doit être celui débité (`ReferralStorePrices`).
/// ⭐ **Le bouton nomme le GESTE** : « Je soutiens · 29,99 € par an », ⛔ pas
/// « Continuer ». 🔴 **App Review 3.1.2** : les liens Conditions et
/// Confidentialité, qui MARCHENT, dans l'écran d'achat lui-même. ⚠️ La
/// résiliation et les factures passent par l'App Store : ⛔ on ne réimplémente
/// rien, et on ne remontre pas ses tarifs à un abonné (§ 12.19).
///
/// ⭐ **« ou une seule fois, sans abonnement »** (le soutien ponctuel, § 12.43,
/// maquette du 2026-10-12) : trois achats non renouvelables sous les deux
/// formules — 1, 2 ou 6 mois. ⛔ Ni pour un abonné actif ni pour un accès à vie
/// (`offersSupportOnce`). ⛔ Aucun lien vers le site (Apple 3.1.1, 3.1.3).
/// ⛔ Le mot « don » nulle part.
struct ReferralBillingBody: View {
  /// Aperçu de recette : le bouton a son vrai visage même sans offre — c'est de
  /// là que se prend la capture de vérification d'App Store Connect.
  var preview = false

  @ObservedObject private var controller = BrowtherReferralController.shared
  @Environment(\.referralNote) private var note
  @State private var restoring = false
  @State private var showsSignIn = false

  var body: some View {
    if controller.known?.subscription.active == true {
      subscribed
    } else {
      offer
    }
  }

  private var subscribed: some View {
    VStack(spacing: 14) {
      ReferralRoundIcon(systemName: "heart.fill", tone: .green)
      ReferralFlowTitle(text: Strings.BrowtherReferral.billingAlreadyTitle)
      ReferralFlowBody(text: Strings.BrowtherReferral.billingAlreadyBody)
      if let subscription = controller.known?.subscription,
        let until = ReferralDate.parse(subscription.until)
      {
        let date = BrowtherReferralController.formatDate(until, withYear: true)
        ReferralFlowBody(
          text: subscription.willRenew
            ? Strings.BrowtherReferral.billingRenews(date)
            : Strings.BrowtherReferral.billingEnds(date)
        )
      }
      Text(Strings.BrowtherReferral.billingManageHint)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
  }

  /// Les trois achats se montrent-ils ? Dans un binaire du store, seulement si
  /// l'App Store les SERT (⛔ jamais trois tuiles qui ne paient pas) ; en build
  /// de dev et en aperçu, toujours — avec les prix de repli, pour la recette.
  static func showsSupportOnce(_ controller: BrowtherReferralController, preview: Bool) -> Bool {
    guard controller.known?.offersSupportOnce == true else { return false }
    return preview || !controller.supportProducts.isEmpty || AppConstants.buildChannel != .release
  }

  private var offer: some View {
    let prices = controller.prices
    return VStack(spacing: 16) {
      VStack(spacing: 8) {
        ReferralFlowTitle(text: Strings.BrowtherReferral.billingTitle)
        ReferralFlowBody(text: Strings.BrowtherReferral.billingBody)
      }
      ReferralFeatureList(extras: .included, extrasOnly: true)
      // ⭐ Un soutien ponctuel qui court : « couvert jusqu'au … », ⛔ sans
      // « Gérer mon abonnement » (il n'y a rien à résilier). Les tarifs restent.
      if let support = controller.known?.support, support.active,
        let until = ReferralDate.parse(support.until)
      {
        ReferralFlowBody(
          text: Strings.BrowtherReferral.billingCoveredUntil(
            BrowtherReferralController.formatDate(until, withYear: true)
          )
        )
      }
      VStack(spacing: 10) {
        plan(
          .yearly,
          title: Strings.BrowtherReferral.billingYear,
          badge: prices.showsFreeMonths ? Strings.BrowtherReferral.billingYearBadge : nil,
          price: prices.yearly,
          struck: prices.yearlyStruck,
          sub: prices.yearlyPerMonth.map(Strings.BrowtherReferral.billingYearSub)
            ?? Strings.BrowtherReferral.billingMonthSub
        )
        plan(
          .monthly,
          title: Strings.BrowtherReferral.billingMonth,
          badge: nil,
          price: prices.monthly,
          struck: nil,
          sub: Strings.BrowtherReferral.billingMonthSub
        )
      }
      if Self.showsSupportOnce(controller, preview: preview) {
        supportOnce
      }
      Text(
        controller.supportChoice != nil
          ? Strings.BrowtherReferral.billingOnceLegalApple
          : Strings.BrowtherReferral.billingLegal
      )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 8) {
        legalLink(Strings.BrowtherReferral.billingTerms, page: "terms")
        Text("·").font(.footnote).foregroundStyle(.tertiary)
        legalLink(Strings.BrowtherReferral.billingPrivacy, page: "privacy")
      }
      // ⭐ « Restaurer mes achats » : obligation Apple (§ 8), avec sa raison.
      Button {
        restore()
      } label: {
        Text(Strings.BrowtherReferral.billingRestore)
          .font(.footnote.weight(.medium))
          .foregroundStyle(.primary)
          .multilineTextAlignment(.center)
          .padding(.vertical, 6)
      }
      .buttonStyle(.plain)
      .disabled(restoring || preview)
      // ⭐ La vraie réponse à « j'ai payé ailleurs » (recette Karim, 2026-09-24 :
      // payé sur le Mac, « Restaurer » ne ramène que les achats Apple). Le
      // compte dev&din est le seul pont entre Polar et StoreKit.
      if controller.account == nil, !preview {
        Button {
          note(.paywallAction, ["screen": "billing", "action": "account"])
          showsSignIn = true
        } label: {
          Text(Strings.BrowtherReferral.billingElsewhere)
            .font(.footnote.weight(.medium))
            .foregroundStyle(ReferralPalette.green)
            .multilineTextAlignment(.center)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        // ⭐ Le scanner, pas la connexion : l'ordinateur où on a payé affiche
        // le QR (connecté ou non), cet iPhone le scanne (`ReferralLinkFlowSheet`).
        .sheet(isPresented: $showsSignIn) {
          ReferralLinkFlowSheet(start: nil)
        }
      }
    }
  }

  /// « ou une seule fois, sans abonnement », puis les trois achats côte à côte
  /// (1 · 2 · 6 mois, prix du store), et ce que l'achat choisi donne.
  private var supportOnce: some View {
    let prices = controller.supportPrices
    return VStack(spacing: 10) {
      HStack(spacing: 10) {
        Rectangle().fill(ReferralPalette.line).frame(height: 1)
        Text(Strings.BrowtherReferral.billingOnceSeparator)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize()
        Rectangle().fill(ReferralPalette.line).frame(height: 1)
      }
      .padding(.top, 2)
      HStack(spacing: 8) {
        ForEach(ReferralSupportOnce.allCases, id: \.self) { item in
          supportTile(item, price: prices.price(item))
        }
      }
      if let choice = controller.supportChoice {
        Text(Strings.BrowtherReferral.billingOnceNote(choice.months))
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func supportTile(_ item: ReferralSupportOnce, price: String) -> some View {
    let selected = controller.supportChoice == item
    return Button {
      UISelectionFeedbackGenerator().selectionChanged()
      controller.supportChoice = item
    } label: {
      VStack(spacing: 4) {
        Text(Strings.BrowtherReferral.billingOnceMonths(item.months))
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Text(price)
          .font(.footnote.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .padding(.horizontal, 6)
      .background {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(selected ? ReferralPalette.greenSurface : ReferralPalette.panel)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(selected ? ReferralPalette.green : ReferralPalette.line, lineWidth: selected ? 1.5 : 1)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
  }

  /// Une formule. Sélectionnée = la surface verte du parrainage + un bouton radio plein.
  private func plan(
    _ period: BillingPeriod,
    title: String,
    badge: String?,
    price: String,
    struck: String?,
    sub: String
  ) -> some View {
    let selected = controller.supportChoice == nil && controller.period == period
    return Button {
      UISelectionFeedbackGenerator().selectionChanged()
      controller.supportChoice = nil
      controller.period = period
    } label: {
      HStack(alignment: .center, spacing: 12) {
        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
          .font(.system(size: 20))
          .foregroundStyle(selected ? ReferralPalette.green : Color.secondary)
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 8) {
            Text(title)
              .font(.headline)
            if let badge {
              Text(badge)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(ReferralPalette.greenFill, in: Capsule())
            }
          }
          Text(sub)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 2) {
          if let struck {
            Text(struck)
              .font(.footnote)
              .strikethrough()
              .foregroundStyle(.secondary)
          }
          Text(price)
            .font(.headline.monospacedDigit())
        }
      }
      .padding(14)
      .background {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(selected ? ReferralPalette.greenSurface : ReferralPalette.panel)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(selected ? ReferralPalette.green : ReferralPalette.line, lineWidth: selected ? 1.5 : 1)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
  }

  /// Un lien vers une page légale du site, dans la langue de l'app.
  private func legalLink(_ label: String, page: String) -> some View {
    Button {
      let language = ["fr", "ar", "en"].first { (Bundle.main.preferredLocalizations.first ?? "").hasPrefix($0) } ?? "en"
      if let url = URL(string: "\(ReferralProduct.siteURL)/\(language)/\(page)") {
        UIApplication.shared.open(url)
      }
    } label: {
      Text(label)
        .font(.footnote)
        .underline()
        .foregroundStyle(.secondary)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(.isLink)
  }

  private func restore() {
    restoring = true
    Task { @MainActor in
      let restored = await controller.restorePurchases()
      restoring = false
      BrowtherReferralToast.show(
        title: restored ? Strings.BrowtherReferral.billingRestored : Strings.BrowtherReferral.billingRestoreNone,
        persistent: false,
        duration: 4
      )
    }
  }
}

/// Le bouton principal : « Je soutiens · prix » — ou « Gérer mon abonnement » pour un abonné.
struct ReferralBillingCTA: View {
  var preview = false
  /// L'achat a abouti : l'appelant ouvre « Merci ».
  var onPurchased: () -> Void

  @ObservedObject private var controller = BrowtherReferralController.shared
  @State private var buying = false

  var body: some View {
    if controller.known?.subscription.active == true {
      ReferralSecondaryButton(label: Strings.BrowtherReferral.billingManage) {
        ReferralPurchases.manageSubscriptions(from: BrowtherReferralPresenter.topController()?.view)
      }
    } else {
      let prices = controller.prices
      // ⭐ Un achat « une seule fois » choisi : « Je soutiens · 9,99 € une fois ».
      // ⚠️ Choisi puis devenu invisible (abonné entre-temps) : la formule reprend.
      let once = ReferralBillingBody.showsSupportOnce(controller, preview: preview) ? controller.supportChoice : nil
      let label = once.map { Strings.BrowtherReferral.billingOnceCta(controller.supportPrices.price($0)) }
        ?? (controller.period == .yearly
          ? Strings.BrowtherReferral.billingCtaYear(prices.yearly)
          : Strings.BrowtherReferral.billingCtaMonth(prices.monthly))
      let canBuy = preview
        || (once.map { controller.supportProducts[$0] != nil } ?? (controller.packages[controller.period] != nil))
      Button {
        buy(once: once)
      } label: {
        ZStack {
          Text(label)
            .opacity(buying ? 0 : 1)
          if buying {
            ProgressView().tint(Color(UIColor.systemBackground))
          }
        }
      }
      .buttonStyle(BrowtherIntroPrimaryButtonStyle())
      .opacity(canBuy ? 1 : 0.4)
      .disabled(!canBuy || buying)
      // ⛔ **Un bouton grisé sans explication est une panne muette** (recette
      // Karim, 2026-09-24 : « le bouton est grisé, je ne peux pas tester »).
      // Quand l'App Store ne sert pas les formules, on le DIT, et on propose de
      // réessayer.
      if !canBuy {
        VStack(spacing: 6) {
          Text(Self.devBuildNote ?? Strings.BrowtherReferral.billingUnavailable)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
          // Réessayer n'a de sens que si le store PEUT servir les formules.
          if Self.devBuildNote == nil {
            Button(Strings.BrowtherReferral.billingRetry) {
              Task { await controller.reloadPackages() }
            }
            .font(.footnote.weight(.semibold))
          }
        }
        .padding(.top, 6)
      }
    }
  }

  /// 🔴 **Dans un build de dev, le bouton EST grisé, et c'est normal** : le
  /// bundle `.BrowserBeta` n'existe pas dans App Store Connect, donc l'App Store
  /// ne sert aucune formule. Le dire ici a coûté une demi-journée de fausse
  /// piste (recette Karim, 2026-09-24 : « le bouton est grisé, je ne peux pas
  /// tester » — il était sur le build de dev). ⛔ Texte interne, non traduit : il
  /// n'existe pas dans les binaires du store.
  private static var devBuildNote: String? {
    guard AppConstants.buildChannel != .release else { return nil }
    return "Build de dev : l'App Store ne sert pas les formules ici (bundle .BrowserBeta). L'achat se recette en TestFlight."
  }

  private func buy(once: ReferralSupportOnce?) {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    // ⛔ Pas de bouton muet : un aperçu n'achète rien, et il le dit (recette
    // Karim, 2026-09-22 : « quand je clique sur "je soutiens" ça ne fait rien »).
    guard !preview else {
      BrowtherReferralToast.show(
        title: "Aperçu : l'achat ne part pas",
        body: "Pour acheter vraiment : onglet « Soutenir » de l'écran Parrainage.",
        persistent: false,
        duration: 5
      )
      return
    }
    buying = true
    Task { @MainActor in
      let outcome: BrowtherReferralController.BuyOutcome
      if let once {
        outcome = await controller.buySupport(once)
      } else {
        outcome = await controller.buy(controller.period)
      }
      buying = false
      switch outcome {
      case .purchased:
        onPurchased()
      case .cancelled:
        break
      case .failed:
        BrowtherReferralToast.show(title: Strings.BrowtherReferral.billingFailed, persistent: false, duration: 6)
      }
    }
  }
}
