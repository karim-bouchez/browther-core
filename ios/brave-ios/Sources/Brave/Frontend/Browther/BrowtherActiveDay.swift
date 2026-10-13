// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Basarunaa
import BrowtherAnalytics
import BrowtherReferral
import Foundation
import Preferences
import Sawtunaa
import UIKit

/// `app_active` — « actif aujourd'hui » : au plus un event par jour calendaire
/// LOCAL et par installation, avec l'ÉTAT des réglages (pas les gestes, que
/// `feature_toggled` porte déjà). Contrat commun aux 4 plateformes :
/// `private/docs/ANALYTICS.md`.
///
/// Déclencheurs : le lancement, et chaque retour de l'app au premier plan — une
/// app gardée en mémoire plusieurs jours compte chaque jour où elle est
/// réellement rouverte. ⛔ Pas de minuteur : une app ouverte mais inutilisée ne
/// doit pas compter.
///
/// `app_launched` reste à part (un par démarrage à froid).
@MainActor
public final class BrowtherActiveDay {
  public static let shared = BrowtherActiveDay()

  private var observer: NSObjectProtocol?

  private init() {}

  /// À appeler une fois au lancement, après `BrowtherAnalyticsService.initialize()`.
  /// Idempotent.
  public func start() {
    guard observer == nil else { return }
    observer = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { _ in
      MainActor.assumeIsolated { BrowtherActiveDay.shared.reportIfNeeded() }
    }
    // Le lancement lui-même — ⚠️ sauf réveillée en arrière-plan par le système
    // (notification, tâche de fond) : personne n'a ouvert l'app, et si
    // quelqu'un l'ouvre ensuite, `didBecomeActive` s'en charge.
    if UIApplication.shared.applicationState != .background {
      reportIfNeeded()
    }
  }

  private func reportIfNeeded(now: Date = Date()) {
    let today = ReferralDate.localDayKey(now)
    guard Preferences.BrowtherAnalytics.lastActiveDay.value != today else { return }

    var properties: [String: Any] = [
      "basarunaa_enabled": Self.durableState(
        enabled: Preferences.Basarunaa.enabled.value,
        temporaryRevertAt: Preferences.Basarunaa.temporaryRevertAt.value,
        temporaryRevertTo: Preferences.Basarunaa.temporaryRevertTo.value
      ),
      "sawtunaa_enabled": Self.durableState(
        enabled: Preferences.Sawtunaa.enabled.value,
        temporaryRevertAt: Preferences.Sawtunaa.temporaryRevertAt.value,
        temporaryRevertTo: Preferences.Sawtunaa.temporaryRevertTo.value
      ),
      // Même format que sur `app_launched` (`fr_FR`).
      "locale": Locale.current.identifier,
    ]
    // ⛔ Omise quand on ne sait pas — jamais `false` par défaut.
    if let isDefault = Self.defaultBrowserState(
      apiResult: Preferences.General.isDefaultAPILastResult.value,
      apiResultDate: Preferences.General.isDefaultAPILastResultDate.value,
      lastExternalLinkDate: Preferences.General.lastHTTPURLOpenedDate.value,
      now: now
    ) {
      properties["default_browser"] = isDefault
    }

    // Le jour n'est noté que si l'event est réellement parti : analytics
    // coupée, il reste à compter si elle est rallumée dans la journée.
    guard
      BrowtherAnalyticsService.shared.trackReportingDelivery(
        event: "app_active",
        properties: properties
      )
    else { return }
    Preferences.BrowtherAnalytics.lastActiveDay.value = today
  }

  // MARK: - Lecture de l'état (pur)

  /// Le réglage GLOBAL d'une fonctionnalité, pas sa bascule « Seulement 5 min ».
  /// Pendant le compte à rebours, la préférence porte l'état TEMPORAIRE
  /// (`FeatureTemporarySwitch` ne la remet qu'à l'échéance) : le réglage durable
  /// est alors celui qui sera rétabli. Vaut aussi pour une échéance dépassée
  /// app fermée, pas encore soldée à cet instant du lancement.
  static func durableState(
    enabled: Bool,
    temporaryRevertAt: Double,
    temporaryRevertTo: Bool
  ) -> Bool {
    temporaryRevertAt > 0 ? temporaryRevertTo : enabled
  }

  /// Durée pendant laquelle une réponse sur le navigateur par défaut reste
  /// crue — celle du cache de `DefaultBrowserHelper` (« 14-day validity »).
  static let defaultBrowserEvidenceValidity: TimeInterval = 14 * 24 * 3600

  /// Browther est-il le navigateur par défaut ? `nil` = on ne sait pas.
  ///
  /// ⚠️ On ne rappelle PAS `UIApplication.isDefault(.webBrowser)` ici : Apple
  /// rationne cette API (« aggressively rate-limit », quelques réponses par
  /// an), et chaque appel de plus en retirerait une à la validation du filleul
  /// (`BrowtherReferralController.checkDefaultBrowserIfUseful`) et au
  /// calendrier de `DefaultBrowserHelper`. On relit donc ce que l'app sait
  /// déjà, la plus récente des deux l'emporte :
  /// - la dernière réponse de l'API, mise en cache par `DefaultBrowserHelper` ;
  /// - un lien `http(s)` reçu d'une autre app — iOS ne l'envoie qu'au
  ///   navigateur par défaut (même preuve que le parrainage, § 9) : un oui,
  ///   jamais un non.
  /// Au-delà de 14 jours, plus rien n'est cru : la propriété est omise.
  static func defaultBrowserState(
    apiResult: Bool?,
    apiResultDate: Date?,
    lastExternalLinkDate: Date?,
    now: Date
  ) -> Bool? {
    let oldest = now.addingTimeInterval(-defaultBrowserEvidenceValidity)
    let linkDate = lastExternalLinkDate.flatMap { $0 >= oldest ? $0 : nil }
    var api: (result: Bool, date: Date)?
    if let apiResult, let apiResultDate, apiResultDate >= oldest {
      api = (apiResult, apiResultDate)
    }
    switch (api, linkDate) {
    case (let api?, let linkDate?):
      return linkDate > api.date ? true : api.result
    case (let api?, nil):
      return api.result
    case (nil, .some):
      return true
    case (nil, nil):
      return nil
    }
  }
}
