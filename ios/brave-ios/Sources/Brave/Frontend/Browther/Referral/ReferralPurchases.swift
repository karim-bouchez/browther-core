// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowtherReferral
import Foundation
import RevenueCat
import StoreKit
import UIKit

/// Le paiement sur iOS — `docs/PARRAINAGE.md` § 7.4 : **IAP obligatoire**, via
/// **RevenueCat**. ⛔ Jamais Polar ni Stripe dans l'app. ⛔ Les écrans de
/// paywall de RevenueCat ne sont pas utilisés : l'écran 7 est le nôtre.
///
/// ## La clé
///
/// La clé d'API **publique** de RevenueCat (`appl_…`) est faite pour vivre dans
/// le binaire : elle se pose en dur ci-dessous (⛔ jamais une clé secrète).
/// Projet RevenueCat **Browther** (`proj58d9b5d4`), app **Browther iOS**
/// (`app4a1a885cb6`, bundle `com.devndin.browther.ios.browser`), posée le
/// 2026-09-22 — cf. `private/docs/PARRAINAGE.md` § 5.
///
/// ## Le sujet est le MÊME que celui du parrainage (§ 7.1)
///
/// 🔴 `appUserID` **doit** être le sujet du parrainage : le webhook RevenueCat
/// (`referral.devndin.com/v1/webhooks/revenuecat/browther`) écrit la couverture
/// payée sur cet identifiant — un autre ferait atterrir le paiement sur un
/// sujet fantôme, et l'abonné continuerait d'être sollicité. ⭐ Mais l'app ne
/// DÉPEND pas du webhook pour ouvrir : `CustomerInfo` se lit en local, tout de
/// suite (statut effectif = max(accès payé, couverture)).
///
/// ⚠️ **Un build de dev (bundle `.BrowserBeta`) ne peut PAS acheter** : les
/// produits appartiennent à l'app `.browser`. L'offre y reste vide, l'écran 7
/// montre les prix de repli (`ReferralPricing`) et son bouton est grisé — c'est
/// normal. Les achats se recettent en TestFlight, avec un testeur Sandbox.
/// Le paquet RevenueCat, nommé sans ambiguïté pour le reste du module.
typealias RevenueCatPackage = RevenueCat.Package
/// Un produit du store lu par identifiant (les achats « une seule fois »).
typealias RevenueCatProduct = RevenueCat.StoreProduct

@MainActor
final class ReferralPurchases {
  static let shared = ReferralPurchases()

  static let publicKey = "appl_VyeTrvJvuMywzBjoKdoTRUMURWB"

  /// Le vrai paiement existe-t-il dans ce binaire ? (une clé posée)
  static var isReady: Bool { !publicKey.isEmpty }

  private var configuredFor: String?
  private var watchTask: Task<Void, Never>?

  /// Se présenter à RevenueCat sous l'identité du parrainage. Idempotent : un
  /// changement d'identité (recette, compte) passe par `logIn`, ⛔ pas une
  /// seconde configuration.
  func configure(subjectRef: String) async {
    guard Self.isReady, configuredFor != subjectRef else { return }
    if configuredFor == nil, !Purchases.isConfigured {
      Purchases.logLevel = .warn
      Purchases.configure(
        with: Configuration.Builder(withAPIKey: Self.publicKey)
          .with(appUserID: subjectRef)
          .build()
      )
    } else {
      // ⛔ Le paiement n'est pas le chemin critique : un échec ne se dit pas.
      _ = try? await Purchases.shared.logIn(subjectRef)
    }
    configuredFor = subjectRef
  }

  /// L'abonnement d'après l'APPAREIL — ⛔ rien ne passe par notre service.
  static func entitlement(of info: CustomerInfo?) -> LocalEntitlement? {
    guard let active = info?.entitlements[ReferralBilling.entitlement], active.isActive else {
      return nil
    }
    return LocalEntitlement(active: true, willRenew: active.willRenew, until: active.expirationDate)
  }

  func customerInfo() async -> CustomerInfo? {
    guard configuredFor != nil else { return nil }
    return try? await Purchases.shared.customerInfo()
  }

  /// RevenueCat pousse un `CustomerInfo` à chaque achat, renouvellement,
  /// restauration, expiration.
  func watch(_ onChange: @escaping @MainActor (CustomerInfo) -> Void) {
    guard configuredFor != nil else { return }
    watchTask?.cancel()
    watchTask = Task { @MainActor in
      for await info in Purchases.shared.customerInfoStream {
        onChange(info)
      }
    }
  }

  /// Les deux formules de l'offre courante, par période. ⚠️ Résolues par
  /// **identifiant de produit du store** (`ReferralBilling`), ⛔ pas par le type
  /// de paquet RevenueCat : c'est le contrat qu'on maîtrise des deux côtés.
  func packages() async -> [BillingPeriod: Package] {
    guard configuredFor != nil else {
      lastProblem = "RevenueCat pas encore configuré (pas de sujet)."
      return [:]
    }
    let offerings: Offerings
    do {
      offerings = try await Purchases.shared.offerings()
    } catch {
      lastProblem = "offres illisibles : \(error.localizedDescription)"
      return [:]
    }
    guard let current = offerings.current else {
      lastProblem = "aucune offre courante (\(offerings.all.count) offre(s) connues)."
      return [:]
    }
    var found: [BillingPeriod: Package] = [:]
    for item in current.availablePackages {
      let id = item.storeProduct.productIdentifier
      for period in BillingPeriod.allCases where id == ReferralBilling.productID(period) {
        found[period] = found[period] ?? item
      }
    }
    if found.isEmpty {
      // 🔴 Le cas vécu (recette Karim, 2026-09-24) : RevenueCat répond, l'offre
      // existe, mais l'App Store ne SERT aucun produit — cause la plus
      // fréquente : le contrat « Paid Applications » pas actif, ou des produits
      // créés il y a trop peu de temps.
      lastProblem =
        "l'offre « \(current.identifier) » n'a aucun produit servi par l'App Store "
        + "(\(current.availablePackages.count) paquet(s) reçus)."
    } else {
      lastProblem = nil
    }
    return found
  }

  /// ⛔ **Pas de panne muette** : pourquoi l'offre est vide, en clair. Lu par
  /// l'écran 7 (ligne + « Réessayer ») et par l'outil de recette.
  private(set) var lastProblem: String?

  enum Outcome {
    case purchased(CustomerInfo)
    /// ⚠️ Un abandon n'est pas un échec : fermer la feuille du store est une réponse.
    case cancelled
    case failed
  }

  func purchase(_ package: Package) async -> Outcome {
    do {
      let result = try await Purchases.shared.purchase(package: package)
      if result.userCancelled { return .cancelled }
      return Self.entitlement(of: result.customerInfo) != nil ? .purchased(result.customerInfo) : .failed
    } catch let error as ErrorCode where error == .purchaseCancelledError {
      return .cancelled
    } catch {
      return .failed
    }
  }

  // MARK: Le soutien ponctuel (§ 12.43)

  /// Les trois achats « une seule fois », lus par IDENTIFIANT. 🔴 ⛔ Hors offering
  /// et entitlement : RevenueCat donnerait à un achat non renouvelable un accès
  /// SANS fin — ce sont les mois crédités par le service qui ouvrent.
  func supportProducts() async -> [ReferralSupportOnce: StoreProduct] {
    guard configuredFor != nil else { return [:] }
    let products = await Purchases.shared.products(ReferralSupportOnce.allCases.map(\.productID))
    var found: [ReferralSupportOnce: StoreProduct] = [:]
    for product in products {
      if let item = ReferralSupportOnce.allCases.first(where: { $0.productID == product.productIdentifier }) {
        found[item] = product
      }
    }
    return found
  }

  enum SupportOutcome {
    case purchased
    /// ⚠️ Un abandon n'est pas un échec.
    case cancelled
    case failed
  }

  /// ⚠️ L'achat abouti n'ouvre RIEN en local (aucun entitlement) : le webhook
  /// RevenueCat → service crédite les mois, que l'app relit.
  func purchaseSupport(_ product: StoreProduct) async -> SupportOutcome {
    do {
      let result = try await Purchases.shared.purchase(product: product)
      if result.userCancelled { return .cancelled }
      return result.transaction != nil ? .purchased : .failed
    } catch let error as ErrorCode where error == .purchaseCancelledError {
      return .cancelled
    } catch {
      return .failed
    }
  }

  /// « Restaurer mes achats » — obligation Apple (§ 8).
  func restore() async -> CustomerInfo? {
    try? await Purchases.shared.restorePurchases()
  }

  /// La résiliation et les factures passent par l'App Store : c'est lui qui
  /// encaisse — ⛔ on ne réimplémente rien.
  static func manageSubscriptions(from view: UIView?) {
    if let scene = view?.window?.windowScene {
      Task { try? await AppStore.showManageSubscriptions(in: scene) }
    } else if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
      UIApplication.shared.open(url)
    }
  }
}

/// Un prix tel que le STORE le rend — Apple convertit pour chaque pays, et le
/// prix montré doit être celui débité. `ReferralPricing` n'est que le repli.
struct ReferralStorePrices: Equatable {
  var monthly: String
  var yearly: String
  /// Douze mois au tarif mensuel — le prix barré (seulement si l'annuel est moins cher).
  var yearlyStruck: String?
  /// Ce que l'annuel revient par mois — « soit 2,50 € par mois ».
  var yearlyPerMonth: String?
  /// Le badge « 2 mois offerts » ne se montre que si c'est vrai à ces prix-là.
  var showsFreeMonths: Bool

  static let fallback = ReferralStorePrices(
    monthly: ReferralPricing.monthly,
    yearly: ReferralPricing.yearly,
    yearlyStruck: ReferralPricing.yearlyStruck,
    yearlyPerMonth: ReferralPricing.yearlyPerMonth,
    showsFreeMonths: true
  )

  init(monthly: String, yearly: String, yearlyStruck: String?, yearlyPerMonth: String?, showsFreeMonths: Bool) {
    self.monthly = monthly
    self.yearly = yearly
    self.yearlyStruck = yearlyStruck
    self.yearlyPerMonth = yearlyPerMonth
    self.showsFreeMonths = showsFreeMonths
  }

  init(packages: [BillingPeriod: Package]) {
    guard let month = packages[.monthly]?.storeProduct, let year = packages[.yearly]?.storeProduct else {
      self = .fallback
      if let month = packages[.monthly]?.storeProduct { self.monthly = month.localizedPriceString }
      if let year = packages[.yearly]?.storeProduct { self.yearly = year.localizedPriceString }
      return
    }
    let formatter = year.priceFormatter
    func format(_ value: Decimal) -> String? {
      formatter?.string(from: NSDecimalNumber(decimal: value))
    }
    let twelve = month.price * 12
    let cheaper = year.price < twelve
    self.init(
      monthly: month.localizedPriceString,
      yearly: year.localizedPriceString,
      yearlyStruck: cheaper ? format(twelve) : nil,
      yearlyPerMonth: format(year.price / 12),
      showsFreeMonths: cheaper && (twelve - year.price) >= month.price * Decimal(ReferralPricing.yearlyFreeMonths) - 0.05
    )
  }
}

/// Les prix des trois achats « une seule fois », tels que le STORE les rend
/// (Apple convertit par pays) — `ReferralSupportOnce.fallbackPrice` en repli.
struct ReferralSupportPrices: Equatable {
  var byItem: [ReferralSupportOnce: String]

  init(products: [ReferralSupportOnce: RevenueCatProduct]) {
    var prices: [ReferralSupportOnce: String] = [:]
    for item in ReferralSupportOnce.allCases {
      prices[item] = products[item]?.localizedPriceString ?? item.fallbackPrice
    }
    byItem = prices
  }

  func price(_ item: ReferralSupportOnce) -> String { byItem[item] ?? item.fallbackPrice }
}
