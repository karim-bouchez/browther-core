// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import PostHog
import Preferences
import Sentry
import os.log

/// Service singleton qui initialise Sentry + PostHog au lancement, gaté sur les
/// prefs `BrowtherAnalytics.sentryEnabled` / `posthogEnabled`.
///
/// Contrat d'events partagé avec Desktop (cf. `private/docs/ANALYTICS.md`) :
/// - `app_launched`, `onboarding_completed`, `default_browser_set`,
///   `consent_changed`, `feature_toggled`, `page_viewed`.
///
/// Pas de PII : pas d'email, pas d'IP, pas d'URL visitée, pas de contenu de page.
/// UUID v4 anonyme local (`Preferences.BrowtherAnalytics.distinctId`).
public final class BrowtherAnalyticsService {

  public static let shared = BrowtherAnalyticsService()

  private let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.devndin.browther",
    category: "browther-analytics"
  )

  private var posthog: PostHogSDK?
  private var sentryStarted = false
  private var initialized = false

  private init() {}

  // MARK: - Lifecycle

  /// À appeler une seule fois au lancement (AppDelegate.didFinishLaunching).
  /// Idempotent.
  public func initialize() {
    guard !initialized else { return }
    initialized = true

    // Force la génération/lecture du distinctId au premier lancement.
    _ = DistinctIdProvider.get()

    if Preferences.BrowtherAnalytics.sentryEnabled.value {
      startSentry()
    } else {
      log.info("Sentry désactivé (pref off) — skip init")
    }

    if Preferences.BrowtherAnalytics.posthogEnabled.value {
      startPostHog()
    } else {
      log.info("PostHog désactivé (pref off) — skip init")
    }
  }

  /// Appelé quand le toggle Sentry change (depuis onboarding ou Settings).
  public func setSentryEnabled(_ enabled: Bool) {
    Preferences.BrowtherAnalytics.sentryEnabled.value = enabled
    if enabled {
      startSentry()
    } else {
      stopSentry()
    }
    track(event: "consent_changed", properties: ["consent": "sentry", "enabled": enabled])
  }

  /// Appelé quand le toggle PostHog change.
  public func setPostHogEnabled(_ enabled: Bool) {
    Preferences.BrowtherAnalytics.posthogEnabled.value = enabled
    if enabled {
      startPostHog()
    } else {
      stopPostHog()
    }
    track(event: "consent_changed", properties: ["consent": "posthog", "enabled": enabled])
  }

  // MARK: - Track API

  /// Envoie un event PostHog. No-op si PostHog désactivé ou pas init.
  /// Les properties communes (`os`, `version`, `$lib`, `$lib_version`) sont auto-injectées.
  public func track(event: String, properties: [String: Any] = [:]) {
    guard Preferences.BrowtherAnalytics.posthogEnabled.value else { return }
    guard let posthog else { return }
    var props = properties
    props["os"] = "ios"
    props["version"] = Bundle.main.infoDictionaryString(forKey: "CFBundleShortVersionString")
    props["$lib"] = "browther-native"
    props["$lib_version"] = "1.0.0"
    posthog.capture(event, properties: props)
  }

  // MARK: - Sentry

  private func startSentry() {
    guard !sentryStarted else { return }
    let dsn = AnalyticsConfig.sentryDsn
    guard !dsn.isEmpty else {
      log.error("Sentry DSN vide dans AnalyticsConfig — gen-analytics-config-ios.sh pas exécuté ?")
      return
    }
    SentrySDK.start { options in
      options.dsn = dsn
      // Périmètre Browther : crashes uniquement, pas de breadcrumbs/perf.
      options.enableAutoBreadcrumbTracking = false
      options.enableNetworkBreadcrumbs = false
      options.enableUserInteractionTracing = false
      options.enableAutoPerformanceTracing = false
      options.tracesSampleRate = 0
      options.profilesSampleRate = 0
      options.attachStacktrace = true
      // Le détecteur de gels reste actif (un gel long EST un bug utilisateur), mais le
      // défaut du SDK — 2 s — est calibré pour une app native légère, pas pour un
      // Chromium qui initialise son moteur + les modèles ONNX au démarrage. Mesuré en
      // prod sur la 2026.6.19 : 61 events, dont 44 venant d'un seul iPhone XR (3 Go),
      // aucun ne correspondant à un gel signalé. À 5 s on ne remonte plus que les gels
      // réellement perceptibles.
      options.appHangTimeoutInterval = 5
      // Pas de PII (IP, device name custom)
      options.sendDefaultPii = false
      // Tag pour cross-filter dans le dashboard Sentry partagé Desktop/iOS/Android.
      options.releaseName = "browther-ios@\(Bundle.main.infoDictionaryString(forKey: "CFBundleShortVersionString"))"
    }
    SentrySDK.configureScope { scope in
      scope.setUser(Sentry.User(userId: DistinctIdProvider.get()))
      scope.setTag(value: "ios", key: "os")
    }
    sentryStarted = true
    log.info("Sentry démarré")
  }

  private func stopSentry() {
    guard sentryStarted else { return }
    SentrySDK.close()
    sentryStarted = false
    log.info("Sentry stoppé")
  }

  // MARK: - PostHog

  private func startPostHog() {
    guard posthog == nil else { return }
    let key = AnalyticsConfig.posthogApiKey
    guard !key.isEmpty else {
      log.error("PostHog API key vide dans AnalyticsConfig — gen-analytics-config-ios.sh pas exécuté ?")
      return
    }
    let config = PostHogConfig(apiKey: key, host: AnalyticsConfig.posthogHost)
    config.captureApplicationLifecycleEvents = false
    config.captureScreenViews = false
    config.flushAt = 50
    config.flushIntervalSeconds = 30
    PostHogSDK.shared.setup(config)
    PostHogSDK.shared.identify(DistinctIdProvider.get())
    posthog = PostHogSDK.shared
    log.info("PostHog démarré")
  }

  private func stopPostHog() {
    guard let posthog else { return }
    posthog.flush()
    posthog.reset()
    PostHogSDK.shared.close()
    self.posthog = nil
    log.info("PostHog stoppé")
  }
}

// MARK: - Bundle helper

extension Bundle {
  fileprivate func infoDictionaryString(forKey key: String) -> String {
    (object(forInfoDictionaryKey: key) as? String) ?? "unknown"
  }
}
