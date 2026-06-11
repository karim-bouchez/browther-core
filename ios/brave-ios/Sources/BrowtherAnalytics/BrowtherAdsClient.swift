// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CryptoKit
import Foundation
import UIKit
import os.log

/// Une pub servie par la régie devndin-ads. Seuls `id` + `imageURL` sont
/// exposés à l'UI (parité mojom `BrowtherAd` desktop) ; le click URL et
/// l'impression token restent dans le client (jamais affichés/loggés/dans la
/// WebView).
public struct BrowtherServedAd: Equatable {
  public let id: String
  public let imageURL: String
}

/// Client HTTP de la régie pub dev&din (`https://ads-api.devndin.com`).
///
/// Port Swift natif de `components/browther_ads/ads_client.cc` (desktop). La
/// signature HMAC du serve se fait dans le code natif : le secret publisher ne
/// touche jamais la WebView (parité avec la règle "web → server-side only" de
/// `ads/docs/INTEGRATION.md`).
///
/// - `serve(placement:count:)` : `POST /v1/serve` signé HMAC-SHA256, met en
///   cache les pubs servies par `id`.
/// - `markVisible(id:)` : batch les impression tokens (≤ 50 toutes les ~10 s,
///   idempotent par `id`) puis flush `POST /v1/track/impressions`.
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

  // Pubs servies, indexées par id (résout impression token + click URL).
  private var served: [String: CachedAd] = [:]
  // Impression tokens en attente de flush + ids déjà comptés (anti double).
  private var pendingImpressions: [String] = []
  private var reportedIds: Set<String> = []
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

  /// True si publisher id + secret + url sont configurés (Bitwarden → env).
  public var isConfigured: Bool {
    !AnalyticsConfig.adsApiUrl.isEmpty
      && !AnalyticsConfig.adsPublisherId.isEmpty
      && !AnalyticsConfig.adsPublisherSecret.isEmpty
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

    // Body : sérialisé une fois, signé, envoyé tel quel (INTEGRATION § 2 — la
    // signature porte sur les octets exacts envoyés).
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

    // timestamp : epoch secondes (tolérance serveur ±5 min). nonce : UUID.
    let timestamp = String(Int(Date().timeIntervalSince1970))
    let nonce = UUID().uuidString.lowercased()
    let signature = sign(timestamp: timestamp, nonce: nonce, body: bodyData)

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = bodyData  // ⚠️ exactement les octets signés
    request.httpShouldHandleCookies = false
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(AnalyticsConfig.adsPublisherId, forHTTPHeaderField: "X-Publisher-Id")
    request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
    request.setValue(nonce, forHTTPHeaderField: "X-Nonce")
    request.setValue(signature, forHTTPHeaderField: "X-Signature")

    session.dataTask(with: request) { [weak self] data, response, error in
      let ads = self?.parseServeResponse(data: data, response: response, error: error) ?? []
      DispatchQueue.main.async { completion(ads) }
    }.resume()
  }

  /// hex(HMAC-SHA256(secret, "{timestamp}.{nonce}.{rawBody}")) — lowercase.
  /// Le préfixe est de l'ASCII ; on lui concatène les octets bruts du body pour
  /// reproduire à l'octet près le `StrCat` desktop (`ads_client.cc::SignBody`).
  private func sign(timestamp: String, nonce: String, body: Data) -> String {
    var message = Data("\(timestamp).\(nonce).".utf8)
    message.append(body)
    let key = SymmetricKey(data: Data(AnalyticsConfig.adsPublisherSecret.utf8))
    let mac = HMAC<SHA256>.authenticationCode(for: message, using: key)
    return Data(mac).map { String(format: "%02x", $0) }.joined()
  }

  private func parseServeResponse(
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
      freshCache[id] = CachedAd(clickURL: clickURL, impressionToken: token)
      result.append(BrowtherServedAd(id: id, imageURL: imageURL))
    }

    // Met à jour le cache sur la queue (thread-safe). Enqueué avant que la
    // completion main n'arrive → `markVisible`/`clickURL` voient bien le cache.
    queue.async { [weak self] in
      guard let self else { return }
      for (id, cached) in freshCache {
        self.served[id] = cached
      }
    }
    return result
  }

  // MARK: - Impressions

  /// Signale qu'une pub (par `id`) est devenue réellement visible. Batch +
  /// flush différé des impression tokens. Idempotent par `id`.
  public func markVisible(id: String) {
    queue.async { [weak self] in
      guard let self else { return }
      guard let cached = self.served[id], !cached.impressionToken.isEmpty else { return }
      guard !self.reportedIds.contains(id) else { return }
      self.reportedIds.insert(id)
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
