// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Basarunaa
import Foundation
import OSLog
import Preferences
import UIKit
import Web

/// State saved before entering fake fullscreen so we can restore on exit.
/// Keyed off the `BrowserViewController` instance via `ObjectAssociation`.
private final class BasarunaaFullscreenState {
  let savedBackgroundColor: UIColor?
  var rotationObserver: NSObjectProtocol?
  var sizePollTimer: Timer?
  var lastObservedSize: CGSize = .zero
  init(savedBackgroundColor: UIColor?) {
    self.savedBackgroundColor = savedBackgroundColor
  }
}
private var basarunaaFullscreenStateKey: UInt8 = 0

/// Observateur unique du passage en arrière-plan, pour vider les compteurs de
/// la collecte. Global plutôt que membre : `BrowserViewController` est étendu
/// ici, on ne peut pas lui ajouter de propriété stockée.
private var basarunaaCollectBackgroundObserver: NSObjectProtocol?

extension BrowserViewController: BasarunaaScriptHandlerDelegate {
  private static let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa.BVC")

  private var basarunaaFullscreenState: BasarunaaFullscreenState? {
    get { objc_getAssociatedObject(self, &basarunaaFullscreenStateKey) as? BasarunaaFullscreenState }
    set {
      objc_setAssociatedObject(self, &basarunaaFullscreenStateKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
  }

  func basarunaaDidActivate(tab: (any TabState)?) {
    Self.log.info("activated for tab")
    // Collecte de corpus : pousser les préférences au collecteur à chaque
    // activation plutôt qu'une seule fois au lancement. C'est idempotent, et
    // ça évite la panne desktop du 2026-08-21 — la configuration demandée UNE
    // fois au démarrage se perdait quand l'autre bout n'écoutait pas encore, et
    // le collecteur restait sur ses défauts (donc éteint) pour toute la
    // session, pendant que l'écran affichait « active ». Une information qui
    // compte ne se transmet pas une seule fois.
    BrowserViewController.syncBasarunaaCollectPrefs()
  }

  /// Pousse les trois préférences de collecte au collecteur. Appelée à
  /// l'activation de Basarunaa sur une page et à chaque changement de pref.
  static func syncBasarunaaCollectPrefs() {
    let enabled = Preferences.Basarunaa.collectEnabled.value
    let device = Preferences.Basarunaa.collectDevice.value
    let videoScenes = Preferences.Basarunaa.collectVideoScenes.value
    Task.detached {
      await Collector.shared.configure(
        enabled: enabled, device: device, videoScenes: videoScenes)
    }
    observeBackgroundForBasarunaaCollect()
  }

  /// Les compteurs de la collecte sont écrits en différé (5 s) — sinon chaque
  /// image provoquerait une écriture disque pour quelques centaines d'octets.
  /// Sur un téléphone, l'app est suspendue plusieurs fois par heure : sans ce
  /// vidage, les dernières secondes de compteurs seraient perdues à chaque
  /// fois, et le total afficherait durablement moins que le corpus réel.
  /// (Les images, elles, sont écrites immédiatement — jamais concernées.)
  private static func observeBackgroundForBasarunaaCollect() {
    guard basarunaaCollectBackgroundObserver == nil else { return }
    basarunaaCollectBackgroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil, queue: nil
    ) { _ in
      Task.detached { await Collector.shared.persistNow() }
    }
  }

  func basarunaaDidApplyBlur(tab: (any TabState)?, imageCount: Int) {
    Self.log.info("applied blur on \(imageCount, privacy: .public) initial images")
  }

  func basarunaaDidEnterFakeFullscreen(tab: (any TabState)?) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      let state = BasarunaaFullscreenState(
        savedBackgroundColor: self.view.backgroundColor
      )
      state.lastObservedSize = self.view.bounds.size
      // Poll on view.bounds size (200ms) — `orientationDidChangeNotification`
      // doesn't fire reliably without `beginGeneratingDeviceOrientationNotifications`,
      // and we can't hook `viewWillTransition(to:with:)` from an extension
      // without patching the BVC original file. Polling is the least invasive
      // way to detect rotation and re-apply `.collapsed` + force WKWebView
      // re-layout so the canvas `100vw/100vh` matches the new geometry.
      state.sizePollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) {
        [weak self] _ in
        Task { @MainActor [weak self] in
          guard let self, let state = self.basarunaaFullscreenState else { return }
          let currentSize = self.view.bounds.size
          if currentSize != state.lastObservedSize {
            state.lastObservedSize = currentSize
            Self.log.info(
              "fake_fs_rotation_detected new=\(NSCoder.string(for: currentSize), privacy: .public)"
            )
            self.toolbarVisibilityViewModel.toolbarState = .collapsed
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
          }
        }
      }
      self.basarunaaFullscreenState = state
      self.toolbarVisibilityViewModel.toolbarState = .collapsed
      UIView.animate(withDuration: 0.2) {
        self.header.alpha = 0
        self.footer.alpha = 0
        self.statusBarOverlay.alpha = 0
        self.view.backgroundColor = .black
      }
    }
  }

  func basarunaaDidExitFakeFullscreen(tab: (any TabState)?) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      let state = self.basarunaaFullscreenState
      state?.sizePollTimer?.invalidate()
      if let observer = state?.rotationObserver {
        NotificationCenter.default.removeObserver(observer)
      }
      let restoredBackgroundColor = state?.savedBackgroundColor
      self.basarunaaFullscreenState = nil
      self.toolbarVisibilityViewModel.toolbarState = .expanded
      UIView.animate(withDuration: 0.2) {
        self.header.alpha = 1
        self.footer.alpha = 1
        self.statusBarOverlay.alpha = 1
        self.view.backgroundColor = restoredBackgroundColor
      }
    }
  }
}
