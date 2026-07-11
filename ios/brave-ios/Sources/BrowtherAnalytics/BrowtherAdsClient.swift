// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import UIKit
import os.log

/// Une pub servie par la régie devndin-ads. `id`, `imageURL`, `ratio` et
/// `showAdLabel` sont exposés à l'UI (parité mojom `BrowtherAd` desktop) ; le
/// click URL et l'impression token restent dans le client (jamais
/// affichés/loggés/dans la WebView).
public struct BrowtherServedAd: Equatable {
  public let id: String
  public let imageURL: String
  /// Format renvoyé par le serve (ex "3.2:1") — pilote l'aspect-ratio côté UI
  /// (pas de valeur en dur, INTEGRATION.md § 3). Vide si absent (fallback UI).
  public let ratio: String
  /// true = annonceur externe → label « Pub » obligatoire sur cette créa ;
  /// false = house ad dev&din, pas de label. Décision par slide.
  public let showAdLabel: Bool
}

/// Client HTTP de la régie pub dev&din (`https://ads-api.devndin.com`).
///
/// Port Swift natif de `components/browther_ads/ads_client.cc` (desktop).
/// Mode publisher PUBLIC : header `X-Publisher-Id` seul, aucun secret embarqué
/// (HMAC publisher retiré le 2026-07-11 — un binaire distribué ne peut pas
/// garder un secret ; l'anti-fraude vit côté serveur : serve tokens signés
/// serveur, TTL, dédup, rate limiting).
///
/// - `serve(placement:count:)` : `POST /v1/serve`, re-serve throttlé à ~10 min
///   par placement (définition officielle de l'impression, INTEGRATION.md § 4)
///   — entre deux, le lot en cache est resservi sans requête réseau et sans
///   re-tracker.
/// - `markVisible(id:)` : batch les impression tokens (≤ 50 toutes les ~10 s,
///   idempotent par pub servie) puis flush `POST /v1/track/impressions`.
/// - `clickURL(id:)` : résout l'URL de click (302 → targetUrl + log) d'une pub.
///
/// Config embarquée via `AnalyticsConfig` (généré depuis `analytics.env`). Une
/// config vide ⇒ `isConfigured == false` ⇒ aucune requête réseau, la bannière
/// se masque proprement.
public final class BrowtherAdsClient {

  public static let shared = BrowtherAdsClient()

  // Délai de batch des impressions (parité `kImpressionFlushDelay` = 10 s).
  // Les tokens expirent en 30 min côté serveur.
  private static let flushDelay: TimeInterval = 10
  // Cap serveur : 50 tokens par POST (parité `kMaxImpressionBatch`).
  private static let maxImpressionBatch = 50
  // Throttle de re-serve par placement (parité `kServeCacheTtl` desktop,
  // INTEGRATION.md § 4). Les tokens expirent en 30 min > TTL.
  private static let serveCacheTtl: TimeInterval = 10 * 60

  private let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.devndin.browther",
    category: "browther-ads"
  )

  // Sérialise tout l'état mutable (cache, pending, timer).
  private let queue = DispatchQueue(label: "browther.ads", qos: .utility)

  // Session éphémère : pas de cookies (parité `credentials_mode = kOmit` +
  // `LOAD_DO_NOT_SAVE_COOKIES` desktop, traffic annotation `cookies_allowed: NO`).
  private let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false
    config.httpCookieAcceptPolicy = .never
    config.timeoutIntervalForRequest = 15
    return URLSession(configuration: config)
  }()

  // Données privées d'une pub servie (jamais exposées hors du client).
  private struct CachedAd {
    let clickURL: String
    let impressionToken: String
  }

  // Lot servi par placement, pour le throttle de re-serve 10 min.
  private struct CachedServe {
    let servedAt: Date
    let ads: [BrowtherServedAd]
  }

  // Pubs servies, indexées par id (résout impression token + click URL).
  private var served: [String: CachedAd] = [:]
  // Cache de re-serve par placement (throttle ~10 min, INTEGRATION.md § 4).
  private var serveCache: [String: CachedServe] = [:]
  // Impression tokens en attente de flush + tokens déjà consommés (anti
  // double : une pub resservie depuis le cache garde son token consommé).
  private var pendingImpressions: [String] = []
  private var consumedTokens: Set<String> = []
  private var flushWorkItem: DispatchWorkItem?

  private init() {
    // Best effort : flush les impressions restantes quand l'app passe en
    // background (INTEGRATION § 4 « flush on background »).
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(appDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
  }

  // MARK: - Config

  /// True si publisher id + url sont configurés (analytics.env).
  public var isConfigured: Bool {
    !AnalyticsConfig.adsApiUrl.isEmpty
      && !AnalyticsConfig.adsPublisherId.isEmpty
  }

  // MARK: - Serve

  /// Récupère jusqu'à `count` pubs pour `placement`. Best effort : sur config
  /// absente / erreur réseau / 4xx, renvoie un tableau vide (jamais d'échec dur
  /// — l'UI masque simplement la bannière). `completion` est appelé sur la main
  /// queue.
  public func serve(
    placement: String,
    count: Int,
    completion: @escaping ([BrowtherServedAd]) -> Void
  ) {
    guard isConfigured else {
      DispatchQueue.main.async { completion([]) }
      return
    }

    // Throttle 10 min : lot encore frais → resservi sans requête réseau (les
    // tokens déjà consommés le restent, `consumedTokens` dédup).
    let cachedAds: [BrowtherServedAd]? = queue.sync {
      guard let cached = serveCache[placement],
        Date().timeIntervalSince(cached.servedAt) < Self.serveCacheTtl
      else {
        return nil
      }
      return cached.ads
    }
    if let cachedAds {
      DispatchQueue.main.async { completion(cachedAds) }
      return
    }

    let bodyDict: [String: Any] = [
      "placement": placement,
      "platform": "ios",
      "count": count,
    ]
    guard
      let bodyData = try? JSONSerialization.data(withJSONObject: bodyDict),
      let url = URL(string: "\(AnalyticsConfig.adsApiUrl)/v1/serve")
    else {
      DispatchQueue.main.async { completion([]) }
      return
    }

    // Mode publisher public : X-Publisher-Id seul, aucune signature (HMAC
    // retiré 2026-07-11 — parité `ads_client.cc` desktop/Android).
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = bodyData
    request.httpShouldHandleCookies = false
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(AnalyticsConfig.adsPublisherId, forHTTPHeaderField: "X-Publisher-Id")

    session.dataTask(with: request) { [weak self] data, response, error in
      let ads =
        self?.parseServeResponse(
          placement: placement,
          data: data,
          response: response,
          error: error
        ) ?? []
      DispatchQueue.main.async { completion(ads) }
    }.resume()
  }

  private func parseServeResponse(
    placement: String,
    data: Data?,
    response: URLResponse?,
    error: Error?
  ) -> [BrowtherServedAd] {
    if let error {
      log.debug("serve KO réseau : \(error.localizedDescription, privacy: .public)")
      return []
    }
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(code), let data else {
      log.debug("serve KO http=\(code, privacy: .public)")
      return []
    }
    guard
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let adsArray = root["ads"] as? [[String: Any]]
    else {
      return []
    }

    var result: [BrowtherServedAd] = []
    var freshCache: [String: CachedAd] = [:]
    for ad in adsArray {
      guard
        let id = ad["id"] as? String, !id.isEmpty,
        let imageURL = ad["imageUrl"] as? String, !imageURL.isEmpty
      else {
        continue
      }
      let clickURL = ad["clickUrl"] as? String ?? ""
      let token = ad["impressionToken"] as? String ?? ""
      // Champ absent (vieux cache serveur) → house ad, pas de label.
      let showAdLabel = ad["showAdLabel"] as? Bool ?? false
      let ratio = ad["ratio"] as? String ?? ""
      freshCache[id] = CachedAd(clickURL: clickURL, impressionToken: token)
      result.append(
        BrowtherServedAd(id: id, imageURL: imageURL, ratio: ratio, showAdLabel: showAdLabel)
      )
    }

    // Met à jour les caches sur la queue (thread-safe). Enqueué avant que la
    // completion main n'arrive → `markVisible`/`clickURL` voient bien le cache.
    queue.async { [weak self] in
      guard let self else { return }
      for (id, cached) in freshCache {
        self.served[id] = cached
      }
      // Alimente le throttle 10 min de re-serve pour ce placement.
      self.serveCache[placement] = CachedServe(servedAt: Date(), ads: result)
    }
    return result
  }

  // MARK: - Impressions

  /// Signale qu'une pub (par `id`) est devenue réellement visible. Batch +
  /// flush différé des impression tokens. Idempotent par pub SERVIE : une pub
  /// resservie depuis le cache 10 min garde le même token, déjà consommé si
  /// elle a déjà été vue.
  public func markVisible(id: String) {
    queue.async { [weak self] in
      guard let self else { return }
      guard let cached = self.served[id], !cached.impressionToken.isEmpty else { return }
      guard !self.consumedTokens.contains(cached.impressionToken) else { return }
      self.consumedTokens.insert(cached.impressionToken)
      self.pendingImpressions.append(cached.impressionToken)
      self.scheduleFlushLocked()
    }
  }

  /// URL de click d'une pub servie (nil si `id` inconnu ou sans click URL).
  public func clickURL(id: String) -> URL? {
    queue.sync {
      guard let cached = served[id], !cached.clickURL.isEmpty else { return nil }
      return URL(string: cached.clickURL)
    }
  }

  // Programme un flush dans `flushDelay` s'il n'y en a pas déjà un. À appeler
  // depuis `queue`.
  private func scheduleFlushLocked() {
    guard flushWorkItem == nil, !pendingImpressions.isEmpty else { return }
    let work = DispatchWorkItem { [weak self] in
      self?.flushWorkItem = nil
      self?.flushImpressionsLocked()
    }
    flushWorkItem = work
    queue.asyncAfter(deadline: .now() + Self.flushDelay, execute: work)
  }

  // Flush jusqu'à `maxImpressionBatch` tokens ; reschedule s'il en reste. À
  // appeler depuis `queue`.
  private func flushImpressionsLocked() {
    guard isConfigured, !pendingImpressions.isEmpty else { return }
    guard let url = URL(string: "\(AnalyticsConfig.adsApiUrl)/v1/track/impressions") else {
      return
    }

    let take = min(pendingImpressions.count, Self.maxImpressionBatch)
    let tokens = Array(pendingImpressions.prefix(take))
    pendingImpressions.removeFirst(take)

    guard let body = try? JSONSerialization.data(withJSONObject: ["tokens": tokens]) else {
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = body
    request.httpShouldHandleCookies = false
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    session.dataTask(with: request) { [weak self] _, response, error in
      guard let self else { return }
      let code = (response as? HTTPURLResponse)?.statusCode ?? 0
      if error != nil || !(200..<300).contains(code) {
        // Réseau/HTTP KO → requeue pour retry (idempotent : un token consommé
        // 2× = `duplicates` côté serveur, sans erreur).
        self.queue.async {
          self.pendingImpressions.insert(contentsOf: tokens, at: 0)
          self.scheduleFlushLocked()
        }
        self.log.debug("impressions flush KO (requeued \(tokens.count, privacy: .public))")
      } else {
        self.log.debug("impressions flushed : \(tokens.count, privacy: .public)")
      }
    }.resume()

    // Reste des tokens (> 50) → reschedule.
    if !pendingImpressions.isEmpty {
      scheduleFlushLocked()
    }
  }

  @objc private func appDidEnterBackground() {
    queue.async { [weak self] in
      guard let self else { return }
      self.flushWorkItem?.cancel()
      self.flushWorkItem = nil
      self.flushImpressionsLocked()
    }
  }
}
