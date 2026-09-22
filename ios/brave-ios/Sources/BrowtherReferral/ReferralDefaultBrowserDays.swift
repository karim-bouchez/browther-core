// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// La validation du filleul Browther — `docs/PARRAINAGE.md` § 9 (2026-09-22) :
/// **3 journées distinctes où Browther, navigateur PAR DÉFAUT, a chargé une
/// vraie page**.
///
/// ## Pourquoi deux registres
///
/// Un jour compte quand deux faits tombent LE MÊME JOUR LOCAL :
/// - **une preuve du défaut** — ⚠️ une PREUVE, ⛔ jamais un « probablement » :
///   - l'API d'Apple (iOS 18.2+, `UIApplication.isDefault(.webBrowser)`) a
///     répondu oui ce jour-là — ⚠️ elle est **rationnée** par Apple ;
///   - OU un lien `http(s)` est arrivé depuis une autre app (WhatsApp, Mail…) :
///     iOS ne l'envoie qu'au navigateur par défaut ;
/// - **une vraie page chargée** (l'unité d'usage de Browther, § 9) — ouvrir le
///   navigateur et le refermer ne prouve rien.
///
/// ⚠️ **Seuls les jours qui SUIVENT la saisie du code comptent** (§ 12.8 : la
/// validation ne compte qu'après la saisie). Un par jour local, jamais deux fois
/// (`eventKey` = `default:<jour>`, le service déduplique aussi).
public struct DefaultBrowserDays: Codable, Equatable, Sendable {
  /// Jours locaux où le défaut a été PROUVÉ.
  public var proofDays: [String] = []
  /// Jours locaux où une vraie page a fini de charger.
  public var browsingDays: [String] = []
  /// Jours déjà déclarés au service.
  public var reportedDays: [String] = []

  /// On ne garde que ce qui peut encore servir : un filleul valide en quelques
  /// jours, et un registre qui grandirait sans fin n'apprendrait rien de plus.
  static let keptDays = 60

  public init() {}

  public mutating func recordProof(on date: Date = Date()) {
    Self.insert(ReferralDate.localDayKey(date), into: &proofDays)
  }

  public mutating func recordBrowsing(on date: Date = Date()) {
    Self.insert(ReferralDate.localDayKey(date), into: &browsingDays)
  }

  public mutating func markReported(_ day: String) {
    Self.insert(day, into: &reportedDays)
  }

  public func hasProof(on date: Date) -> Bool {
    proofDays.contains(ReferralDate.localDayKey(date))
  }

  /// Les jours à déclarer, du plus ancien au plus récent : prouvés ET
  /// navigués, depuis la saisie du code, pas encore déclarés.
  public func daysToReport(redeemedAt: Date?, limit: Int = 10, calendar: Calendar = .current) -> [String] {
    let from = redeemedAt.map { ReferralDate.localDayKey($0, calendar: calendar) }
    let browsing = Set(browsingDays)
    let reported = Set(reportedDays)
    return proofDays
      .filter { browsing.contains($0) && !reported.contains($0) }
      .filter { day in from.map { day >= $0 } ?? true }
      .sorted()
      .prefix(limit)
      .map { $0 }
  }

  /// L'instant à déclarer pour un jour : midi LOCAL — ⚠️ le service compte des
  /// journées UTC, et midi reste dans la même date UTC pour tous les fuseaux
  /// de ±11 h.
  public static func occurredAt(day: String, calendar: Calendar = .current) -> Date? {
    let parts = day.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
  }

  private static func insert(_ day: String, into list: inout [String]) {
    guard !list.contains(day) else { return }
    list.append(day)
    list.sort()
    if list.count > keptDays { list.removeFirst(list.count - keptDays) }
  }
}

/// Le parrainage existe-t-il dans CE binaire ? — l'interrupteur de lancement.
///
/// ## Pourquoi un interrupteur, et pourquoi dans le CODE
///
/// Le flow est ÉTEINT dans les builds de l'App Store tant que `inStoreBuilds`
/// vaut `false` — une ligne, visible dans git, que Karim bascule le jour du
/// lancement. Allumé ailleurs (builds de dev installés sur l'iPhone), pour la
/// recette. ⚠️ **TestFlight porte le binaire de production** (§ 12.28) : il y
/// est éteint aussi.
///
/// 🔴 **« Inviter OU payer » est ce qui rend le dispositif conforme** (§ 8,
/// Apple 3.2.2) : un écran qui ne dirait que « partage pour débloquer » serait
/// un rejet net. D'où la seconde condition : sans vrai paiement dans le
/// binaire, rien dans le store.
public enum ReferralLaunch {
  /// ⛔ Ne passer à `true` que le jour du lancement, sur décision de Karim.
  public static let inStoreBuilds = false

  /// ⚠️ **Sawtunaa est-il sorti de « encore en développement » ?** (§ 9) Le
  /// mois offert ne démarre qu'à sa finalisation : l'annonce (écran 0), qui
  /// lance le compteur, attend ce jour-là. D'ici là tout est ouvert (§ 12.11),
  /// et le reste du flow tourne — code, invitations, écran 6, validation.
  /// ⛔ À basculer en même temps que le retrait de l'encadré « encore en
  /// développement » de Sawtunaa, jamais avant — et, le même jour,
  /// `BrowtherSurfacesRules.feedbackAfterBrowsingDays` 3 → 4 : l'avis doit
  /// venir strictement APRÈS l'annonce (3ᵉ jour) et avant la note (7ᵉ)
  /// (`SURFACES-COMMUNES.md` § 2.2). Tant que l'annonce n'existe pas, décaler
  /// l'avis ne ferait que le retarder pour rien.
  public static let extrasReleased = false

  public static func isEnabled(isStoreBuild: Bool, storeBillingReady: Bool) -> Bool {
    guard isStoreBuild else { return true }
    return inStoreBuilds && storeBillingReady
  }
}
