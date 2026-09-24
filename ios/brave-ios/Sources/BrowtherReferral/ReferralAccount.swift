// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Security

/// Le compte dev&din FACULTATIF sur iPhone — `docs/PARRAINAGE.md` § 7.1 et
/// § 7.4. ⛔ Jamais exigé : il ne sert qu'à faire suivre le SOUTIEN (mois
/// gagnés, code, abonnement) d'un appareil à l'autre — c'est le SEUL pont entre
/// un abonnement payé sur l'ordinateur (Polar) et l'iPhone (StoreKit), qui ne
/// se voient pas. 🔴 Il ne porte que ça : ni historique, ni favoris, ni onglets.
///
/// Pendant de `browther_referral_account.cc` (desktop, plateforme de référence).
///
/// ⭐ **On ne se connecte qu'UNE fois, sur un seul appareil** (recette Karim,
/// 2026-09-24) : **l'appareil connecté affiche un QR, l'autre le scanne**.
/// L'iPhone scanne dans les deux sens (`ReferralLinkTarget`) — le QR « Relier
/// mon téléphone » d'un ordinateur connecté (il reçoit sa propre session), ou
/// le QR de connexion d'un ordinateur qui ne l'est pas (il l'autorise avec la
/// sienne). ⛔ Le second appareil ne choisit donc jamais de méthode : c'est ce
/// qui évite deux comptes sans le savoir (Apple « masquer mon e-mail » ici,
/// Google là-bas).
///
/// Se connecter « autrement » reste possible, pour qui n'a qu'un appareil sous
/// la main : Google ou Apple dans une `ASWebAuthenticationSession` qui revient
/// sur `browther://auth/callback?code=…` (`auth-service/src/lib/sso-apps.ts`),
/// ou un code reçu par e-mail.
public struct ReferralAccount: Codable, Equatable, Sendable {
  /// L'identifiant Better Auth — il DEVIENT le sujet du parrainage.
  public var userId: String
  public var email: String?
  public var name: String?

  public init(userId: String, email: String?, name: String?) {
    self.userId = userId
    self.email = email
    self.name = name
  }
}

/// 🔴 Le jeton de session vit dans le TROUSSEAU, ⛔ jamais dans
/// `UserDefaults` ni dans un fichier : il vaut une session dev&din d'un an.
/// ⚠️ `ThisDeviceOnly` et non synchronisé — au contraire de l'identité
/// d'appareil (`ReferralIdentity`) : une session ne se recopie pas d'un
/// appareil à l'autre, chacun se connecte (et se déconnecte) pour lui-même.
public enum ReferralAccountStore {
  static let service = "com.devndin.browther.referral"
  static let account = "dev-account"

  private struct Stored: Codable {
    var account: ReferralAccount
    var token: String
  }

  public static func load() -> (account: ReferralAccount, token: String)? {
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data,
      let stored = try? JSONDecoder().decode(Stored.self, from: data),
      !stored.token.isEmpty, !stored.account.userId.isEmpty
    else { return nil }
    return (stored.account, stored.token)
  }

  @discardableResult
  public static func save(_ account: ReferralAccount, token: String) -> Bool {
    guard let data = try? JSONEncoder().encode(Stored(account: account, token: token)) else { return false }
    clear()
    var query = baseQuery()
    query[kSecValueData as String] = data
    // Lisible après le premier déverrouillage : le statut se relit aussi
    // quand l'app se réveille en arrière-plan.
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
  }

  public static func clear() {
    SecItemDelete(baseQuery() as CFDictionary)
  }

  private static func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
    ]
  }
}

/// Ce que la connexion peut rendre, en clair pour l'écran.
public enum ReferralAuthFailure: Error, Equatable, Sendable {
  /// Réseau coupé, service injoignable.
  case unreachable
  /// Code e-mail faux ou expiré.
  case badCode
  /// Tout le reste (code à usage unique périmé, session illisible…).
  case failed
}

/// Les appels au COMPTE — `auth.devndin.com` (Better Auth) et la porte du
/// paiement de `browther-api`. ⛔ Pas de cookies, pas de cache : le jeton se
/// présente en `Authorization: Bearer` (plugin `bearer` de l'auth-service),
/// comme le fait le desktop.
public final class ReferralAuthClient: @unchecked Sendable {
  public static let authURL = URL(string: "https://auth.devndin.com")!
  public static let apiURL = URL(string: "https://browther-api.devndin.com")!
  /// Le schéma du retour (`BRAVE_URL_SCHEME`, `Base.xcconfig`) — et l'entrée
  /// `browther` de `SSO_APP_LINKS` côté auth-service.
  public static let callbackScheme = "browther"
  /// L'app vue par l'auth-service : branding de ses pages et de ses e-mails.
  static let appId = "browther"

  private let session: URLSession
  private let language: String

  public init(language: String) {
    self.language = language
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 20
    self.session = URLSession(configuration: configuration)
  }

  public enum Provider: String, Sendable {
    case google, apple
  }

  /// La page où commence la connexion Google / Apple — elle finit sur
  /// `browther://auth/callback?code=…`.
  public static func signInURL(_ provider: Provider) -> URL {
    var components = URLComponents(url: authURL, resolvingAgainstBaseURL: false)!
    components.path = "/sso/initiate/\(provider.rawValue)"
    components.queryItems = [URLQueryItem(name: "app", value: appId)]
    return components.url!
  }

  /// Le code à usage unique du retour, lu dans `browther://auth/callback?code=…`.
  public static func callbackCode(_ url: URL) -> String? {
    guard url.scheme == callbackScheme,
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    else { return nil }
    return items.first { $0.name == "code" }?.value.flatMap { $0.isEmpty ? nil : $0 }
  }

  /// Échange le code à usage unique (5 min, une fois) contre le jeton de
  /// session. L'auth-service rend l'en-tête `Cookie` de la connexion : le jeton
  /// est la valeur du cookie `*.session_token` (signée — le plugin `bearer`
  /// l'accepte telle quelle).
  public func exchange(code: String) async throws -> String {
    let (data, status, _) = try await send("POST", Self.authURL, "/api/auth/sso/exchange-code", ["code": code])
    guard status == 200,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let cookie = object["cookie"] as? String,
      let token = Self.sessionToken(fromCookieHeader: cookie)
    else { throw ReferralAuthFailure.failed }
    return token
  }

  static func sessionToken(fromCookieHeader header: String) -> String? {
    for pair in header.split(separator: ";") {
      let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
      // ⚠️ Le NOM porte un préfixe par environnement (`COOKIE_PREFIX`) et
      // `__Secure-` : seul le suffixe est stable.
      guard parts.count == 2, parts[0].hasSuffix(".session_token"), !parts[1].isEmpty else { continue }
      return parts[1].removingPercentEncoding ?? parts[1]
    }
    return nil
  }

  /// Envoie un code à 6 chiffres par e-mail (courriel habillé Browther, dans
  /// la langue de l'app).
  public func sendEmailCode(to email: String) async throws {
    let (_, status, _) = try await send(
      "POST",
      Self.authURL,
      "/api/auth/email-otp/send-verification-otp",
      ["email": email, "type": "sign-in"]
    )
    guard (200..<300).contains(status) else { throw ReferralAuthFailure.failed }
  }

  /// Le code saisi → le jeton de session.
  public func verifyEmailCode(email: String, code: String) async throws -> String {
    let (data, status, headers) = try await send(
      "POST",
      Self.authURL,
      "/api/auth/sign-in/email-otp",
      ["email": email, "otp": code]
    )
    guard (200..<300).contains(status) else {
      throw (400..<500).contains(status) ? ReferralAuthFailure.badCode : ReferralAuthFailure.failed
    }
    // `set-auth-token` (plugin `bearer`) : le jeton signé. Sinon, le `token`
    // du corps — brut, que le plugin signe lui-même.
    if let token = headers["set-auth-token"], !token.isEmpty { return token }
    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let token = object["token"] as? String, !token.isEmpty
    {
      return token
    }
    throw ReferralAuthFailure.failed
  }

  /// Qui est-ce ? L'identifiant du compte devient le sujet du parrainage.
  public func account(token: String) async throws -> ReferralAccount {
    let (data, status, _) = try await send("GET", Self.authURL, "/api/auth/get-session", nil, token: token)
    guard status == 200,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let user = object["user"] as? [String: Any],
      let id = user["id"] as? String, !id.isEmpty
    else { throw ReferralAuthFailure.failed }
    return ReferralAccount(userId: id, email: user["email"] as? String, name: user["name"] as? String)
  }

  /// Révoque la session côté serveur — ⛔ sans jamais bloquer la déconnexion.
  public func signOut(token: String) async {
    _ = try? await send("POST", Self.authURL, "/api/auth/sign-out", [:], token: token)
  }

  /// ⭐ `POST /api/billing/link` : l'abonnement Polar payé sur l'ORDINATEUR
  /// (sans compte, ou avec l'e-mail du compte) est rejoué sur le compte. La
  /// cible est le compte authentifié ; `fromRef` ne sert qu'à retrouver le
  /// client Polar. `true` = quelque chose a été rattaché.
  public func linkBilling(token: String, fromRef: String?) async -> Bool {
    var body: [String: Any] = [:]
    if let fromRef { body["fromRef"] = fromRef }
    guard let (data, status, _) = try? await send("POST", Self.apiURL, "/api/billing/link", body, token: token),
      status == 200,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return false }
    return object["linked"] as? Bool == true
  }

  // MARK: - Relier un appareil (le QR, dans les deux sens)

  /// À quel compte ce QR « Relier mon téléphone » relie-t-il ? L'e-mail, pour
  /// la confirmation. ⛔ Ne consomme rien.
  public func peekLink(code: String) async throws -> String? {
    let (data, status, _) = try await send("POST", Self.authURL, "/api/auth/link/peek", ["code": code])
    guard status == 200 else { throw ReferralAuthFailure.badCode }
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    return object?["email"] as? String
  }

  /// Consomme le code : une session NEUVE pour cet appareil (⛔ jamais celle de
  /// l'ordinateur qui l'a affiché).
  public func redeemLink(code: String) async throws -> (token: String, account: ReferralAccount) {
    let (data, status, _) = try await send("POST", Self.authURL, "/api/auth/link/redeem", ["code": code])
    guard status == 200 else {
      throw status == 404 ? ReferralAuthFailure.badCode : ReferralAuthFailure.failed
    }
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let token = object["token"] as? String, !token.isEmpty,
      let user = object["user"] as? [String: Any],
      let id = user["id"] as? String, !id.isEmpty
    else { throw ReferralAuthFailure.failed }
    return (token, ReferralAccount(userId: id, email: user["email"] as? String, name: user["name"] as? String))
  }

  /// ⭐ L'iPhone CONNECTÉ autorise l'ordinateur qui affiche le QR du device
  /// flow (`/device?user_code=…`) — avec sa propre session, sans passer par
  /// la page web ni se reconnecter. `badCode` = code expiré ou déjà utilisé.
  public func approveDevice(userCode: String, token: String) async throws {
    let (_, status, _) = try await send(
      "POST",
      Self.authURL,
      "/api/auth/device/approve",
      ["userCode": userCode],
      token: token
    )
    switch status {
    case 200..<300: return
    case 400: throw ReferralAuthFailure.badCode
    default: throw ReferralAuthFailure.failed
    }
  }

  // MARK: - Transport

  private func send(
    _ method: String,
    _ base: URL,
    _ path: String,
    _ body: [String: Any]?,
    token: String? = nil
  ) async throws -> (Data, Int, [String: String]) {
    var request = URLRequest(url: base.appendingPathComponent(path))
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(Self.appId, forHTTPHeaderField: "X-App-Id")
    request.setValue(language, forHTTPHeaderField: "Accept-Language")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    }
    do {
      let (data, response) = try await session.data(for: request)
      let http = response as? HTTPURLResponse
      var headers: [String: String] = [:]
      for (key, value) in http?.allHeaderFields ?? [:] {
        if let key = key as? String, let value = value as? String { headers[key.lowercased()] = value }
      }
      return (data, http?.statusCode ?? 0, headers)
    } catch {
      throw ReferralAuthFailure.unreachable
    }
  }
}

/// Ce qu'un QR (ou un lien ouvert dans Browther) demande au compte.
/// ⛔ Seul `auth.devndin.com` est reconnu : un QR d'ailleurs n'est pas un QR
/// de Browther.
public enum ReferralLinkTarget: Equatable, Sendable {
  /// « Relier mon téléphone » d'un ordinateur CONNECTÉ : `/link?c=…`.
  case link(code: String)
  /// « Connecter un compte » d'un ordinateur qui NE l'est PAS (device flow) :
  /// `/device?user_code=…` — l'iPhone connecté l'autorise.
  case computer(userCode: String)

  public init?(_ url: URL) {
    guard url.scheme == "https", url.host?.lowercased() == ReferralAuthClient.authURL.host,
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    else { return nil }
    func value(_ name: String) -> String? {
      items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }
    switch url.path {
    case "/link":
      guard let code = value("c")?.lowercased(), code.allSatisfy(\.isHexDigit) else { return nil }
      self = .link(code: code)
    case "/device":
      guard let raw = value("user_code") else { return nil }
      let code = raw.uppercased().filter { $0.isLetter || $0.isNumber }
      guard code.count == 8 else { return nil }
      self = .computer(userCode: code)
    default:
      return nil
    }
  }

  public init?(scanned text: String) {
    guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
    self.init(url)
  }

  /// `ABCD-EFGH`, comme l'ordinateur l'affiche.
  public static func display(_ userCode: String) -> String {
    userCode.count == 8 ? "\(userCode.prefix(4))-\(userCode.suffix(4))" : userCode
  }
}
