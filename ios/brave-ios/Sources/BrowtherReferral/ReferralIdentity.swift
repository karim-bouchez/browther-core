// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Security

/// L'identité d'appareil du parrainage — `docs/PARRAINAGE.md` § 7.1 et § 12.28.
///
/// ⭐ **Un UUID dans le trousseau SYNCHRONISABLE** (`kSecAttrSynchronizable`) :
/// il suit la personne d'un iPhone à l'autre par le trousseau iCloud et
/// survit à la désinstallation. ⚠️ Deux iPhone du même compte iCloud sont donc
/// le MÊME sujet (même code, même couverture) — c'est voulu. Repli non
/// synchronisé si iCloud refuse.
///
/// ⚠️ **Ce n'est PAS `Preferences.BrowtherAnalytics.distinctId`** : celui-là vit
/// dans UserDefaults, se régénère à la réinstallation et sert à l'analytique —
/// un sujet qui changerait à chaque réinstallation perdrait ses mois et son
/// code, et offrirait un nouveau « même appareil » à chaque fois. ⛔ Jamais
/// utilisé pour le ciblage de la régie. Le service n'en stocke qu'un hachage.
///
/// 🔴 **Le compte dev&din facultatif** (§ 7.1, 2026-09-22) viendra PAR-DESSUS :
/// le sujet deviendra le compte quand il y en a un, et cet appareil restera le
/// `deviceRef` de la garde « même appareil ».
public enum ReferralIdentity {
  static let service = "com.devndin.browther.referral"
  static let account = "subject"

  /// L'identité de l'appareil, créée au premier appel. `nil` si le trousseau
  /// refuse tout (⛔ alors tout reste ouvert : personne à qui rattacher un code).
  public static func deviceSubject() -> String? {
    if let existing = read(synchronizable: true) ?? read(synchronizable: false) {
      return existing
    }
    let created = UUID().uuidString.lowercased()
    if write(created, synchronizable: true) { return created }
    if write(created, synchronizable: false) { return created }
    return nil
  }

  private static func baseQuery(synchronizable: Bool) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any,
    ]
  }

  private static func read(synchronizable: Bool) -> String? {
    var query = baseQuery(synchronizable: synchronizable)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data,
      let value = String(data: data, encoding: .utf8),
      !value.isEmpty
    else { return nil }
    return value
  }

  private static func write(_ value: String, synchronizable: Bool) -> Bool {
    var query = baseQuery(synchronizable: synchronizable)
    query[kSecValueData as String] = Data(value.utf8)
    // ⚠️ « Après le premier déverrouillage » : le statut se lit aussi quand
    // l'app se réveille en arrière-plan. ⛔ Pas `ThisDeviceOnly`, qui interdit
    // la synchronisation.
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
  }
}
