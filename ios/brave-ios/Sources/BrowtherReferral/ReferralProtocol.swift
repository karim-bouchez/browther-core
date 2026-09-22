// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Le contrat avec le service de parrainage — `docs/PARRAINAGE.md` § 7 et
/// § 10.3, contrat détaillé dans `referral/docs/API.md`.
///
/// ⚠️ **Ce fichier ne décide de rien** : il traduit les réponses du service en
/// types. Les règles vivent dans `ReferralAccess` (ce qui est ouvert),
/// `ReferralMilestones` (les paliers) et `ReferralPrompt` (quand solliciter).
///
/// ⛔ **Aucun texte utilisateur ici** : le service renvoie un *cas* de rappel,
/// l'app choisit la phrase.
///
/// 🔴 **Le mot `referral` est déjà pris dans le fork** (`brave_referrals`, le
/// programme de codes promo d'installation de Brave, et `ReferralData` côté
/// iOS) : tout ce qui est à nous vit dans le module `BrowtherReferral`, sous
/// des clés `browther.referral.*` — ⛔ jamais mélangé avec `Growth/URP`.

public enum ReferralPlatform: String, Codable, Sendable {
  case ios, android, web, desktop
}

public enum AccessSource: String, Codable, Sendable {
  case lifetime, paid, referral, none
}

public enum InvitationStatus: String, Codable, Sendable {
  case sent, installed, validated
}

public struct ValidationProgress: Codable, Equatable, Sendable {
  public var current: Double
  public var target: Double
  public var met: Bool

  public init(current: Double, target: Double, met: Bool) {
    self.current = current
    self.target = target
    self.met = met
  }
}

public struct InvitationItem: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var status: InvitationStatus
  public var sentAt: String?
  public var installedAt: String?
  public var validatedAt: String?
  public var creditedMonths: Int
  /// Vrai quand elle a fait franchir un palier — la ligne ★ de l'écran 6.
  public var milestone: Bool
  /// En cours seulement : où en est le critère (« encore 2 jours », § 5.3).
  public var progress: ValidationProgress?

  public init(
    id: String,
    status: InvitationStatus,
    sentAt: String? = nil,
    installedAt: String? = nil,
    validatedAt: String? = nil,
    creditedMonths: Int = 0,
    milestone: Bool = false,
    progress: ValidationProgress? = nil
  ) {
    self.id = id
    self.status = status
    self.sentAt = sentAt
    self.installedAt = installedAt
    self.validatedAt = validatedAt
    self.creditedMonths = creditedMonths
    self.milestone = milestone
    self.progress = progress
  }
}

/// Le cas de rappel choisi par le service (§ 3.3). ⭐ Il dit **quoi** dire,
/// jamais **quand** : c'est l'app qui décide (J−10 / J−3, au moment de mérite).
public enum ReminderCase: String, Codable, Sendable {
  case subscriptionCancelled = "subscription_cancelled"
  case inProgress = "in_progress"
  case noneOpened = "none_opened"
  case earnedMonthsEnding = "earned_months_ending"
}

public struct MilestoneBonus: Codable, Equatable, Sendable {
  public var at: Int
  public var months: Int

  public init(at: Int, months: Int) {
    self.at = at
    self.months = months
  }
}

public struct ReferralStatus: Codable, Equatable, Sendable {
  public struct Access: Codable, Equatable, Sendable {
    public var unlocked: Bool
    public var lifetime: Bool
    public var until: String?
    public var source: AccessSource
  }

  /// ⭐ « Qui a payé n'est plus jamais sollicité » (§ 4), tant que ça court.
  public struct Subscription: Codable, Equatable, Sendable {
    public var active: Bool
    public var everPaid: Bool
    public var willRenew: Bool
    public var until: String?
  }

  /// Le mois de l'annonce (écran 0) — `nil` = pas encore démarré.
  public struct Trial: Codable, Equatable, Sendable {
    public var startedAt: String?
  }

  public struct Referral: Codable, Equatable, Sendable {
    public var code: String
    /// `nil` tant que la régie n'a pas créé le lien : on partage le code seul.
    public var url: String?
    public var clicks: Int?
  }

  public struct Invitations: Codable, Equatable, Sendable {
    public var sent: Int
    public var installed: Int
    public var validated: Int
    public var items: [InvitationItem]
  }

  public struct Milestones: Codable, Equatable, Sendable {
    public struct Next: Codable, Equatable, Sendable {
      public var at: Int
      public var bonusMonths: Int
      public var remaining: Int
      public var lifetime: Bool
    }

    public var validated: Int
    public var monthsEarned: Int
    public var lifetimeAt: Int
    public var next: Next?
    /// Le barème complet du produit (brief B bis) — absent d'un service antérieur.
    public var bonuses: [MilestoneBonus]?
  }

  public struct Reminder: Codable, Equatable, Sendable {
    public var `case`: ReminderCase?
    public var nextCoverageEnd: String?

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      // ⚠️ Un cas inconnu (service plus récent que l'app) vaut « rien à dire »,
      // ⛔ pas un statut illisible : sinon tout le parrainage tomberait.
      let raw = try container.decodeIfPresent(String.self, forKey: .case)
      self.case = raw.flatMap(ReminderCase.init(rawValue:))
      self.nextCoverageEnd = try container.decodeIfPresent(String.self, forKey: .nextCoverageEnd)
    }

    public init(case: ReminderCase?, nextCoverageEnd: String?) {
      self.case = `case`
      self.nextCoverageEnd = nextCoverageEnd
    }
  }

  /// ⭐ Ce que voit celui qui a SAISI un code (§ 5.3). `nil` = pas de parrain.
  /// ⛔ Rien du parrain n'y figure : ni identifiant, ni code, ni date.
  public struct ReferredBy: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
      case installed, validated
    }

    public var status: Status
    public var redeemedAt: String?
    public var validatedAt: String?
    public var progress: ValidationProgress?
  }

  /// Le critère à atteindre côté filleul (§ 5.2).
  public struct Validation: Codable, Equatable, Sendable {
    public var kind: String
    public var event: String
    public var target: Double
  }

  public var product: String
  public var serverTime: String?
  public var access: Access
  public var subscription: Subscription
  public var trial: Trial
  public var referral: Referral
  public var invitations: Invitations
  public var milestones: Milestones
  public var reminder: Reminder
  public var referredBy: ReferredBy?
  public var validation: Validation?
}

/// Les 3 jours conditionnels du moment « partage » (§ 4). ⛔ Ne se disent
/// qu'APRÈS coup, et seulement s'ils ont été offerts.
public struct ShareOutcome: Codable, Equatable, Sendable {
  public struct Grace: Codable, Equatable, Sendable {
    public var granted: Bool
    public var coveredUntil: String?
  }

  public var grace: Grace
}

public enum RedeemRefusal: String, Codable, Sendable {
  case unknownCode = "unknown_code"
  case `self` = "self"
  case sameDevice = "same_device"
  case alreadyRedeemed = "already_redeemed"
  case wrongProduct = "wrong_product"
}

public enum RedeemOutcome: Equatable, Sendable {
  case accepted(monthsGranted: Int, coveredUntil: String?)
  case refused(RedeemRefusal)
}

extension RedeemOutcome: Decodable {
  private enum CodingKeys: String, CodingKey {
    case accepted, monthsGranted, coveredUntil, reason
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if try container.decode(Bool.self, forKey: .accepted) {
      self = .accepted(
        monthsGranted: try container.decodeIfPresent(Int.self, forKey: .monthsGranted) ?? 0,
        coveredUntil: try container.decodeIfPresent(String.self, forKey: .coveredUntil)
      )
      return
    }
    let raw = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
    // Un refus inconnu se lit comme « ce code ne correspond à personne ».
    self = .refused(RedeemRefusal(rawValue: raw) ?? .unknownCode)
  }
}

public struct ProgressOutcome: Decodable, Equatable, Sendable {
  public struct Progress: Decodable, Equatable, Sendable {
    public var current: Double
    public var target: Double
    public var validated: Bool
  }

  public var counted: Bool
  public var progress: Progress?
}

/// 🧪 Une situation COMPLÈTE à poser côté service (`POST /v1/admin/recette`,
/// § 12.18) — un remplacement, jamais une retouche.
public struct RecetteState: Codable, Equatable, Sendable {
  public enum Subscription: String, Codable, Sendable {
    case none, active, cancelled
  }

  public var trialStarted: Bool
  /// Jours de couverture restants ; négatif = déjà tombée ; `nil` = aucune.
  public var daysLeft: Int?
  public var lifetime: Bool
  public var validated: Int
  public var installed: Int
  public var subscription: Subscription
  public var subscriptionDaysLeft: Int

  public init(
    trialStarted: Bool,
    daysLeft: Int?,
    lifetime: Bool = false,
    validated: Int = 0,
    installed: Int = 0,
    subscription: Subscription = .none,
    subscriptionDaysLeft: Int = 30
  ) {
    self.trialStarted = trialStarted
    self.daysLeft = daysLeft
    self.lifetime = lifetime
    self.validated = validated
    self.installed = installed
    self.subscription = subscription
    self.subscriptionDaysLeft = subscriptionDaysLeft
  }

  public func encode(to encoder: Encoder) throws {
    // ⚠️ `daysLeft: null` doit PARTIR (« aucune couverture ») : l'encodage
    // par défaut omettrait la clé, et le service lirait « non précisé ».
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(trialStarted, forKey: .trialStarted)
    if let daysLeft {
      try container.encode(daysLeft, forKey: .daysLeft)
    } else {
      try container.encodeNil(forKey: .daysLeft)
    }
    try container.encode(lifetime, forKey: .lifetime)
    try container.encode(validated, forKey: .validated)
    try container.encode(installed, forKey: .installed)
    try container.encode(subscription, forKey: .subscription)
    try container.encode(subscriptionDaysLeft, forKey: .subscriptionDaysLeft)
  }
}

// MARK: - Dates du service

/// Les dates du service sont en ISO 8601 avec millisecondes
/// (`2026-11-08T10:00:00.000Z`) — ⚠️ `ISO8601DateFormatter` par défaut les
/// refuse : il faut `.withFractionalSeconds`, et accepter aussi sans.
public enum ReferralDate {
  public static func parse(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFraction.date(from: value) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: value)
  }

  public static func string(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  /// Le jour LOCAL (`YYYY-MM-DD`) — ⚠️ pas l'UTC : « une fois par jour » se
  /// vit dans le fuseau de la personne.
  public static func localDayKey(_ date: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }
}
