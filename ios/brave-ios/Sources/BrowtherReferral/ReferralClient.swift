// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Le service injoignable, un 429, un 500 — ⛔ jamais une raison de bloquer.
public struct ReferralUnavailable: Error, Sendable {
  public let status: Int?

  public init(status: Int?) {
    self.status = status
  }
}

/// L'identité envoyée à chaque appel (§ 7.1).
public struct ReferralIdentityBody: Sendable {
  public var product: String
  /// Compte si le produit en a un, identité d'appareil sinon.
  public var subjectRef: String
  /// L'appareil, quand il diffère du sujet — sert la garde « même appareil ».
  public var deviceRef: String?
  public var platform: ReferralPlatform

  public init(product: String, subjectRef: String, deviceRef: String? = nil, platform: ReferralPlatform) {
    self.product = product
    self.subjectRef = subjectRef
    self.deviceRef = deviceRef
    self.platform = platform
  }
}

/// Le client du service — `referral/docs/API.md`. **Tout est en POST** : le
/// sujet ne doit jamais se promener dans une URL. Pas d'authentification :
/// un secret dans une app n'est pas un secret (§ 10.3).
///
/// ⚠️ **Toutes les lectures sont bornées** (8 s) : le parrainage ne doit jamais
/// retenir un écran. Une écriture ne l'est pas — un renvoi créerait un
/// doublon —, SAUF les écritures idempotentes qui peignent l'écran
/// (`register`, `transfer`).
///
/// ⛔ **Pas de cookies, pas de cache** : une session éphémère, comme le client
/// de la régie.
public final class ReferralClient: @unchecked Sendable {
  private let baseURL: URL
  private let identity: ReferralIdentityBody
  private let session: URLSession

  static let readTimeout: TimeInterval = 8
  static let writeTimeout: TimeInterval = 30

  public init(baseURL: URL = ReferralProduct.serviceURL, identity: ReferralIdentityBody) {
    self.baseURL = baseURL
    self.identity = identity
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    self.session = URLSession(configuration: configuration)
  }

  public var subjectRef: String { identity.subjectRef }

  /// À chaque ouverture : crée le sujet si besoin, rend le statut complet.
  public func register() async throws -> ReferralStatus {
    try await call("/v1/register", [:], bounded: true)
  }

  public func status() async throws -> ReferralStatus {
    try await call("/v1/status", [:], bounded: true)
  }

  /// ⭐ Le mois démarre ICI (à l'annonce), ⛔ pas à l'installation (§ 4).
  public func startTrial() async throws -> ReferralStatus {
    try await call("/v1/trial", [:], bounded: false)
  }

  /// Un partage a ABOUTI (destinataire choisi, ou message copié). ⛔ Ne crée
  /// AUCUNE invitation (§ 12.1) : il ne sert qu'au moment « partage » des 3 jours.
  public func share() async throws -> ShareOutcome {
    try await call("/v1/share", [:], bounded: false)
  }

  public func redeem(code: String) async throws -> RedeemOutcome {
    try await call("/v1/redeem", ["code": code], bounded: false)
  }

  /// Un fait d'usage du filleul — Browther : un `default_browser_day` par jour.
  public func reportProgress(event: String, eventKey: String, occurredAt: Date) async throws -> ProgressOutcome {
    try await call(
      "/v1/progress",
      ["event": event, "eventKey": eventKey, "occurredAt": ReferralDate.string(occurredAt)],
      bounded: false
    )
  }

  /// 🧪 Poser une situation COMPLÈTE (`POST /v1/admin/recette`, § 12.18).
  public func applyRecette(token: String, state: RecetteState) async throws -> ReferralStatus {
    let encoded = try JSONEncoder().encode(state)
    let stateObject = try JSONSerialization.jsonObject(with: encoded)
    return try await call(
      "/v1/admin/recette",
      ["state": stateObject],
      bounded: true,
      headers: ["X-Admin-Token": token]
    )
  }

  // MARK: - Transport

  private func call<T: Decodable>(
    _ path: String,
    _ extra: [String: Any],
    bounded: Bool,
    headers: [String: String] = [:]
  ) async throws -> T {
    var body: [String: Any] = [
      "product": identity.product,
      "subjectRef": identity.subjectRef,
      "platform": identity.platform.rawValue,
    ]
    if let deviceRef = identity.deviceRef { body["deviceRef"] = deviceRef }
    for (key, value) in extra { body[key] = value }

    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    request.httpMethod = "POST"
    request.timeoutInterval = bounded ? Self.readTimeout : Self.writeTimeout
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, response) = try await session.data(for: request)
      let code = (response as? HTTPURLResponse)?.statusCode ?? 0
      guard (200..<300).contains(code) else { throw ReferralUnavailable(status: code) }
      return try JSONDecoder().decode(T.self, from: data)
    } catch let error as ReferralUnavailable {
      throw error
    } catch {
      throw ReferralUnavailable(status: nil)
    }
  }
}
