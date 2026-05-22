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
    /// Default `true` to match desktop + Browther "navigateur pré-configuré" UX.
    ///
    /// Note historique : avant 2026-05-22 le piège `UserScriptManager.
    /// dynamicScripts` (dict figé au boot, valeur nil = clé supprimée)
    /// bloquait toute activation après un boot avec `false`. Fixé en sortant
    /// `.sawtunaa` de `alwaysEnabledScripts` et en observant le pref dans
    /// `BrowserViewController.preferencesDidChange`.
    public static let enabled = Option<Bool>(
      key: "sawtunaa.enabled",
      default: true
    )
  }
}
