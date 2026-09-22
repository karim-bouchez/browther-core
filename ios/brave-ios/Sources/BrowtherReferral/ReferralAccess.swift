// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Ce que l'app a le droit d'ouvrir — `docs/PARRAINAGE.md` § 4 et § 7.4 :
/// **statut effectif = max(accès payé, couverture du parrainage)**.
///
/// 🔴 **Trois états, jamais deux.** Tant qu'on ne sait pas, on n'affiche NI la
/// pause NI une sollicitation : un écran qui « choisit » pendant qu'il ne sait
/// pas est un écran qui clignote.
///
/// 🔴 **Sens de la panne : OUVERT.** Jamais interrogé ⇒ tout est ouvert ;
/// service injoignable ⇒ dernier statut connu. ⛔ Interdit permanent (§ 11.2) :
/// on ne bloque jamais quelqu'un à cause d'une panne serveur.
public struct AccessState: Equatable, Sendable {
  /// `true` = les fonctionnalités supplémentaires sont ouvertes.
  public var unlocked: Bool
  public var lifetime: Bool
  /// Fin de la couverture, `nil` si à vie ou si rien n'a jamais couvert.
  public var until: Date?
  public var source: AccessSource
  /// ⭐ `false` tant que la réponse du service n'est pas arrivée.
  public var known: Bool
  /// Le mois de l'annonce n'a pas démarré et rien d'autre ne couvre : tout est
  /// ouvert. Sert au libellé de l'écran 6.
  public var beforeTrial: Bool

  /// Ce qu'on vaut tant qu'on ne sait pas — ⛔ ne jamais mettre en pause ici.
  public static let unknown = AccessState(
    unlocked: true,
    lifetime: false,
    until: nil,
    source: .none,
    known: false,
    beforeTrial: false
  )

  public init(
    unlocked: Bool,
    lifetime: Bool,
    until: Date?,
    source: AccessSource,
    known: Bool,
    beforeTrial: Bool
  ) {
    self.unlocked = unlocked
    self.lifetime = lifetime
    self.until = until
    self.source = source
    self.known = known
    self.beforeTrial = beforeTrial
  }

  /// 🔴 **Avant l'annonce, RIEN n'est en pause** (§ 12.11). Le service ne dit
  /// que ce qui COUVRE : un sujet neuf y est `unlocked: false, source: none`,
  /// et le lire tel quel mettait tout nouveau venu en pause dès l'arrivée — un
  /// paywall à l'installation (⛔ § 11.2).
  ///
  /// ⚠️ `trial.startedAt` est le seul signal : dans `access`, une couverture
  /// tombée ne se distingue pas d'une couverture qui n'a jamais existé.
  public init(status: ReferralStatus?) {
    guard let status else {
      self = .unknown
      return
    }
    let beforeTrial = status.trial.startedAt == nil && status.access.source == .none
    self.init(
      unlocked: status.access.unlocked || beforeTrial,
      lifetime: status.access.lifetime,
      until: ReferralDate.parse(status.access.until),
      source: status.access.source,
      known: true,
      beforeTrial: beforeTrial
    )
  }

  /// Les fonctionnalités supplémentaires sont-elles en pause **maintenant** ?
  ///
  /// ⚠️ On recalcule sur l'horloge locale plutôt que de croire `unlocked` : le
  /// statut peut dater de plusieurs heures (cache), et une couverture qui
  /// tombe pendant que l'app est ouverte doit se voir. ⛔ Mais un statut
  /// inconnu ne met jamais en pause, et « avant l'annonce » non plus.
  public func isPaused(now: Date = Date()) -> Bool {
    if !known || lifetime || beforeTrial { return false }
    guard let until else { return !unlocked }
    return until <= now
  }

  /// Jours entiers restants avant la fin de la couverture (⌈…⌉, jamais négatif).
  public func daysLeft(now: Date = Date()) -> Int? {
    guard known, !lifetime, let until else { return nil }
    let seconds = until.timeIntervalSince(now)
    if seconds <= 0 { return 0 }
    return Int((seconds / 86_400).rounded(.up))
  }
}

extension ReferralStatus {
  /// ⭐ « Qui a payé n'est plus jamais sollicité » (§ 4, absolu).
  ///
  /// ⚠️ Un abonnement **résilié mais encore courant** n'en fait pas partie :
  /// c'est précisément le cas de rappel `subscription_cancelled` (§ 3.3).
  public var isSubscriberAtPeace: Bool {
    subscription.active && subscription.willRenew
  }

  /// 🔴 **Statut effectif = max(accès payé LOCAL, couverture du service)**
  /// (§ 7.4). L'achat App Store est connu de l'appareil avant le service : le
  /// webhook arrive quelques secondes après — et JAMAIS pour un abonnement
  /// restauré sur une autre identité. ⚠️ `willRenew` vient aussi de l'appareil :
  /// un abonnement résilié mais courant ne doit pas passer pour « en paix ».
  public func merging(entitlement: LocalEntitlement?) -> ReferralStatus {
    guard let entitlement, entitlement.active, !subscription.active else { return self }
    var merged = self
    merged.access.unlocked = true
    merged.access.source = .paid
    if let until = entitlement.until {
      merged.access.until = ReferralDate.string(until)
    }
    merged.subscription = Subscription(
      active: true,
      everPaid: true,
      willRenew: entitlement.willRenew,
      until: entitlement.until.map(ReferralDate.string)
    )
    return merged
  }
}

/// Ce que l'App Store dit de l'abonnement, sur CET appareil.
public struct LocalEntitlement: Equatable, Sendable {
  public var active: Bool
  public var willRenew: Bool
  public var until: Date?

  public init(active: Bool, willRenew: Bool, until: Date?) {
    self.active = active
    self.willRenew = willRenew
    self.until = until
  }
}

/// Ce que l'écran Parrainage dit de la couverture — une étiquette pour CHAQUE
/// cas connu, « avant l'annonce » compris (§ 12.11 : sinon l'écran reste en
/// chargement pour tout nouveau venu).
public enum CoverageLabel: Equatable, Sendable {
  case lifetime
  case paid(renews: Bool, until: Date?)
  case paused
  case until(Date)
  case offered

  public init(status: ReferralStatus, access: AccessState, now: Date = Date()) {
    if access.lifetime {
      self = .lifetime
    } else if status.subscription.active {
      self = .paid(
        renews: status.subscription.willRenew,
        until: ReferralDate.parse(status.subscription.until)
      )
    } else if access.isPaused(now: now) {
      self = .paused
    } else if let until = access.until, !access.beforeTrial {
      self = .until(until)
    } else {
      self = .offered
    }
  }
}

/// L'état que montre le composant « fonctionnalités » (§ 2.2) : Offert 1 mois ·
/// Jusqu'au … · En pause dans N j · En pause · Inclus.
public enum ExtrasState: Equatable, Sendable {
  case offered
  case until(Date)
  case soon(days: Int)
  case paused
  case included

  /// L'état du MOMENT, pour la liste du (i) de l'écran 6.
  public init(status: ReferralStatus, access: AccessState, now: Date = Date()) {
    if access.lifetime || status.subscription.active {
      self = .included
    } else if access.isPaused(now: now) {
      self = .paused
    } else if let left = access.daysLeft(now: now), left <= ReferralPrompt.reminderStages.max() ?? 10 {
      self = .soon(days: left)
    } else if let until = access.until, !access.beforeTrial {
      self = .until(until)
    } else {
      self = .offered
    }
  }
}
