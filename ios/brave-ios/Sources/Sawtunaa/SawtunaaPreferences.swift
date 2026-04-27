// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences

extension Preferences {
  final public class Sawtunaa {
    /// Whether Sawtunaa (music/noise removal) is enabled.
    public static let enabled = Option<Bool>(
      key: "sawtunaa.enabled",
      default: false
    )
  }
}
