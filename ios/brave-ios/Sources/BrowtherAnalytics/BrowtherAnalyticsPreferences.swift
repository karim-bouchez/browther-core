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
    /// Dernier jour LOCAL (`AAAA-MM-JJ`) où `app_active` a été remis au SDK —
    /// l'event part au plus une fois par jour (cf. `BrowtherActiveDay`).
    /// ⚠️ Écrit seulement après un envoi réel : analytics coupée, le jour
    /// reste à compter.
    public static let lastActiveDay = Option<String?>(
      key: "browther.analytics.last-active-day",
      default: nil
    )

    // MARK: Compteurs d'usage portés par `app_active`

    /// Pages ouvertes depuis l'installation (ou depuis la mise à jour qui a
    /// introduit ce compteur) : une navigation principale aboutie, `http(s)`,
    /// hors pages internes et hors navigation privée. ⛔ Un nombre, jamais une
    /// adresse. Incrémenté par `BrowtherReferralController.notePageLoaded`, à
    /// côté du compte du jour du parrainage.
    public static let pagesTotal = Option<Int>(
      key: "browther.analytics.pages-total",
      default: 0
    )

    /// Totaux tels qu'ils sont partis avec le dernier `app_active` REMIS au
    /// SDK — l'event suivant n'envoie que l'écart, pour qu'une somme d'events
    /// ne compte jamais deux fois le même appareil.
    /// ⚠️ Écrits au même moment que `lastActiveDay`, et seulement là.
    /// `nil` = aucun event parti depuis que ces compteurs existent : l'écart
    /// est alors omis (⛔ pas tout l'historique de l'appareil d'un coup).
    public static let lastSentBlurredTotal = Option<Int?>(
      key: "browther.analytics.last-sent.blurred-total",
      default: nil
    )
    public static let lastSentMusicSecondsTotal = Option<Int?>(
      key: "browther.analytics.last-sent.music-seconds-total",
      default: nil
    )
    public static let lastSentBlockedTotal = Option<Int?>(
      key: "browther.analytics.last-sent.blocked-total",
      default: nil
    )
    public static let lastSentPagesTotal = Option<Int?>(
      key: "browther.analytics.last-sent.pages-total",
      default: nil
    )
  }
}
