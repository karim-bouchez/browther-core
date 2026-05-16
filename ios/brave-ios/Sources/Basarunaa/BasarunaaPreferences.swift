// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences

extension Preferences {
  /// Basarunaa (image-blur) iOS — pipeline ML natif CoreML.
  ///
  /// Aligned with the macOS POC popup
  /// (`private/extensions/basarunaa/CLAUDE.md` § "Configuration utilisateur" /
  ///  `components/basarunaa/resources/panel/basarunaa_panel.html`).
  ///
  /// Storage keys mirror the desktop pref names so the same user-facing
  /// defaults document covers both platforms.
  final public class Basarunaa {
    /// Master ON/OFF — when false, the JS script handler keeps the default
    /// CSS blur on but skips ML analysis entirely.
    public static let enabled = Option<Bool>(
      key: "basarunaa.enabled",
      default: false
    )

    /// Which persons should stay blurred when ML runs.
    /// Valid values: `"blur-female"` (POC default), `"blur-male"`, `"blur-all"`.
    /// The historical iOS values `"blur"` / `"strict"` are migrated on read
    /// (see `effectiveMode`) so existing testers don't end up in a broken state.
    public static let mode = Option<String>(
      key: "basarunaa.mode",
      default: "blur-female"
    )

    /// Detection thresholds — exposed in the panel under "Détection".
    /// Defaults match the POC popup sliders.
    public static let confBody = Option<Double>(
      key: "basarunaa.conf-body",
      default: 0.25
    )
    public static let confFace = Option<Double>(
      key: "basarunaa.conf-face",
      default: 0.30
    )
    /// Minimum softmax probability required to trust a gender classification.
    /// Below this threshold the fused gender is replaced with `nil` so the
    /// `blur-female` mode falls back to the safer "keep" default.
    public static let genderCertainty = Option<Double>(
      key: "basarunaa.gender-certainty",
      default: 0.70
    )

    /// Debug overlay mode — visible in the panel's Debug section.
    /// Valid values: `"none"`, `"boxes"`, `"debug"`.
    public static let debugMode = Option<String>(
      key: "basarunaa.debug-mode",
      default: "none"
    )
    /// When true, the analyzed image + decision are persisted under
    /// `Documents/Basarunaa-capture/` (visible via Files.app when file
    /// sharing is enabled on the bundle).
    public static let captureMode = Option<Bool>(
      key: "basarunaa.capture-mode",
      default: false
    )

    /// Returns one of `"blur-female"` / `"blur-male"` / `"blur-all"`, migrating
    /// legacy iOS values (`"blur"` → `"blur-female"`, `"strict"` → `"blur-all"`,
    /// `"off"` → `"blur-female"` + enabled=false equivalent).
    public static var effectiveMode: String {
      switch mode.value {
      case "blur-female", "blur-male", "blur-all":
        return mode.value
      case "strict":
        return "blur-all"
      default:
        return "blur-female"
      }
    }
  }
}
