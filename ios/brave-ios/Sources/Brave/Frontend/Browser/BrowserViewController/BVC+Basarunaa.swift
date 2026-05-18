// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import OSLog
import UIKit
import Web

/// State saved before entering fake fullscreen so we can restore on exit.
/// Keyed off the `BrowserViewController` instance via `ObjectAssociation`.
private struct BasarunaaFullscreenState {
  let savedBackgroundColor: UIColor?
}
private var basarunaaFullscreenStateKey: UInt8 = 0

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
  }

  func basarunaaDidApplyBlur(tab: (any TabState)?, imageCount: Int) {
    Self.log.info("applied blur on \(imageCount, privacy: .public) initial images")
  }

  func basarunaaDidEnterFakeFullscreen(tab: (any TabState)?) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      // Stash le fond actuel de la BVC view — la WKWebView ne s'étend pas
      // jusqu'aux bords device pendant le fake fullscreen (le canvas DOM en
      // `100vw/100vh` ne couvre que la WKWebView viewport), donc on voit le
      // fond BVC autour. On le passe en noir le temps du fake fullscreen pour
      // que ça se confonde avec le letterbox `object-fit:contain` du canvas.
      self.basarunaaFullscreenState = BasarunaaFullscreenState(
        savedBackgroundColor: self.view.backgroundColor
      )
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
      let restoredBackgroundColor = self.basarunaaFullscreenState?.savedBackgroundColor
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
