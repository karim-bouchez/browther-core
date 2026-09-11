// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import UIKit

/// LE coordinateur des sollicitations de Browther iOS — un seul endroit, avec
/// l'ordre écrit noir sur blanc (`docs/SURFACES-COMMUNES.md` §4, dernière case).
///
/// ## Ce qui passe par ici, et ce qui n'y passe pas
///
/// - **Fiches qui s'ouvrent d'elles-mêmes, sous le verrou de 3 jours** : l'avis
///   écrit, puis la demande de note (dialogue de l'OS). La note héritée de Brave
///   (`AppReviewManager`, au lancement, hors verrou) est coupée à la source ;
///   les deux callouts Brave encore actifs (barre du bas, navigateur par
///   défaut) respectent et arment le même verrou (`BVC+Callout`).
/// - **« Ce qui a changé »** : un encart du Nouvel Onglet
///   (`BrowtherBetaNoticeSectionProvider`). Il ne consomme pas le verrou mais
///   garde la session : aucune fiche ne s'ouvre le jour où il apparaît.
/// - **Hors verrou** (§2.1 : dans le flux, rien n'interrompt) : le bandeau
///   « accès anticipé » et l'onboarding — dont la fin arme le verrou, puisque
///   sa dernière étape propose de suivre les canaux.
///
/// ## Quand
///
/// Le seuil ARME, il n'OUVRE pas (§2.3) : la décision se prend au début de la
/// session (retour au premier plan) et ne se relit pas en cours de route —
/// franchir le 3ᵉ jour de navigation au milieu d'une recherche n'ouvre rien.
/// La fiche vient ensuite sur un Nouvel Onglet, 2,5 s après son arrivée ; si
/// l'écran n'est pas libre à l'échéance, on renonce pour la session (§2.7) et
/// elle reviendra. Jamais sur une page web : on n'interrompt pas une lecture.
final class BrowtherPromptCoordinator {
  static let shared = BrowtherPromptCoordinator()

  /// Délai après l'appel de `showNTPOnboarding` (lui-même 0,5 s après
  /// l'apparition du Nouvel Onglet) : 2,5 s au total. Le temps de voir où l'on
  /// est, pas assez pour avoir commencé à taper — et si l'on a commencé, la
  /// barre d'adresse en mode saisie fait renoncer.
  static let presentationDelay: TimeInterval = 2.0

  private var sessionPending: BrowtherSurfacesRules.Solicitation?
  private var attemptedThisSession = false
  private var foregroundObserver: NSObjectProtocol?

  private init() {
    startSession()
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willEnterForegroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.startSession()
    }
  }

  /// Début de session : c'est ici, et seulement ici, que les compteurs sont lus.
  func startSession(now: Date = Date()) {
    sessionPending = BrowtherSurfaces.pendingSolicitation(now: now)
    attemptedThisSession = false
  }

  /// Un Nouvel Onglet vient d'apparaître (`BVC.showNTPOnboarding`).
  func newTabPageDidAppear(in browserViewController: BrowserViewController) {
    guard let pending = sessionPending, !attemptedThisSession else { return }
    attemptedThisSession = true
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.presentationDelay) {
      [weak browserViewController] in
      guard let bvc = browserViewController else { return }
      // L'écran doit être libre À L'ÉCHÉANCE, sinon on renonce pour la session.
      guard bvc.browtherIsScreenFreeForSolicitation() else { return }
      // Et la décision doit tenir encore : un callout Brave, une autre fenêtre
      // (iPad) ou l'encart des nouveautés ont pu passer entre-temps.
      guard BrowtherSurfaces.pendingSolicitation() == pending else { return }
      switch pending {
      case .feedback:
        bvc.browtherPresentFeedback(source: .spontaneous)
      case .rating:
        bvc.browtherRequestRating()
      }
    }
  }
}
