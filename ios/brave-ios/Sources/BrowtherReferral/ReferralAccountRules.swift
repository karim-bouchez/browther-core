// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

// Le compte dev&din FACULTATIF — les RÈGLES, pures et testées
// (`private/scripts/ios-referral-tests/run.sh`). Le contrat est commun à
// toutes les apps dev&din (`docs/PARRAINAGE.md` § 7.1, tableau « Le contrat ») ;
// ce fichier est le jumeau de `fajrunaa/lib/referral/account.ts`
// (l'implémentation de référence) et de
// `private/webui/referral/src/core/account.ts` (desktop) : ⛔ un écart entre
// eux est un défaut, pas une variante.
//
// 🔴 Le compte ne porte QUE le parrainage et l'abonnement : code, invitations,
// mois gagnés. ⛔ Jamais l'historique, les favoris ni les onglets.
// Les APPELS vivent dans `ReferralAccount.swift` (`ReferralAuthClient`).

/// Ce que l'auth-service a répondu à un appel fait au nom du compte.
/// `nil` = aucune réponse (réseau coupé, délai).
public struct ReferralAuthReply: Sendable {
  public var status: Int
  public var data: Data

  public init(status: Int, data: Data) {
    self.status = status
    self.data = data
  }

  public init(status: Int, json: String) {
    self.init(status: status, data: Data(json.utf8))
  }

  var object: [String: Any]? {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  static func appNames(_ raw: Any?) -> [String] {
    guard let apps = raw as? [Any] else { return [] }
    return apps.compactMap { ($0 as? [String: Any])?["name"] as? String }.filter { !$0.isEmpty }
  }
}

/// Ce compte peut-il être supprimé d'ICI ? — `GET /api/auth/account/deletable`.
///
/// ⭐ **Se demande AVANT d'envoyer le code** (recette Fajrunaa, 2026-10-07 : un
/// compte qui sert à Darsunaa recevait son code, et n'apprenait le refus
/// qu'après l'avoir saisi — en ayant eu peur, entre-temps, de tout supprimer).
/// ⚠️ `unreachable` et `failed` ne valent PAS « oui » : sans réponse, on
/// n'envoie pas de code.
public enum ReferralDeletability: Equatable, Sendable {
  case deletable
  /// `apps` nomme celles qu'on connaît ; VIDE quand le compte n'est pas né
  /// dans une app à compte facultatif.
  case blocked(apps: [String])
  case unreachable
  case failed

  public init(reply: ReferralAuthReply?) {
    guard let reply else {
      self = .unreachable
      return
    }
    guard reply.status == 200, let object = reply.object, let deletable = object["deletable"] as? Bool else {
      self = .failed
      return
    }
    self = deletable ? .deletable : .blocked(apps: ReferralAuthReply.appNames(object["apps"]))
  }
}

/// Le code de confirmation est parti : `destination` = l'adresse MASQUÉE
/// (« k****@gmail.com »), telle que l'auth-service la rend.
public enum ReferralDeletionCode: Equatable, Sendable {
  case sent(destination: String)
  case unreachable
  case failed

  public init(reply: ReferralAuthReply?) {
    guard let reply else {
      self = .unreachable
      return
    }
    if reply.status == 200, let destination = reply.object?["destination"] as? String, !destination.isEmpty {
      self = .sent(destination: destination)
    } else {
      self = .failed
    }
  }
}

/// Ce que `POST /api/auth/account/delete` a répondu (`docs/AUTH.md`) :
/// - `deleted` — le compte et ce qu'il portait sont supprimés ;
/// - `badCode` — le code de confirmation est faux ou expiré ;
/// - `usedElsewhere` — le compte sert, ou a pu servir, à une app dev&din qui a
///   ses propres données : il se supprime depuis celle-là, ⛔ pas d'ici ;
/// - `unreachable` — un des deux services n'a pas répondu (`422` :
///   l'auth-service n'a pas joint le service de parrainage) : RIEN n'est
///   supprimé, on peut réessayer avec le même code ;
/// - `failed` — le reste (session perdue, erreur du service).
public enum ReferralDeletionOutcome: Equatable, Sendable {
  case deleted
  case badCode
  case usedElsewhere(apps: [String])
  case unreachable
  case failed

  /// ⚠️ `401` dit deux choses (session perdue, code faux) : c'est `error` qui tranche.
  public init(reply: ReferralAuthReply?) {
    guard let reply else {
      self = .unreachable
      return
    }
    let object = reply.object ?? [:]
    switch reply.status {
    case 200:
      self = object["success"] as? Bool == true ? .deleted : .failed
    case 401 where object["error"] as? String == "INVALID_CODE":
      self = .badCode
    case 422:
      self = .unreachable
    case 409:
      self = .usedElsewhere(apps: ReferralAuthReply.appNames(object["apps"]))
    default:
      self = .failed
    }
  }
}

public enum ReferralDeletion {
  public static let codeLength = 6

  /// Les six chiffres du code reçu (espaces et tirets d'un code recopié
  /// retirés) — `nil` s'il en manque.
  public static func normalizeCode(_ raw: String) -> String? {
    let digits = raw.filter { !$0.isWhitespace && $0 != "-" }
    guard digits.count == codeLength, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
    return digits
  }
}

/// Comment NOMMER le compte à l'écran. « Masquer mon adresse » d'Apple donne un
/// relais illisible (`x7k2…@privaterelay.appleid.com`) : on dit « avec Apple »,
/// ce qui rappelle aussi par où se reconnecter — c'est le piège des deux
/// comptes (§ 7.1 : Apple masqué sur un appareil, Google sur l'autre).
public enum ReferralAccountLabel: Equatable, Sendable {
  case email(String)
  case apple
  case unknown

  public init(_ account: ReferralAccount) {
    guard let email = account.email, !email.isEmpty else {
      self = .unknown
      return
    }
    self = email.lowercased().hasSuffix("@privaterelay.appleid.com") ? .apple : .email(email)
  }
}

/// Ce que la personne a à PERDRE avec cet appareil — **par onglet** de l'écran
/// Parrainage. Le compte se propose dans l'onglet de ce qui est en jeu, avec
/// les mots de cet onglet (Karim, 2026-10-07) : dire « mets ton parrainage à
/// l'abri » à quelqu'un qui n'a parrainé personne mais qui est ABONNÉ ne parle
/// de rien, et ne lui dit rien là où est son abonnement.
public enum ReferralAccountStake: String, CaseIterable, Sendable {
  /// Son code est parti (un partage a abouti sur cet appareil), ou il a déjà
  /// servi. ⚠️ Un partage ne crée rien côté service (§ 12.1), mais le code
  /// dicté à des proches, lui, existe : sans compte, les invitations qui
  /// arriveront après un changement d'appareil iraient à un sujet que plus
  /// personne ne peut ouvrir. D'où `sharedOnce`, retenu sur l'appareil.
  case invite
  /// Au moins une invitation en cours ou validée.
  case invitations
  /// Elle a saisi le code d'un proche (son mois offert, sa progression).
  case referee
  /// Un abonnement court.
  case paid
}

public struct ReferralAccountStakes: Equatable, Sendable {
  public var invite: Bool
  public var invitations: Bool
  public var referee: Bool
  public var paid: Bool
  /// Un abonnement a existé, même éteint : il compte pour « quelque chose à
  /// mettre à l'abri », pas pour la rangée de « Soutenir ».
  private var everPaid: Bool

  public init(status: ReferralStatus?, sharedOnce: Bool) {
    let invitations = status?.invitations.items.contains { $0.status != .sent } ?? false
    let earned =
      status.map { $0.access.lifetime || $0.milestones.validated > 0 || $0.milestones.monthsEarned > 0 } ?? false
    self.invite = sharedOnce || invitations || earned
    self.invitations = invitations
    self.referee = status?.referredBy != nil
    self.paid = status?.subscription.active == true
    self.everPaid = status?.subscription.everPaid == true
  }

  public subscript(stake: ReferralAccountStake) -> Bool {
    switch stake {
    case .invite: return invite
    case .invitations: return invitations
    case .referee: return referee
    case .paid: return paid
    }
  }

  /// Y a-t-il quoi que ce soit à mettre à l'abri ? C'est ce qui fait passer le
  /// texte du compte de « retrouver un compte » (qui arrive sur un appareil
  /// neuf n'a rien, par définition) à « mettre à l'abri ».
  /// ⚠️ Le mois de l'annonce seul ne compte pas : tout le monde l'a.
  public var hasSomethingToShelter: Bool {
    invite || invitations || referee || paid || everPaid
  }
}
