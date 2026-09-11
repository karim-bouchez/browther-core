// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import StoreKit
import UIKit

// MARK: - Browther : sollicitations (cf. BrowtherPromptCoordinator)

extension BrowserViewController {

  /// L'écran est-il libre pour une fiche spontanée ? Rien de présenté, pas de
  /// saisie d'adresse en cours, toujours sur un Nouvel Onglet normal, app au
  /// premier plan. Relu à l'échéance, pas à la décision (§2.7).
  ///
  /// ⚠️ Pas `isOnboardingOrFullScreenCalloutPresented` : Brave le passe à
  /// `true` en présentant le callout « barre du bas » et ne le remet jamais à
  /// `false` — il bloquerait tout jusqu'à la mort du process. Un callout à
  /// l'écran se voit déjà dans `presentedViewController`.
  func browtherIsScreenFreeForSolicitation() -> Bool {
    presentedViewController == nil
      && !topToolbar.inOverlayMode
      && !isTabTrayActive
      && !privateBrowsingManager.isPrivateBrowsing
      && activeNewTabPageViewController != nil
      && topToolbar.currentURL == nil
      && view.window != nil
      && UIApplication.shared.applicationState == .active
  }

  /// Fiche d'avis. `spontaneous` arme le verrou à l'affichage réel (dans la
  /// fiche elle-même) ; `permanent` n'arme rien — c'est la personne qui vient.
  func browtherPresentFeedback(source: BrowtherSurfaces.FeedbackSource) {
    present(BrowtherFeedbackHostingController(source: source), animated: true)
  }

  /// Demande de note (dialogue de l'OS, §3.4). Aucune UI à nous, et l'OS peut
  /// décider de ne rien afficher (plafond de 3 par an) : la tentative est
  /// consommée quand même, marquée AVANT — si l'app meurt pendant le dialogue,
  /// mieux vaut une demande perdue qu'une re-sollicitation immédiate. Le chemin
  /// manuel reste Réglages › Noter Browther.
  func browtherRequestRating() {
    guard let scene = view.window?.windowScene else { return }
    BrowtherSurfaces.markSolicitationShown()
    BrowtherSurfaces.noteRatingRequested(source: .spontaneous)
    AppStore.requestReview(in: scene)
  }
}
