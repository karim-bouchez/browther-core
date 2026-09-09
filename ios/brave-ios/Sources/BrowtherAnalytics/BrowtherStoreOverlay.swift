// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import StoreKit
import UIKit

/// `SKOverlay` — la feuille App Store qui monte par le bas de l'écran.
///
/// Ce que ça change pour la personne : taper une pub pour une app iOS ne la
/// SORT plus de Browther. Une carte apparaît en bas (icône, nom, bouton),
/// l'installation se fait sur place, la carte redescend, et elle est toujours
/// là où elle était. Sans ça elle atterrit dans l'App Store et doit revenir à
/// la main — c'est là qu'on perd les gens.
///
/// ⛔ **Toujours un confort, jamais le chemin.** Chaque cas d'indisponibilité
/// (destination Play, aucune scène au premier plan, fiche qui ne charge pas,
/// aucun callback) ouvre `fallbackURL` : le tap aboutit toujours quelque part.
/// C'est pour ça que le repli vit ICI et pas chez l'appelant — un seul endroit
/// à lire pour vérifier qu'aucun chemin ne se termine dans le vide.
///
/// ⚠️ Ce type ne compte PAS le click : `BrowtherAdsClient.trackClick(id:)` s'en
/// charge avant, comme pour une ouverture normale.
///
/// Implémentation de référence : `fajrunaa/modules/expo-store-overlay/ios/`
/// (ads/docs/INTEGRATION.md § 5 « iOS : installer sans quitter l'app »).
public enum BrowtherStoreOverlay {

  /// true si un tap sur cette destination peut se régler sans quitter Browther.
  /// Play n'a **aucun équivalent public** — seul l'App Store est concerné.
  public static func canPresent(_ store: BrowtherAdStoreTarget) -> Bool {
    store.kind == .appStore && !store.id.isEmpty
  }

  /// Présente la feuille pour `store` ; si **rien** ne s'affiche, ouvre
  /// `fallbackURL` — la destination résolue par la régie, qui mène à l'App Store
  /// natif et sait au moins afficher un message. Appelable depuis n'importe quel
  /// thread.
  public static func present(_ store: BrowtherAdStoreTarget, fallbackURL: URL) {
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        presentOnMain(store, fallbackURL: fallbackURL)
      }
    }
  }

  /// Présentation en cours. `SKOverlay.delegate` est `weak` : sans cette
  /// référence forte, le délégué serait libéré avant le premier callback et rien
  /// ne se résoudrait jamais.
  @MainActor private static var current: Presentation?

  @MainActor
  private static func presentOnMain(_ store: BrowtherAdStoreTarget, fallbackURL: URL) {
    guard canPresent(store), let scene = foregroundWindowScene() else {
      UIApplication.shared.open(fallbackURL)
      return
    }

    let configuration = SKOverlay.AppConfiguration(appIdentifier: store.id, position: .bottom)
    // Mêmes jetons que l'URL App Store construite par la régie : `ct` =
    // l'emplacement, `pt` = le compte développeur. Sans eux, remplacer la sortie
    // vers l'App Store par la feuille perdrait l'attribution — le seul signal
    // qui survit à l'App Store sur iOS.
    if !store.campaignToken.isEmpty {
      configuration.campaignToken = store.campaignToken
    }
    if !store.providerToken.isEmpty {
      configuration.providerToken = store.providerToken
    }

    let overlay = SKOverlay(configuration: configuration)
    let presentation = Presentation(fallbackURL: fallbackURL)
    overlay.delegate = presentation
    current = presentation
    overlay.present(in: scene)
    presentation.startWatchdog()
  }

  /// Appelé une fois par présentation, quel qu'en soit le sort. `presented ==
  /// false` ⇒ rien ne s'est affiché : on ouvre la destination à la place.
  @MainActor
  fileprivate static func didSettle(presented: Bool, fallbackURL: URL) {
    current = nil
    guard !presented else { return }
    UIApplication.shared.open(fallbackURL)
  }

  /// La scène active. `SKOverlay` se présente dans une `UIWindowScene`, pas dans
  /// un contrôleur : on prend celle qui est au premier plan, et on ne devine pas
  /// s'il n'y en a pas (le repli s'en charge).
  @MainActor
  private static func foregroundWindowScene() -> UIWindowScene? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
  }
}

/// Traduit les callbacks de `SKOverlayDelegate` en une seule réponse.
/// `settle` garde l'unicité : le délégué peut très bien recevoir une
/// présentation PUIS un rejet, et le chien de garde peut doubler les deux.
///
/// Tout se passe sur le thread principal (callbacks StoreKit et chien de garde
/// y sont émis) — d'où le `MainActor.assumeIsolated` du repli.
private final class Presentation: NSObject, SKOverlayDelegate {
  private let fallbackURL: URL
  private var settled = false

  init(fallbackURL: URL) {
    self.fallbackURL = fallbackURL
  }

  /// Filet : si aucun callback n'arrive, rien ne se résoudrait et le tap sur la
  /// pub ne ferait **rien** — le pire des cas, parce qu'il est silencieux. Passé
  /// ce délai on considère « pas affichée » et le repli joue. Volontairement
  /// long : une présentation normale se règle en moins d'une seconde, on ne veut
  /// pas doubler une feuille qui arrive.
  func startWatchdog() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
      self?.settle(false)
    }
  }

  private func settle(_ presented: Bool) {
    guard !settled else { return }
    settled = true
    MainActor.assumeIsolated {
      BrowtherStoreOverlay.didSettle(presented: presented, fallbackURL: fallbackURL)
    }
  }

  func storeOverlayDidFinishPresentation(
    _ overlay: SKOverlay,
    transitionContext: SKOverlayTransitionContext
  ) {
    settle(true)
  }

  func storeOverlayDidFailToLoad(_ overlay: SKOverlay, error: Error) {
    // Identifiant inconnu, fiche indisponible dans la région, réseau coupé :
    // rien ne s'est affiché. Le repli ouvre l'App Store à la place.
    settle(false)
  }
}
