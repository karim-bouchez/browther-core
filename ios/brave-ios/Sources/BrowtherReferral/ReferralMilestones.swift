// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Les paliers du parrainage — `docs/PARRAINAGE.md` § 5.1.
///
/// | Invitations validées | Récompense | Cumul |
/// |---|---|---|
/// | 1  | 1 mois           | 1     |
/// | 3  | +1 mois de bonus | 4     |
/// | 5  | +3 mois de bonus | 9     |
/// | 7  | +5 mois de bonus | 16    |
/// | 10 | **à vie**        | à vie |
///
/// ⭐ **Le barème se LIT dans le statut** (`milestones.bonuses` + `lifetimeAt`,
/// brief B bis), ⛔ il ne se recopie pas : c'est le service qui crédite, et un
/// barème recopié finirait par dire autre chose que lui. `common` n'est que le
/// repli d'un statut qui ne le porte pas (aucun statut reçu).
///
/// La jauge (écrans 2b, 4, 6) est un **jouet** : on la tire pour voir ce que
/// rapporteraient plus d'invitations, sans rien enregistrer. ⛔ Jamais pour
/// créditer.
public struct MilestoneScale: Equatable, Sendable {
  /// Les bonus, croissants. La base (1 mois par invitation validée) n'y figure pas.
  public var bonuses: [MilestoneBonus]
  /// Invitations validées qui débloquent l'accès à vie.
  public var lifetimeAt: Int

  public init(bonuses: [MilestoneBonus], lifetimeAt: Int) {
    self.bonuses = bonuses
    self.lifetimeAt = lifetimeAt
  }

  public static let common = MilestoneScale(
    bonuses: [
      MilestoneBonus(at: 3, months: 1),
      MilestoneBonus(at: 5, months: 3),
      MilestoneBonus(at: 7, months: 5),
    ],
    lifetimeAt: 10
  )

  /// Le barème du statut, s'il est lisible — sinon le commun. ⚠️ Un barème
  /// incohérent (bonus au-delà de « à vie », valeurs négatives) est ÉCARTÉ
  /// plutôt qu'affiché : une jauge qui promettrait n'importe quoi serait pire
  /// qu'une jauge au barème commun.
  public init(status: ReferralStatus?) {
    guard let status, let bonuses = status.milestones.bonuses, status.milestones.lifetimeAt >= 2
    else {
      self = .common
      return
    }
    let lifetimeAt = status.milestones.lifetimeAt
    let clean = bonuses
      .filter { $0.at > 1 && $0.at < lifetimeAt && $0.months > 0 }
      .sorted { $0.at < $1.at }
    guard clean.count == bonuses.count else {
      self = .common
      return
    }
    self.init(bonuses: clean, lifetimeAt: lifetimeAt)
  }

  /// Les seuls mois de BONUS gagnés avec `n` invitations validées — « dont +X ».
  public func bonusMonths(for n: Int) -> Int {
    bonuses.filter { $0.at <= n }.reduce(0) { $0 + $1.months }
  }

  /// Total des mois gagnés avec `n` invitations validées (hors « à vie »).
  public func totalMonths(for n: Int) -> Int {
    n <= 0 ? 0 : n + bonusMonths(for: n)
  }

  public struct Next: Equatable, Sendable {
    public var at: Int
    public var bonusMonths: Int
    public var remaining: Int
    public var lifetime: Bool
  }

  /// Le prochain palier à viser. `nil` quand l'accès à vie est déjà atteint.
  public func next(after validated: Int) -> Next? {
    if validated >= lifetimeAt { return nil }
    if let bonus = bonuses.first(where: { $0.at > validated }) {
      return Next(at: bonus.at, bonusMonths: bonus.months, remaining: bonus.at - validated, lifetime: false)
    }
    return Next(at: lifetimeAt, bonusMonths: 0, remaining: lifetimeAt - validated, lifetime: true)
  }

  /// Ce que la jauge affiche pour une position donnée — § 2.2 : « Si j'invite
  /// N proches, je gagne M mois, dont +X de bonus ». Au palier « à vie », ⭐ il
  /// n'y a plus de nombre de mois : c'est « à vie », et rien d'autre.
  public struct Reading: Equatable, Sendable {
    public var invitations: Int
    public var months: Int
    public var bonusMonths: Int
    public var lifetime: Bool
  }

  public func reading(at invitations: Double) -> Reading {
    let n = max(0, min(lifetimeAt, Int(invitations.rounded())))
    if n >= lifetimeAt {
      return Reading(invitations: n, months: 0, bonusMonths: 0, lifetime: true)
    }
    return Reading(invitations: n, months: totalMonths(for: n), bonusMonths: bonusMonths(for: n), lifetime: false)
  }

  /// Le palier qu'une invitation validée a fait franchir, d'après les mois
  /// qu'elle a crédités (la ligne ★ de « Mes invitations ») : le service marque
  /// `milestone` quand le mois porte un bonus, et `creditedMonths` = 1 + ce
  /// bonus. `nil` si rien ne correspond — la ligne ★ ne s'invente pas.
  public func milestone(forCredit creditedMonths: Int) -> MilestoneBonus? {
    bonuses.first { $0.months == creditedMonths - 1 }
  }

  // MARK: - La démo de la jauge (§ 12.4)

  /// **La démo** : le curseur se tire tout seul **à chaque fois qu'une jauge
  /// est affichée** (écran 6, trois façons, écran 4), **jusqu'au jour où la
  /// personne l'a tiré ELLE-MÊME jusqu'au bout** — « à vie », là où partent
  /// les confettis. À partir de là, plus jamais de démo, nulle part (règle de
  /// Karim, 2026-09-21). ⚠️ Toucher la jauge sans aller au bout ne suffit PAS.
  ///
  /// Jusqu'où elle tire : **5** (assez loin pour faire apparaître un bonus) ;
  /// au-delà, jusqu'au palier suivant ; `nil` quand il n'y a plus rien à viser.
  public func demoTarget(from rest: Int) -> Int? {
    let target = 5
    if rest < target { return min(target, lifetimeAt) }
    return next(after: rest)?.at
  }

  /// La personne vient-elle de montrer qu'elle a compris ? ⚠️ Au DOIGT
  /// seulement : la démo qui monte, ou une invitation validée qui fait bouger
  /// la jauge, ne disent rien de ce qu'elle a vu.
  public func understood(value: Int, byHand: Bool) -> Bool {
    byHand && value >= lifetimeAt
  }
}

// MARK: - Les invitations qu'on MONTRE

public enum ReferralInvitations {
  /// 🔴 **On n'invente rien** (§ 12.1) : une invitation n'existe, pour la
  /// personne, qu'à partir du moment où un proche a UTILISÉ son code
  /// (`installed`, puis `validated`). ⛔ Pas l'état `sent`. Les plus récentes
  /// d'abord (le service les rend dans l'ordre de création).
  public static func known(_ items: [InvitationItem]) -> [InvitationItem] {
    items.filter { $0.status != .sent }.reversed()
  }

  /// Les JOURS qui restent à une invitation EN COURS — « encore 2 jours avec
  /// Browther par défaut » (§ 5.3). `nil` = validée, ou progression inconnue.
  /// ⚠️ Jamais 0 tant qu'elle n'est pas validée : « encore 0 jour » se lirait
  /// comme un bug.
  public static func daysLeft(_ item: InvitationItem) -> Int? {
    guard item.status == .installed, let progress = item.progress else { return nil }
    return daysLeft(progress)
  }

  public static func daysLeft(_ progress: ValidationProgress?) -> Int? {
    guard let progress else { return nil }
    return max(1, Int((progress.target - progress.current).rounded(.up)))
  }

  /// Celle qui est la plus près d'être validée — le rappel « en bonne voie ».
  public static func closestDaysLeft(_ items: [InvitationItem]) -> Int? {
    items.compactMap(daysLeft).min()
  }

  /// La part accomplie, de 0 à 1 (la barre de la carte du filleul).
  public static func ratio(_ progress: ValidationProgress?) -> Double {
    guard let progress, progress.target > 0 else { return 0 }
    return max(0, min(1, progress.current / progress.target))
  }
}
