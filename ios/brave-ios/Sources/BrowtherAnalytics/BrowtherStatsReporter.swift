// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences
import os.log

/// Stats publiques anonymes "Depuis le lancement" — POST `/api/stats/ingest`.
///
/// Pattern identique au backend devndin :
/// - UPSERT cumulatif par `anon_uuid` (réutilise `DistinctIdProvider`)
/// - Caps anti-fraude côté serveur, donc on peut envoyer librement
/// - Buffer en mémoire + UserDefaults (survit kill app), flush toutes les 60s
///
/// Hooks attendus :
/// - **Sawtunaa** : `addMusicSeconds(_:)` — chaque tranche d'audio filtré
/// - **Shields** : `addAdsBlocked(_:)` — chaque pub bloquée
///
/// Consent :
/// - `ads_blocked` gaté par `Preferences.BrowtherAnalytics.posthogEnabled` (équivalent `kP3AEnabled` Desktop)
/// - `music_seconds` = opt-in implicite par activation de Sawtunaa (cohérent Desktop)
public final class BrowtherStatsReporter {

  public static let shared = BrowtherStatsReporter()

  private let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.devndin.browther",
    category: "browther-stats"
  )

  private let queue = DispatchQueue(label: "browther.stats", qos: .utility)
  private var flushTimer: Timer?

  // Pending deltas — chargés au démarrage, flushés toutes les 60s.
  private static let kPendingMusicKey = "browther.stats.pending.music_seconds"
  private static let kPendingAdsKey = "browther.stats.pending.ads_blocked"

  private static let kFlushIntervalSeconds: TimeInterval = 60

  private init() {}

  // MARK: - Lifecycle

  /// Démarre le timer de flush (à appeler depuis AppDelegate après init analytics).
  public func start() {
    queue.async { [weak self] in
      guard let self else { return }
      // Flush au démarrage si pending de la session précédente.
      self.performFlush()
    }
    // Timer sur la main runloop
    DispatchQueue.main.async { [weak self] in
      self?.flushTimer?.invalidate()
      self?.flushTimer = Timer.scheduledTimer(
        withTimeInterval: Self.kFlushIntervalSeconds,
        repeats: true
      ) { [weak self] _ in
        self?.queue.async { self?.performFlush() }
      }
    }
  }

  // MARK: - Public counters

  public func addMusicSeconds(_ delta: Int) {
    guard delta > 0 else { return }
    queue.async {
      let cur = UserDefaults.standard.integer(forKey: Self.kPendingMusicKey)
      UserDefaults.standard.set(cur + delta, forKey: Self.kPendingMusicKey)
    }
  }

  public func addAdsBlocked(_ delta: Int) {
    guard delta > 0 else { return }
    // Gate consent identique Desktop (kP3AEnabled / posthogEnabled)
    guard Preferences.BrowtherAnalytics.posthogEnabled.value else { return }
    queue.async {
      let cur = UserDefaults.standard.integer(forKey: Self.kPendingAdsKey)
      UserDefaults.standard.set(cur + delta, forKey: Self.kPendingAdsKey)
    }
  }

  // MARK: - Flush

  private func performFlush() {
    let music = UserDefaults.standard.integer(forKey: Self.kPendingMusicKey)
    let ads = UserDefaults.standard.integer(forKey: Self.kPendingAdsKey)
    guard music > 0 || ads > 0 else { return }

    let url = AnalyticsConfig.browtherApiUrl
    guard !url.isEmpty, let endpoint = URL(string: "\(url)/api/stats/ingest") else {
      log.error("BROWTHER_API_URL invalide — skip flush")
      return
    }

    let body: [String: Any] = [
      "anonUuid": DistinctIdProvider.get(),
      "platform": "ios",
      "musicSecondsDelta": music,
      "adsBlockedDelta": ads,
      "personsBlurredDelta": 0,
    ]

    guard let json = try? JSONSerialization.data(withJSONObject: body) else { return }

    var req = URLRequest(url: endpoint)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = json
    req.timeoutInterval = 15

    URLSession.shared.dataTask(with: req) { [weak self] _, response, error in
      guard let self else { return }
      if let error {
        self.log.error("Stats flush KO réseau : \(error.localizedDescription, privacy: .public)")
        return
      }
      let code = (response as? HTTPURLResponse)?.statusCode ?? 0
      guard (200..<300).contains(code) else {
        self.log.error("Stats flush KO HTTP \(code, privacy: .public) — pending conservés")
        return
      }
      // Succès → reset les compteurs (sur la queue interne pour éviter race)
      self.queue.async {
        UserDefaults.standard.set(0, forKey: Self.kPendingMusicKey)
        UserDefaults.standard.set(0, forKey: Self.kPendingAdsKey)
      }
      self.log.info("Stats flushées : music=\(music), ads=\(ads)")
    }.resume()
  }
}
