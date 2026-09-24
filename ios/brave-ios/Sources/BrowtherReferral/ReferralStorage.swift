// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Ce que le parrainage garde sur l'appareil — ⚠️ sous des clés
/// `browther.referral.*`, ⛔ jamais celles de Brave (`urp.referral.*`, son
/// programme de codes promo d'installation, toujours dans le fork).
///
/// Tout est en JSON dans `UserDefaults` : illisible = « rien n'a encore été
/// vu », ⛔ jamais une erreur qui éteindrait le parrainage.
public final class ReferralStorage: @unchecked Sendable {
  public static let shared = ReferralStorage()

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  enum Key {
    static let prompt = "browther.referral.prompt"
    static let cachedStatus = "browther.referral.cached-status"
    static let gaugeUnderstood = "browther.referral.gauge-understood"
    static let defaultDays = "browther.referral.default-days"
    static let snapshotDay = "browther.referral.snapshot-day"
    static let recetteSubject = "browther.referral.recette-subject"
    static let recetteToken = "browther.referral.recette-token"
    static let transferredFor = "browther.referral.transferred-for"
  }

  // MARK: - L'état des sollicitations

  public var prompt: ReferralPromptState {
    get { decode(ReferralPromptState.self, Key.prompt) ?? ReferralPromptState() }
    set { encode(newValue, Key.prompt) }
  }

  // MARK: - Le dernier statut connu (sens de la panne : § 7)

  private struct Cached: Codable {
    var subject: String
    var status: ReferralStatus
  }

  /// ⚠️ **Le statut se lit avec SON sujet** (§ 12.13) : sinon, le temps que le
  /// nouveau arrive, l'écran montrerait le code et la couverture d'un autre.
  public func cachedStatus(for subject: String) -> ReferralStatus? {
    guard let cached = decode(Cached.self, Key.cachedStatus), cached.subject == subject else { return nil }
    return cached.status
  }

  public func saveStatus(_ status: ReferralStatus, for subject: String) {
    encode(Cached(subject: subject, status: status), Key.cachedStatus)
  }

  // MARK: - La jauge comprise (§ 12.4)

  /// La personne a tiré le curseur ELLE-MÊME jusqu'à « à vie » : plus aucune
  /// jauge ne rejoue la démo, nulle part.
  public var gaugeUnderstood: Bool {
    get { defaults.bool(forKey: Key.gaugeUnderstood) }
    set { defaults.set(newValue, forKey: Key.gaugeUnderstood) }
  }

  // MARK: - La validation du filleul

  public var defaultBrowserDays: DefaultBrowserDays {
    get { decode(DefaultBrowserDays.self, Key.defaultDays) ?? DefaultBrowserDays() }
    set { encode(newValue, Key.defaultDays) }
  }

  // MARK: - La photo du jour (analytique)

  public var snapshotDay: String? {
    get { defaults.string(forKey: Key.snapshotDay) }
    set { defaults.set(newValue, forKey: Key.snapshotDay) }
  }

  // MARK: - Le compte (§ 7.1)

  /// Le compte dans lequel CET appareil a déjà été fusionné (`/v1/transfer`) —
  /// une fois par compte. ⚠️ Un identifiant, ⛔ jamais le jeton (trousseau).
  public var transferredFor: String? {
    get { defaults.string(forKey: Key.transferredFor) }
    set { defaults.set(newValue, forKey: Key.transferredFor) }
  }

  // MARK: - 🧪 Recette (§ 12.18)

  /// Une identité de recette posée PAR-DESSUS la vraie (« repartir d'un
  /// appareil neuf ») — ⛔ jamais dans un build du store.
  public var recetteSubject: String? {
    get { defaults.string(forKey: Key.recetteSubject) }
    set { defaults.set(newValue, forKey: Key.recetteSubject) }
  }

  /// 🔴 Le jeton d'administration se SAISIT dans l'outil et reste sur
  /// l'appareil : ⛔ jamais une constante de build — il ouvrirait l'accès à vie
  /// à qui lit le binaire.
  public var recetteToken: String? {
    get { defaults.string(forKey: Key.recetteToken) }
    set { defaults.set(newValue, forKey: Key.recetteToken) }
  }

  // MARK: - JSON

  private func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
    guard let data = defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  private func encode<T: Encodable>(_ value: T, _ key: String) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    defaults.set(data, forKey: key)
  }
}
