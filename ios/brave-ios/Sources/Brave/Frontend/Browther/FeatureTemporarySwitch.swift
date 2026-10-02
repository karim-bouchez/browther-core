// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Basarunaa
import BrowtherAnalytics
import Combine
import Foundation
import Preferences
import Sawtunaa
import UIKit

/// « Seulement 5 min » : juste après une bascule de Sawtunaa ou de Basarunaa, le panneau
/// propose de revenir automatiquement à l'état d'avant dans 5 min, dans les
/// deux sens (« Réactiver automatiquement… » après une coupure, « Couper
/// automatiquement… » après un allumage). Maquette validée par Karim le
/// 2026-10-01 — cf. `private/docs/sawtunaa/README.md` § Bascule temporaire.
///
/// Règles :
/// - l'interrupteur montre toujours l'état ACTUEL : le mode temporaire ne
///   touche pas la pref pendant les 5 min, il la remet seulement à la fin ;
/// - revenir plus tôt = rebasculer l'interrupteur du panneau ; toute bascule
///   qui rejoint l'état d'avant, d'où qu'elle vienne (réglages, pause du
///   parrainage…), annule le retour. ⛔ L'icône de la barre d'adresse ouvre le
///   panneau, elle ne revient PAS en arrière (essayé puis retiré le
///   2026-10-01 : « ça coupe, je ne sais pas pourquoi », recette Karim) ;
/// - portée : tout le navigateur ; l'échéance est enregistrée, donc une app
///   fermée pendant le compte à rebours retrouve l'état d'avant au lancement.
///
/// Basarunaa (2026-10-01, demande Karim) : même mécanique, une instance par
/// fonctionnalité — chacune a sa préférence, son échéance, son anneau.
@MainActor
final class FeatureTemporarySwitch: ObservableObject {
  static let sawtunaa = FeatureTemporarySwitch(
    feature: "sawtunaa",
    enabled: Preferences.Sawtunaa.enabled,
    revertAtPref: Preferences.Sawtunaa.temporaryRevertAt,
    revertToPref: Preferences.Sawtunaa.temporaryRevertTo,
    // ⛔ Pas de rallumage pendant la pause du parrainage : elle garde le
    // retrait de la musique éteint (BrowtherReferralController § pause).
    blocksTurningOn: { BrowtherReferralController.shared.isPaused() }
  )
  static let basarunaa = FeatureTemporarySwitch(
    feature: "basarunaa",
    enabled: Preferences.Basarunaa.enabled,
    revertAtPref: Preferences.Basarunaa.temporaryRevertAt,
    revertToPref: Preferences.Basarunaa.temporaryRevertTo,
    blocksTurningOn: { false }
  )
  static let duration: TimeInterval = 300

  private let feature: String
  private let enabled: Preferences.Option<Bool>
  private let revertAtPref: Preferences.Option<Double>
  private let revertToPref: Preferences.Option<Bool>
  private let blocksTurningOn: @MainActor () -> Bool

  /// Échéance du retour automatique ; nil = pas de retour programmé.
  @Published private(set) var revertAt: Date?
  /// État rétabli à l'échéance.
  private(set) var revertTo = false

  private var timer: Timer?
  private var prefSubscription: AnyCancellable?

  var isActive: Bool { revertAt != nil }

  /// Secondes restantes (0 si rien n'est programmé).
  func remaining(at now: Date = .now) -> TimeInterval {
    guard let revertAt else { return 0 }
    return max(0, revertAt.timeIntervalSince(now))
  }

  private init(
    feature: String,
    enabled: Preferences.Option<Bool>,
    revertAtPref: Preferences.Option<Double>,
    revertToPref: Preferences.Option<Bool>,
    blocksTurningOn: @escaping @MainActor () -> Bool
  ) {
    self.feature = feature
    self.enabled = enabled
    self.revertAtPref = revertAtPref
    self.revertToPref = revertToPref
    self.blocksTurningOn = blocksTurningOn
    let at = revertAtPref.value
    if at > 0 {
      revertTo = revertToPref.value
      let date = Date(timeIntervalSince1970: at)
      if date <= .now {
        // L'app était fermée à l'échéance : on rétablit sans attendre.
        finish(reason: "relaunch")
      } else {
        revertAt = date
        schedule()
      }
    }
    // `$value` émet AVANT l'écriture, avec la nouvelle valeur.
    prefSubscription = enabled.$value
      .dropFirst()
      .sink { [weak self] newValue in
        MainActor.assumeIsolated {
          guard let self, self.isActive, newValue == self.revertTo else { return }
          // Quelqu'un est revenu à l'état d'avant : plus rien à rétablir.
          self.clear()
          self.track("feature_temporary_end", ["reason": "toggle"])
        }
      }
  }

  /// Programme le retour à l'état d'AVANT la bascule qui vient d'avoir lieu.
  func start() {
    revertTo = !enabled.value
    revertAt = Date(timeIntervalSinceNow: Self.duration)
    persist()
    schedule()
    track(
      "feature_temporary",
      ["enabled": enabled.value, "minutes": Int(Self.duration / 60)]
    )
  }

  /// « Ne pas réactiver » / « Ne pas couper » : l'état actuel devient durable.
  func keep() {
    guard isActive else { return }
    clear()
    track("feature_temporary_end", ["reason": "keep"])
  }

  private func finish(reason: String) {
    let target = revertTo
    clear()
    if target, blocksTurningOn() {
      track("feature_temporary_end", ["reason": reason, "skipped": "referral_paused"])
      return
    }
    enabled.value = target
    if reason == "timer" {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    track("feature_temporary_end", ["reason": reason])
  }

  private func clear() {
    timer?.invalidate()
    timer = nil
    revertAt = nil
    revertAtPref.value = 0
  }

  private func persist() {
    revertAtPref.value = revertAt?.timeIntervalSince1970 ?? 0
    revertToPref.value = revertTo
  }

  private func schedule() {
    timer?.invalidate()
    guard let revertAt else { return }
    let timer = Timer(fire: revertAt, interval: 0, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.finish(reason: "timer") }
    }
    // `.common` : le retour tombe aussi pendant un défilement.
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func track(_ event: String, _ properties: [String: Any]) {
    var props = properties
    props["feature"] = feature
    BrowtherAnalyticsService.shared.track(event: event, properties: props)
  }
}
