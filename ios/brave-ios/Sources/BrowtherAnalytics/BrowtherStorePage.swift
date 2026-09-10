// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import StoreKit
import UIKit

/// La fiche App Store **complète**, dans Browther (`SKStoreProductViewController`).
///
/// Ce que ça change pour la personne : taper une pub pour une app iOS ne la
/// SORT plus de Browther. La fiche monte en modal — captures d'écran,
/// description, note, bouton Obtenir — elle installe ou elle referme, et elle
/// est toujours sur son onglet.
///
/// ⛔ **`SKOverlay` a été essayé puis RETIRÉ le 2026-09-09** (Karim, après
/// recette sur iPhone des deux présentations côte à côte : *« je préfère cette
/// nouvelle version »*). La barre compacte en bas de l'écran fonctionnait, mais
/// c'est l'API d'une recommandation **non sollicitée** : elle ne répond pas à la
/// question que pose quelqu'un qui vient de **taper une pub** — « c'est quoi ? ».
/// Ne pas la remettre « pour voir ». Même choix dans Fajrunaa, Darsunaa et
/// Tranquileaty (`fajrunaa/modules/expo-store-page/`, la référence recopiée ici).
///
/// ⛔ **Toujours un confort, jamais le chemin.** Chaque cas d'indisponibilité
/// (destination Play, identifiant non numérique, aucun contrôleur, fiche qui ne
/// charge pas ou pas à temps) ouvre `fallbackURL` : le tap aboutit toujours
/// quelque part. Le repli vit ICI et pas chez l'appelant — un seul endroit à
/// lire pour vérifier qu'aucun chemin ne se termine dans le vide.
///
/// Attribution : les jetons Apple `ct`/`pt` passent en paramètres de chargement,
/// exactement comme sur l'URL App Store qu'on remplace — rien n'est perdu.
///
/// ⚠️ Ce type ne compte PAS le click : `BrowtherAdsClient.trackClick(id:)` s'en
/// charge avant, comme pour une ouverture normale.
public enum BrowtherStorePage {

  /// Charge puis présente la fiche de `store` ; si elle ne charge pas, ouvre
  /// `fallbackURL` — la destination résolue par la régie, qui mène à l'App Store
  /// natif et sait au moins afficher un message. Appelable depuis n'importe quel
  /// thread.
  public static func present(_ store: BrowtherAdStoreTarget, fallbackURL: URL) {
    Task { @MainActor in
      presentOnMain(store, fallbackURL: fallbackURL)
    }
  }

  /// Fiche en cours. Double rôle :
  /// - `SKStoreProductViewController.delegate` est `weak` : sans cette
  ///   référence forte, le délégué serait libéré et « Annuler » ne refermerait
  ///   rien ;
  /// - garde anti double-tap pendant le chargement (cf. `presentOnMain`).
  @MainActor private static var current: ProductPage?

  @MainActor
  private static func presentOnMain(_ store: BrowtherAdStoreTarget, fallbackURL: URL) {
    // Rien n'est visible pendant la ~1 s de chargement : un 2e tap y est
    // probable. Il ne doit pas remplacer `current` — le délégué de la première
    // fiche serait libéré, et son « Annuler » ne refermerait plus rien. Le click
    // de ce 2e tap, lui, est déjà dédoublonné par le client.
    if current?.isLoading == true {
      return
    }

    // ⚠️ `SKStoreProductParameterITunesItemIdentifier` attend un NOMBRE, pas une
    // chaîne : lui passer `store.id` tel quel ne lève rien et ne charge jamais
    // rien — un tap mort et silencieux.
    guard store.kind == .appStore,
      let itemIdentifier = Int(store.id),
      let presenter = topViewController()
    else {
      UIApplication.shared.open(fallbackURL)
      return
    }

    var parameters: [String: Any] = [
      SKStoreProductParameterITunesItemIdentifier: NSNumber(value: itemIdentifier)
    ]
    // Mêmes jetons que l'URL App Store construite par la régie : `ct` =
    // l'emplacement, `pt` = le compte développeur. Sans eux, remplacer la sortie
    // vers l'App Store par la fiche perdrait l'attribution — le seul signal qui
    // survit à l'App Store sur iOS.
    if !store.campaignToken.isEmpty {
      parameters[SKStoreProductParameterCampaignToken] = store.campaignToken
    }
    if !store.providerToken.isEmpty {
      parameters[SKStoreProductParameterProviderToken] = store.providerToken
    }

    let page = ProductPage(fallbackURL: fallbackURL)
    current = page
    page.load(parameters, presentingFrom: presenter)
  }

  /// Fiche refermée (« Annuler ») ou jamais affichée : on libère le délégué.
  @MainActor
  fileprivate static func release(_ page: ProductPage) {
    if current === page {
      current = nil
    }
  }

  /// Le contrôleur qui présente la fiche : la racine de la fenêtre clé, puis la
  /// chaîne des modales déjà ouvertes — sinon la fiche essaierait de se poser
  /// sur un contrôleur qui en présente déjà un autre, et ne s'afficherait pas.
  @MainActor
  private static func topViewController() -> UIViewController? {
    var top = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }?
      .windows
      .first { $0.isKeyWindow }?
      .rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}

/// Une fiche : son chargement, sa présentation, sa fermeture.
///
/// 🔴 **On CHARGE avant de présenter.** Présenter tout de suite afficherait une
/// roue puis, sur un identifiant inconnu, une page vide sans issue — un tap qui
/// ne mène nulle part, et personne ne le saurait. Le prix : ~1 s sans rien à
/// l'écran, d'où le chien de garde.
///
/// `settle` garde l'unicité : le chien de garde et la fin du chargement peuvent
/// arriver tous les deux, et une fiche qui charge APRÈS le repli ne doit pas
/// surgir au retour dans Browther alors qu'on a déjà ouvert l'App Store.
///
/// Tout se passe sur le thread principal — d'où les `MainActor.assumeIsolated`.
private final class ProductPage: NSObject, SKStoreProductViewControllerDelegate {
  /// Au-delà, on ouvre l'App Store sans attendre la fiche. Un chargement normal
  /// se règle en ~1 s ; on ne veut pas doubler une fiche qui arrive, mais pas
  /// non plus laisser un tap sans réponse visible sur un réseau qui traîne.
  private static let loadTimeout: TimeInterval = 5

  private let controller = SKStoreProductViewController()
  private let fallbackURL: URL
  private var settled = false

  /// true entre le tap et la fin du chargement (fiche affichée ou repli).
  private(set) var isLoading = false

  init(fallbackURL: URL) {
    self.fallbackURL = fallbackURL
    super.init()
    controller.delegate = self
  }

  func load(_ parameters: [String: Any], presentingFrom presenter: UIViewController) {
    isLoading = true
    controller.loadProduct(withParameters: parameters) { [weak self, weak presenter] loaded, _ in
      DispatchQueue.main.async {
        self?.settle(loaded: loaded, presenter: presenter)
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.loadTimeout) { [weak self] in
      self?.settle(loaded: false, presenter: nil)
    }
  }

  private func settle(loaded: Bool, presenter: UIViewController?) {
    guard !settled else { return }
    settled = true
    isLoading = false
    MainActor.assumeIsolated {
      // Fiche inconnue, indisponible dans la région, réseau coupé ou trop lent,
      // ou onglet refermé entre-temps : rien ne s'affichera. L'App Store, lui,
      // sait au moins afficher un message.
      guard loaded, let presenter else {
        BrowtherStorePage.release(self)
        UIApplication.shared.open(fallbackURL)
        return
      }
      presenter.present(controller, animated: true)
    }
  }

  /// « Annuler ». Sans ce délégué, `SKStoreProductViewController` reste à
  /// l'écran : le bouton ne referme rien tout seul.
  func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
    MainActor.assumeIsolated {
      viewController.dismiss(animated: true)
      BrowtherStorePage.release(self)
    }
  }
}
