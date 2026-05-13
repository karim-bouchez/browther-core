// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences

extension Preferences {
  /// Browther analytics & crash reporting consent toggles.
  /// Equivalent iOS des prefs Desktop `kMetricsReportingEnabled` (Sentry) et `kP3AEnabled` (PostHog).
  /// Defaults opt-out (l'user peut désactiver depuis l'onboarding ou les Settings).
  final public class BrowtherAnalytics {
    /// Crash reports → Sentry. Default: true (opt-out).
    public static let sentryEnabled = Option<Bool>(
      key: "browther.analytics.sentry-enabled",
      default: true
    )
    /// Product analytics → PostHog. Default: true (opt-out).
    public static let posthogEnabled = Option<Bool>(
      key: "browther.analytics.posthog-enabled",
      default: true
    )
    /// UUID v4 anonyme local persistant. Réinstall app = nouveau UUID.
    /// Reset = passer la valeur à nil (le service en regénèrera un au prochain accès).
    public static let distinctId = Option<String?>(
      key: "browther.analytics.distinct-id",
      default: nil
    )
  }
}
