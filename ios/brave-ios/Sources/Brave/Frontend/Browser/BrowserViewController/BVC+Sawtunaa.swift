// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Sawtunaa
import Web
import os.log

extension BrowserViewController: SawtunaaScriptHandlerDelegate {

  func sawtunaaDidActivate(tab: (any TabState)?) {
    Logger(subsystem: "com.devndin.browther", category: "Sawtunaa")
      .info("Sawtunaa activated for tab")
  }

  func sawtunaaDidDeactivate(tab: (any TabState)?) {
    Logger(subsystem: "com.devndin.browther", category: "Sawtunaa")
      .info("Sawtunaa deactivated for tab")
  }
}
