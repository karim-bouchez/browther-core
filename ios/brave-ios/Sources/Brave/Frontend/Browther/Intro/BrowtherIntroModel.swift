// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Basarunaa
import BrowtherAnalytics
import Foundation
import Onboarding
import Preferences
import Sawtunaa
import SwiftUI
import UIKit

/// Les écrans de l'introduction Browther, dans l'ordre du parcours.
///
/// ⚠️ `rawValue` part à l'analytique : c'est une clé de série, jamais un texte
/// affiché. La renommer casse l'entonnoir du dashboard.
enum BrowtherIntroStep: String, CaseIterable, Identifiable {
  case welcome
  case ads
  case blur
  case music
  case defaultBrowser = "default"
  case channels

  var id: String { rawValue }
}

/// Les deux fonctionnalités que l'introduction présente et propose d'activer.
enum BrowtherIntroFeature: String {
  case basarunaa
  case sawtunaa
}

/// Qui reste flouté. Les valeurs sont celles de `Preferences.Basarunaa.mode`,
/// pour que l'écran écrive directement le réglage du moteur.
enum BrowtherBlurTarget: String, CaseIterable, Identifiable {
  case women = "blur-female"
  case men = "blur-male"
  case both = "blur-all"

  var id: String { rawValue }
}

/// L'état du parcours. Une seule source de vérité pour les six écrans : c'est
/// elle qui décide ce que fait « Activer » selon l'accès anticipé, qui écrit les
/// préférences, et qui émet l'analytique.
@MainActor
final class BrowtherIntroModel: ObservableObject {

  /// Les étapes réellement présentées. `defaultBrowser` saute si Browther est
  /// déjà le navigateur par défaut — inutile de demander ce qui est fait.
  let steps: [BrowtherIntroStep]

  /// Reprend l'interrupteur unique des panels et du badge de la barre d'outils.
  /// Faux = les fonctionnalités s'activent pour de bon depuis l'introduction.
  let isEarlyAccess: Bool

  @Published private(set) var index: Int = 0
  @Published var adsDemoOn = false
  @Published var musicDemoOn = false
  @Published var blurTarget: BrowtherBlurTarget = .both
  /// Non nul quand la feuille « ça arrive très bientôt » est ouverte.
  @Published var soonFeature: BrowtherIntroFeature?
  /// Fonctionnalités allumées depuis l'introduction (hors accès anticipé).
  @Published private(set) var activated: Set<String> = []

  private let onFinish: () -> Void
  private let onOpenURL: (URL) -> Void
  private let onSetDefaultBrowser: () -> Void

  var step: BrowtherIntroStep { steps[index] }
  var isFirstStep: Bool { index == 0 }
  var progress: (current: Int, total: Int) { (index + 1, steps.count) }

  init(
    isDefaultBrowser: Bool,
    isEarlyAccess: Bool = BrowtherEarlyAccess.isActive,
    onOpenURL: @escaping (URL) -> Void,
    onSetDefaultBrowser: @escaping () -> Void,
    onFinish: @escaping () -> Void
  ) {
    var steps: [BrowtherIntroStep] = [.welcome, .ads, .blur, .music]
    if !isDefaultBrowser {
      steps.append(.defaultBrowser)
    }
    steps.append(.channels)
    self.steps = steps
    self.isEarlyAccess = isEarlyAccess
    self.onOpenURL = onOpenURL
    self.onSetDefaultBrowser = onSetDefaultBrowser
    self.onFinish = onFinish
    // Le floutage part sur « les deux » : au repos, personne n'apparaît en
    // clair dans l'aperçu, et la personne rétrécit le flou si elle le décide.
    self.blurTarget = BrowtherBlurTarget(rawValue: Preferences.Basarunaa.mode.value) ?? .both
    trackStep()
  }

  // MARK: - Navigation

  func advance() {
    guard index + 1 < steps.count else {
      finish()
      return
    }
    index += 1
    trackStep()
  }

  func back() {
    guard index > 0 else { return }
    index -= 1
    trackStep()
  }

  func finish() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    onFinish()
  }

  private func trackStep() {
    track(
      "onboarding_step_viewed",
      ["step": step.rawValue, "index": index, "early_access": isEarlyAccess]
    )
  }

  // MARK: - Démonstrations

  /// L'interrupteur de démonstration (écrans Pubs et Musique). Il ne règle
  /// rien : il montre la page avec et sans Browther.
  func toggleDemo(for step: BrowtherIntroStep) {
    switch step {
    case .ads: adsDemoOn.toggle()
    case .music: musicDemoOn.toggle()
    default: return
    }
    let on = step == .ads ? adsDemoOn : musicDemoOn
    track("onboarding_demo_toggled", ["step": step.rawValue, "on": on])
  }

  func choose(_ target: BrowtherBlurTarget) {
    guard target != blurTarget else { return }
    blurTarget = target
    // Écrit tout de suite, même si le floutage est encore désactivé : c'est ce
    // que promet la feuille « ton choix est enregistré ».
    Preferences.Basarunaa.mode.value = target.rawValue
    track("onboarding_blur_target_chosen", ["value": target.rawValue])
  }

  // MARK: - Activation

  /// Pendant l'accès anticipé, « Activer » explique que la fonctionnalité
  /// arrive ; à la sortie, elle s'allume vraiment. Le même bouton, deux
  /// réponses — c'est le seul écart entre les deux états de l'introduction.
  func activate(_ feature: BrowtherIntroFeature) {
    track(
      "onboarding_activate_tapped",
      ["feature": feature.rawValue, "available": !isEarlyAccess]
    )
    guard !isEarlyAccess else {
      // Le geste a un effet : la feuille arrive, et on le sent — sinon
      // « Activer » donne l'impression de n'avoir rien fait.
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      soonFeature = feature
      return
    }
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    switch feature {
    case .basarunaa:
      Preferences.Basarunaa.enabled.value = true
      Preferences.Basarunaa.mode.value = blurTarget.rawValue
    case .sawtunaa:
      Preferences.Sawtunaa.enabled.value = true
      musicDemoOn = true
    }
    activated.insert(feature.rawValue)
    track(
      "feature_toggled",
      ["feature": feature.rawValue, "enabled": true, "source": "onboarding"]
    )
  }

  func later(_ what: String) {
    track("onboarding_later_tapped", ["feature": what])
    advance()
  }

  func dismissSoonSheet() {
    soonFeature = nil
  }

  // MARK: - Navigateur par défaut

  func setAsDefaultBrowser() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    track("default_browser_set", ["source": "onboarding"])
    onSetDefaultBrowser()
  }

  // MARK: - Canaux dev&din

  func openChannel(_ channel: BrowtherIntroChannel) {
    track(channel.event, ["source": "onboarding"])
    onOpenURL(channel.url)
  }

  // MARK: - Analytique

  private func track(_ event: String, _ properties: [String: Any]) {
    BrowtherAnalyticsService.shared.track(event: event, properties: properties)
  }
}

/// Les deux canaux de diffusion dev&din (cf. `devndin/docs/BROADCASTS.md` §0).
/// Mêmes URL que le bandeau du Nouvel Onglet et les panels —
/// `grep 0029Vb8ydkv5vKABH78PVX32`.
enum BrowtherIntroChannel: CaseIterable {
  case whatsApp
  case telegram

  var url: URL {
    switch self {
    case .whatsApp:
      return URL(string: "https://whatsapp.com/channel/0029Vb8ydkv5vKABH78PVX32")!
    case .telegram:
      return URL(string: "https://t.me/devndin_nouveautes")!
    }
  }

  var event: String {
    switch self {
    case .whatsApp: return "marketing_whatsapp_channel_clicked"
    case .telegram: return "marketing_telegram_channel_clicked"
    }
  }
}
