// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences

extension Preferences {
  /// Basarunaa (image-blur) iOS — pipeline ML natif CoreML.
  /// L'intensité du flou est hardcodée (pas dans le POC, pas tunable en prod).
  final public class Basarunaa {
    public static let enabled = Option<Bool>(
      key: "basarunaa.enabled",
      default: false
    )
    /// Mode de floutage : "off", "blur", "strict".
    public static let mode = Option<String>(
      key: "basarunaa.mode",
      default: "blur"
    )
    /// DEBUG-only — seuil de confiance détection visage (0.0 → 1.0).
    /// En release, le seuil est lu via `Self.faceThreshold.value` mais l'UI
    /// qui le règle est gated `#if DEBUG`.
    public static let faceThreshold = Option<Double>(
      key: "basarunaa.face-threshold",
      default: 0.5
    )
    /// DEBUG-only — seuil de confiance détection corps (0.0 → 1.0).
    public static let bodyThreshold = Option<Double>(
      key: "basarunaa.body-threshold",
      default: 0.4
    )
  }
}
