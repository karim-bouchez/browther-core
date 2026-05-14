// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import OSLog
import Web

extension BrowserViewController: BasarunaaScriptHandlerDelegate {
  private static let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa.BVC")

  func basarunaaDidActivate(tab: (any TabState)?) {
    Self.log.info("activated for tab")
  }

  func basarunaaDidApplyBlur(tab: (any TabState)?, imageCount: Int) {
    Self.log.info("applied blur on \(imageCount, privacy: .public) initial images")
  }
}
