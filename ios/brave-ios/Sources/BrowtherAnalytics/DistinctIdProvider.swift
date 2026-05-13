// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences

enum DistinctIdProvider {
  /// Renvoie le UUID v4 anonyme stocké en pref. En génère un nouveau si absent.
  static func get() -> String {
    if let existing = Preferences.BrowtherAnalytics.distinctId.value, !existing.isEmpty {
      return existing
    }
    let new = UUID().uuidString.lowercased()
    Preferences.BrowtherAnalytics.distinctId.value = new
    return new
  }
}
