// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Ce que cet appareil retient du partage proposé (dans `ReferralPromptState`).
public struct SharePromptState: Codable, Equatable, Sendable {
  /// Dernier affichage (ISO).
  public var shownAt: String?
  /// Nombre d'affichages — sa parité choisit l'onglet ouvert.
  public var count: Int?
  /// Fermetures d'affilée, sans partage abouti entre deux.
  public var dismissedInRow: Int?
  /// Dernier partage abouti, D'OÙ QU'IL VIENNE (ISO).
  public var sharedAt: String?
  /// « Ne plus me redemander » : jusqu'à la fin de l'abonnement, ou pour toujours.
  public var muted: Muted?
  /// D'où compter les 7 jours quand l'annonce n'a jamais été montrée (quelqu'un
  /// qui a payé avant elle : `trial.startedAt` reste nul) — la première fois que
  /// cet appareil l'a vu dans cet état.
  public var since: String?

  public enum Muted: String, Codable, Sendable {
    case subscription, lifetime
  }

  public init() {}
}

/// **Le partage proposé** — `docs/PARRAINAGE.md` § 12.45 et
/// `docs/PROMPT-partage-propose.md` (décidé par Karim le 2026-10-12). Port de la
/// règle de Darsunaa (`packages/core/src/referral/share-prompt.ts`), premier
/// client recetté le 2026-10-14.
///
/// Depuis le parrainage, plus rien ne proposait de partager l'app à qui est
/// couvert pour des mois : le partage de l'écran Parrainage s'ouvre donc de
/// lui-même, au moment de mérite, avec un titre au-dessus des onglets.
///
/// - 🔴 **L'abonné et l'accès à vie le voient AUSSI** (sans la phrase du gain,
///   avec « Ne plus me redemander ») : d'où une décision SÉPARÉE de
///   `ReferralPrompt.decide`, qui s'arrête à eux dès ses premières lignes.
/// - ⛔ **Il n'est pas daté** : il passe APRÈS tout écran daté, prend le verrou
///   du jour, mais ne fait céder la journée à personne.
/// - ⛔ **Jamais pendant la pause** : J0 y est le créneau de sollicitation.
public enum ReferralSharePrompt {
  /// Première fois : ce nombre de jours après l'annonce (écran 0).
  public static let firstAfterDays = 7
  /// Ensuite : au plus une fois par période — et le silence après un partage abouti.
  public static let gapDays = 30
  /// Après deux fermetures d'affilée, la période s'allonge.
  public static let longGapDays = 60
  public static let dismissalsForLongGap = 2
  /// ⛔ Jamais la même semaine qu'un autre écran — **dans les deux sens** (Karim,
  /// 2026-10-13) : ni 7 jours après un écran, ni 7 jours avant un rappel.
  public static let quietDays = 7

  /// ⭐ Browther (Karim, 2026-10-14) : « le nombre d'heures de musique retirées
  /// ainsi que le nombre de personnes floutées, sauf si on a vraiment très très
  /// peu ». En dessous de ces seuils, la partie se tait.
  public static let minMusicHours = 1
  public static let minPersons = 20

  /// Ce qui change le texte et les sorties (brief § 2.1 et § 2.2).
  public enum Profile: String, Equatable, Sendable {
    /// Des mois offerts ou gagnés : la phrase du gain, « Plus tard ».
    case offered
    /// Un abonnement court : ⛔ pas la phrase du gain, « Ne plus me redemander » en plus.
    case paid
    /// L'accès à vie : idem, et son silence est définitif.
    case lifetime
  }

  /// L'onglet ouvert — `opened_on` de l'analytique.
  public enum Tab: String, Equatable, Sendable {
    case status, message
  }

  public struct Decision: Equatable, Sendable {
    public var profile: Profile
    public var openedOn: Tab
  }

  /// Pourquoi il ne sort pas — rendu à l'outil de recette, qui doit pouvoir dire
  /// « il se tait à raison » plutôt que « il ne se passe rien ».
  public enum Silence: String, Equatable, Sendable {
    case unknown, noMerit = "no_merit", paused, beforeAnnounce = "before_announce", muted
    case tooEarly = "too_early", recentPrompt = "recent_prompt", recentShare = "recent_share"
    case recentScreen = "recent_screen", reminderSoon = "reminder_soon"
  }

  public enum Verdict: Equatable, Sendable {
    case due(Decision)
    case silent(Silence)
  }

  public static func profile(status: ReferralStatus, access: AccessState) -> Profile {
    if access.lifetime { return .lifetime }
    return status.subscription.active ? .paid : .offered
  }

  /// ⭐ **L'onglet ouvert alterne** : « Statut WhatsApp » la première fois,
  /// « Message » la suivante. ⛔ Pas un test sur le prix (§ 11.2). Sans
  /// WhatsApp, l'appelant impose « Message » (`whatsAppInstalled`).
  public static func tab(shownSoFar: Int, whatsAppInstalled: Bool = true) -> Tab {
    guard whatsAppInstalled else { return .message }
    return shownSoFar % 2 == 0 ? .status : .message
  }

  private static func elapsedDays(_ since: String?, _ now: Date) -> Double? {
    guard let date = ReferralDate.parse(since) else { return nil }
    return now.timeIntervalSince(date) / 86_400
  }

  /// La décision, AVEC sa raison quand elle est négative.
  public static func explain(
    state: ReferralPromptState,
    status: ReferralStatus?,
    access: AccessState,
    atMeritMoment: Bool,
    whatsAppInstalled: Bool = true,
    now: Date = Date()
  ) -> Verdict {
    // Trois états, jamais deux.
    guard access.known, let status else { return .silent(.unknown) }

    let profile = profile(status: status, access: access)
    let own = state.sharePrompt ?? SharePromptState()

    if profile == .offered {
      // ⛔ Jamais pendant la pause : J0 y est le créneau de sollicitation.
      if access.isPaused(now: now) { return .silent(.paused) }
      // Avant l'annonce, la personne ne sait pas ce qu'est le parrainage.
      // ⚠️ Browther : l'annonce attend que Sawtunaa soit finalisé (§ 9).
      if access.beforeTrial || state.announced != true { return .silent(.beforeAnnounce) }
    }

    if own.muted == .lifetime && access.lifetime { return .silent(.muted) }
    if own.muted == .subscription && status.subscription.active { return .silent(.muted) }

    guard let sinceStart = elapsedDays(status.trial.startedAt ?? own.since, now) else {
      return .silent(.beforeAnnounce)
    }
    if sinceStart < Double(firstAfterDays) { return .silent(.tooEarly) }

    let gap = (own.dismissedInRow ?? 0) >= dismissalsForLongGap ? longGapDays : gapDays
    if let shown = elapsedDays(own.shownAt, now), shown < Double(gap) { return .silent(.recentPrompt) }
    if let shared = elapsedDays(own.sharedAt, now), shared < Double(gapDays) { return .silent(.recentShare) }
    if let screen = elapsedDays(state.lastScreenAt, now), screen < Double(quietDays) {
      return .silent(.recentScreen)
    }

    // ⚠️ Un abonné en paix n'a pas de rappel à venir : son échéance se renouvelle.
    if !access.lifetime && !status.isPayerAtPeace,
      let left = access.daysLeft(now: now),
      left <= (ReferralPrompt.reminderStages.max() ?? 10) + quietDays
    {
      return .silent(.reminderSoon)
    }

    // ⚠️ En dernier : la recette lit ainsi « il sortirait, au moment de mérite ».
    guard atMeritMoment else { return .silent(.noMerit) }

    return .due(Decision(
      profile: profile,
      openedOn: tab(shownSoFar: own.count ?? 0, whatsAppInstalled: whatsAppInstalled)
    ))
  }

  public static func decide(
    state: ReferralPromptState,
    status: ReferralStatus?,
    access: AccessState,
    atMeritMoment: Bool,
    whatsAppInstalled: Bool = true,
    now: Date = Date()
  ) -> Decision? {
    if case .due(let decision) = explain(
      state: state, status: status, access: access, atMeritMoment: atMeritMoment,
      whatsAppInstalled: whatsAppInstalled, now: now
    ) {
      return decision
    }
    return nil
  }

  // MARK: - Le titre (compteur Browther)

  public struct Headline: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
      /// « Browther a retiré {hours} de musique et flouté {persons} pour toi. »
      case both
      /// « Browther a retiré {hours} de musique pour toi. »
      case music
      /// « Browther a flouté {persons} pour toi. »
      case blur
      /// « Browther t'est utile ? »
      case none
    }
    public var kind: Kind
    public var hours: Int
    public var persons: Int
  }

  /// La phrase au-dessus des onglets — totaux À VIE, ⛔ aucun seuil dans un écran.
  public static func headline(musicSeconds: Int, personsBlurred: Int) -> Headline {
    let hours = max(0, musicSeconds) / 3600
    let persons = max(0, personsBlurred)
    let music = hours >= minMusicHours
    let blur = persons >= minPersons
    let kind: Headline.Kind = music && blur ? .both : music ? .music : blur ? .blur : .none
    return Headline(kind: kind, hours: hours, persons: persons)
  }

  // MARK: - Ce que l'affichage et les gestes écrivent

  /// À chaque statut reçu : pose le départ des 7 jours pour qui n'a jamais vu
  /// l'annonce (abonné, accès à vie), et lève un « Ne plus me redemander » dont
  /// l'abonnement s'est éteint. Rend le MÊME état quand rien ne change.
  public static func sync(
    _ state: ReferralPromptState,
    status: ReferralStatus,
    access: AccessState,
    now: Date = Date()
  ) -> ReferralPromptState {
    var own = state.sharePrompt ?? SharePromptState()
    let before = own
    if status.trial.startedAt == nil, own.since == nil, profile(status: status, access: access) != .offered {
      own.since = ReferralDate.string(now)
    }
    if own.muted == .subscription, !status.subscription.active {
      own.muted = nil
    }
    guard own != before else { return state }
    var next = state
    next.sharePrompt = own
    return next
  }

  /// Le partage proposé vient d'être affiché.
  public static func markShown(_ state: ReferralPromptState, now: Date = Date()) -> ReferralPromptState {
    var own = state.sharePrompt ?? SharePromptState()
    own.shownAt = ReferralDate.string(now)
    own.count = (own.count ?? 0) + 1
    var next = state
    next.sharePrompt = own
    return next
  }

  /// Refermé (« Plus tard », croix, glissé). ⚠️ Refermer APRÈS avoir partagé
  /// n'est pas une fermeture : le partage a eu lieu.
  public static func markDismissed(_ state: ReferralPromptState) -> ReferralPromptState {
    var own = state.sharePrompt ?? SharePromptState()
    if let shared = ReferralDate.parse(own.sharedAt), let shown = ReferralDate.parse(own.shownAt), shared >= shown {
      return state
    }
    own.dismissedInRow = (own.dismissedInRow ?? 0) + 1
    var next = state
    next.sharePrompt = own
    return next
  }

  /// « Ne plus me redemander » — proposé à l'abonné et à l'accès à vie seulement.
  public static func markMuted(_ state: ReferralPromptState, profile: Profile) -> ReferralPromptState {
    guard profile != .offered else { return state }
    var own = state.sharePrompt ?? SharePromptState()
    own.muted = profile == .lifetime ? .lifetime : .subscription
    var next = state
    next.sharePrompt = own
    return next
  }

  /// Un partage a abouti, **d'où qu'il vienne** (écran Parrainage, trois façons,
  /// partage proposé) : 30 jours de silence, et les fermetures repartent de zéro.
  public static func markShareAchieved(_ state: ReferralPromptState, now: Date = Date()) -> ReferralPromptState {
    var own = state.sharePrompt ?? SharePromptState()
    own.sharedAt = ReferralDate.string(now)
    own.dismissedInRow = 0
    var next = state
    next.sharePrompt = own
    return next
  }

  /// Un AUTRE écran du parrainage vient de venir à la personne (annonce,
  /// rappels, J0, invitation validée) : le partage proposé se tait une semaine.
  public static func markReferralScreenShown(_ state: ReferralPromptState, now: Date = Date()) -> ReferralPromptState {
    var next = state
    next.lastScreenAt = ReferralDate.string(now)
    return next
  }

  /// 🧪 Recette : remet le partage proposé en état de sortir, sur l'onglet voulu.
  /// ⚠️ `since` est posé 8 jours en arrière pour qui n'a pas de mois démarré.
  public static func rearmForRecette(_ state: ReferralPromptState, tab: Tab, now: Date = Date()) -> ReferralPromptState {
    var own = SharePromptState()
    own.count = tab == .status ? 0 : 1
    own.since = ReferralDate.string(now.addingTimeInterval(-Double(firstAfterDays + 1) * 86_400))
    var next = state
    next.sharePrompt = own
    next.lastScreenAt = nil
    return next
  }
}
