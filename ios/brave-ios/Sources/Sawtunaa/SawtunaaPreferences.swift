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

  /// Basarunaa (image-blur) iOS — front-only pour l'instant.
  /// Le back CoreML natif viendra plus tard (WebKit imposé Apple, donc on ne peut
  /// pas réutiliser l'extension WebGPU macOS). Les prefs sont déjà en place pour
  /// que l'UI soit prête le jour où le pipeline ML est branché.
  final public class Basarunaa {
    public static let enabled = Option<Bool>(
      key: "basarunaa.enabled",
      default: false
    )
    /// Mode de floutage : "off", "blur", "strict" (matching le panel macOS).
    public static let mode = Option<String>(
      key: "basarunaa.mode",
      default: "blur"
    )
    /// Seuil de confiance détection visage (0.0 → 1.0).
    public static let faceThreshold = Option<Double>(
      key: "basarunaa.face-threshold",
      default: 0.5
    )
    /// Seuil de confiance détection corps (0.0 → 1.0).
    public static let bodyThreshold = Option<Double>(
      key: "basarunaa.body-threshold",
      default: 0.4
    )
    /// Intensité du flou (0.0 → 1.0).
    public static let blurStrength = Option<Double>(
      key: "basarunaa.blur-strength",
      default: 0.8
    )
  }
}
