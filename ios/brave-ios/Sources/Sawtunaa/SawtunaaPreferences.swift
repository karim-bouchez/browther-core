// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences

extension Preferences {
  final public class Sawtunaa {
    /// Whether Sawtunaa (music/noise removal) is enabled.
    ///
    /// Default `true` to match desktop + Browther "navigateur pré-configuré"
    /// UX. See `BasarunaaPreferences.enabled` for why leaving `false`
    /// breaks injection until app restart (brave-iOS `UserScriptManager.
    /// dynamicScripts` is initialised once at launch, a nil value silently
    /// removes the entry so URL bar toggles can't re-attach the script).
    public static let enabled = Option<Bool>(
      key: "sawtunaa.enabled",
      default: true
    )
  }
}
