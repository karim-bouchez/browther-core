// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BrowtherReferral
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
struct ReferralBillingBody: View {
  /// Aperçu de recette : le bouton a son vrai visage même sans offre — c'est de
  /// là que se prend la capture de vérification d'App Store Connect.
  var preview = false

  @ObservedObject private var controller = BrowtherReferralController.shared
  @State private var restoring = false

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

  private var offer: some View {
    let prices = controller.prices
    return VStack(spacing: 16) {
      VStack(spacing: 8) {
        ReferralFlowTitle(text: Strings.BrowtherReferral.billingTitle)
        ReferralFlowBody(text: Strings.BrowtherReferral.billingBody)
      }
      ReferralFeatureList(extras: .included, extrasOnly: true)
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
      Text(Strings.BrowtherReferral.billingLegal)
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
    }
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
    let selected = controller.period == period
    return Button {
      UISelectionFeedbackGenerator().selectionChanged()
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
      let label = controller.period == .yearly
        ? Strings.BrowtherReferral.billingCtaYear(prices.yearly)
        : Strings.BrowtherReferral.billingCtaMonth(prices.monthly)
      let canBuy = preview || controller.packages[controller.period] != nil
      Button {
        buy()
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
    }
  }

  private func buy() {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    guard !preview else { return }
    buying = true
    Task { @MainActor in
      let outcome = await controller.buy(controller.period)
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
