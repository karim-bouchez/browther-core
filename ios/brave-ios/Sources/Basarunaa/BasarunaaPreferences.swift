// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences

extension Preferences {
  /// Basarunaa (image-blur) iOS — pipeline ML natif CoreML.
  /// Le back ML est en cours d'implémentation ; en attendant, l'UI lit déjà ces prefs
  /// (toggle, mode, seuils, intensité du flou).
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
