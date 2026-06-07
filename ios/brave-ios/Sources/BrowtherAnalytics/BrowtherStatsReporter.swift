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
  private static let kPendingPersonsKey = "browther.stats.pending.persons_blurred"

  // Compteurs cumulatifs locaux affichés sur la NTP (jamais reset). Parité
  // avec les prefs C++ Desktop/Android `kStatsMusicSecondsTotal` /
  // `kStatsPersonsBlurredTotal`.
  private static let kTotalMusicKey = "browther.stats.total.music_seconds"
  private static let kTotalPersonsKey = "browther.stats.total.persons_blurred"

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
      // Total cumulatif (NTP) — toujours incrémenté, jamais reset.
      let total = UserDefaults.standard.integer(forKey: Self.kTotalMusicKey)
      UserDefaults.standard.set(total + delta, forKey: Self.kTotalMusicKey)
      // Pending (backend) — reset après flush HTTP 200.
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

  /// À appeler quand des personnes sont effectivement floutées par Basarunaa.
  /// Incrémente le total local (affiché NTP) ET le pending backend.
  public func addPersonsBlurred(_ delta: Int) {
    guard delta > 0 else { return }
    queue.async {
      let total = UserDefaults.standard.integer(forKey: Self.kTotalPersonsKey)
      UserDefaults.standard.set(total + delta, forKey: Self.kTotalPersonsKey)
      let cur = UserDefaults.standard.integer(forKey: Self.kPendingPersonsKey)
      UserDefaults.standard.set(cur + delta, forKey: Self.kPendingPersonsKey)
    }
  }

  // MARK: - Lecture (NTP widget)

  /// Total cumulatif de secondes de musique retirées. Lisible depuis le main
  /// thread (UserDefaults thread-safe en lecture).
  public var musicSecondsTotal: Int {
    return UserDefaults.standard.integer(forKey: Self.kTotalMusicKey)
  }

  /// Total cumulatif de personnes floutées.
  public var personsBlurredTotal: Int {
    return UserDefaults.standard.integer(forKey: Self.kTotalPersonsKey)
  }

  // MARK: - Flush

  private func performFlush() {
    let music = UserDefaults.standard.integer(forKey: Self.kPendingMusicKey)
    let ads = UserDefaults.standard.integer(forKey: Self.kPendingAdsKey)
    let persons = UserDefaults.standard.integer(forKey: Self.kPendingPersonsKey)
    guard music > 0 || ads > 0 || persons > 0 else { return }

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
      "personsBlurredDelta": persons,
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
      // Succès → soustraire ce qu'on vient d'envoyer (préserve les Add
      // arrivés pendant le flush, parité avec stats_client.cc Desktop).
      self.queue.async {
        let curMusic = UserDefaults.standard.integer(forKey: Self.kPendingMusicKey)
        UserDefaults.standard.set(max(0, curMusic - music), forKey: Self.kPendingMusicKey)
        let curAds = UserDefaults.standard.integer(forKey: Self.kPendingAdsKey)
        UserDefaults.standard.set(max(0, curAds - ads), forKey: Self.kPendingAdsKey)
        let curPersons = UserDefaults.standard.integer(forKey: Self.kPendingPersonsKey)
        UserDefaults.standard.set(max(0, curPersons - persons), forKey: Self.kPendingPersonsKey)
      }
      self.log.info("Stats flushées : music=\(music), ads=\(ads), persons=\(persons)")
    }.resume()
  }
}
