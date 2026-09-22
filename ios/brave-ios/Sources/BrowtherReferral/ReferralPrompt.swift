// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Ce qui est persisté entre deux lancements (JSON).
///
/// ⚠️ **Une annonce se voit une fois par INSTALLATION, pas par sujet** (§ 12.11)
/// : cet état vit sur l'appareil.
public struct ReferralPromptState: Codable, Equatable, Sendable {
  /// Jour LOCAL (`YYYY-MM-DD`) du dernier jour de navigation compté.
  public var lastDay: String?
  /// Jours de navigation DISTINCTS (une vraie page chargée) — l'unité d'usage
  /// de Browther (§ 9).
  public var days: Int?
  /// L'écran O a été vu (dans l'introduction) — ⛔ il ne revient jamais.
  public var welcomed: Bool?
  /// L'annonce a été montrée — ⛔ elle ne revient jamais (§ 3, « une seule fois »).
  public var announced: Bool?
  /// La fin de couverture pour laquelle un rappel a déjà été montré (ISO).
  /// ⚠️ On mémorise l'ÉCHÉANCE, pas une date d'affichage : c'est ce qui fait
  /// « une fois par palier et par fin » alors que les échéances se succèdent.
  public var reminderShownFor: String?
  /// Le palier déjà montré pour cette échéance (10 puis 3).
  public var reminderStageShown: Int?
  /// Dernier affichage de l'écran J0 (ISO).
  public var pausedShownAt: String?
  /// Affichages de J0 depuis que la couverture est tombée — pilote la cadence.
  public var pausedShownCount: Int?
  /// L'échéance à laquelle la couverture s'est éteinte — remet la cadence à zéro.
  public var pausedSince: String?
  /// 🔴 **Le circuit des trois façons est OUVERT** (§ 12.16), et l'écran par
  /// lequel on y est entré. Il ne se referme que par une de ses trois sorties —
  /// inviter, payer, une du'a —, ⛔ pas par un redémarrage de l'app.
  /// ⚠️ **Seulement s'il part de J0** : une fenêtre qu'on pouvait fermer n'en
  /// ouvre pas une qu'on ne peut plus fermer.
  public var circuit: Circuit?
  /// Le jour local dont le moment de mérite a déjà servi — un par jour.
  public var meritUsedDay: String?
  /// Le nombre d'invitations validées déjà ANNONCÉ (écran 8). ⚠️ Persisté : le
  /// parrain apprend la validation « à sa prochaine ouverture » (§ 7.3).
  public var seenValidated: Int?
  /// Ce que le FILLEUL a déjà vu de sa propre validation (écran 8 bis, § 5.3).
  public var seenRefereeStatus: SeenReferee?

  public enum Circuit: String, Codable, Sendable {
    case paused, support
  }

  public enum SeenReferee: String, Codable, Sendable {
    case none, installed, validated
  }

  public init() {}
}

/// Quand solliciter — `docs/PARRAINAGE.md` § 3, § 3.1, § 3.2, § 3.3 bis et § 4,
/// avec la ligne Browther du § 10.4.
///
/// | Écran | Quand |
/// |---|---|
/// | **O** Code d'un proche | Dans l'INTRODUCTION (étape à part) — ⛔ jamais d'ici |
/// | **0** Annonce | 3ᵉ jour de navigation — ⚠️ **et seulement quand Sawtunaa est finalisé** (`extrasReleased`) |
/// | **1** J−10 / J−3 | de la **première** fin de couverture (pas de cas de rappel) |
/// | **3** Rappel | J−10 / J−3 de **chaque autre** fin, avec le cas du service |
/// | **2** J0 | la couverture est tombée — J0, +7 j, puis toutes les deux semaines |
///
/// ⛔ **Jamais de paywall à l'ouverture ni en fin d'onboarding** (§ 11.2), et les
/// écrans 1, 2, 3 attendent le **moment de mérite** (§ 3.1 — Browther : après
/// un retrait de musique, ou au N-ième onglet du jour).
/// ⭐ **Qui a payé n'est plus jamais sollicité** (§ 4, absolu).
public enum ReferralPrompt {
  /// Jours de navigation DISTINCTS avant l'annonce (§ 3, écran 0).
  public static let announceAfterDistinctDays = 3

  /// Le moment de mérite « au N-ième onglet du jour » (§ 3.1) : la N-ième
  /// vraie page chargée dans la journée. ⚠️ Pas l'ouverture de l'app — § 3.1 :
  /// jamais pendant, jamais à l'ouverture, juste après que le produit a
  /// rendu service.
  public static let meritPagesPerDay = 5

  /// Les rappels d'une fin de couverture : **J−10 puis J−3**, une fois chacun
  /// par échéance (§ 3.3 bis). ⭐ J−10 parce qu'une invitation met des JOURS à
  /// se valider (installer PUIS 3 jours par défaut). ⛔ Pas de troisième palier :
  /// le pied de J0 promet « jamais plus d'une fois par semaine ».
  public static let reminderStages = [10, 3]

  /// Cadence de l'écran J0 (§ 3.2) : **J0, +7 j, puis toutes les deux
  /// semaines**. ⛔ Ne jamais redescendre sous 7 jours sans changer d'abord le
  /// texte que la personne lit (« jamais plus d'une fois par semaine »).
  public static func pausedGapDays(alreadyShown: Int) -> Int {
    if alreadyShown <= 0 { return 0 }
    if alreadyShown == 1 { return 7 }
    return 14
  }

  // MARK: - Ce que l'usage écrit

  /// Un jour de navigation de plus — une fois par JOUR local au plus.
  public static func recordBrowsingDay(_ state: ReferralPromptState, now: Date = Date()) -> ReferralPromptState {
    let today = ReferralDate.localDayKey(now)
    guard state.lastDay != today else { return state }
    var next = state
    next.lastDay = today
    next.days = (state.days ?? 0) + 1
    return next
  }

  /// Le moment de mérite d'aujourd'hui est-il encore disponible ?
  public static func meritAvailable(_ state: ReferralPromptState, now: Date = Date()) -> Bool {
    state.meritUsedDay != ReferralDate.localDayKey(now)
  }

  // MARK: - La décision

  public enum Solicitation: Equatable, Sendable {
    /// Écran 0 — ⭐ l'app DOIT démarrer le mois en l'affichant (§ 4).
    case announce
    /// Écran 1 — première fin de couverture, le service n'a rien de plus à dire.
    case ending(daysLeft: Int, stage: Int)
    /// Écran 3 — fins suivantes, avec le cas du § 3.3.
    case reminder(daysLeft: Int, stage: Int, reminderCase: ReminderCase)
    /// Écran 2 — la couverture est tombée.
    case paused
  }

  public struct Input {
    public var state: ReferralPromptState
    public var status: ReferralStatus?
    public var access: AccessState
    /// ⭐ Le produit vient de rendre son service (§ 3.1). Les écrans 1, 2 et 3
    /// ne sortent QUE là ; l'annonce, elle, n'a pas besoin de l'attendre.
    public var atMeritMoment: Bool
    /// ⚠️ Sawtunaa est-il sorti de « encore en développement » ? L'annonce, qui
    /// démarre le mois offert, l'attend (§ 9).
    public var extrasReleased: Bool
    public var now: Date

    public init(
      state: ReferralPromptState,
      status: ReferralStatus?,
      access: AccessState,
      atMeritMoment: Bool,
      extrasReleased: Bool,
      now: Date = Date()
    ) {
      self.state = state
      self.status = status
      self.access = access
      self.atMeritMoment = atMeritMoment
      self.extrasReleased = extrasReleased
      self.now = now
    }
  }

  public static func decide(_ input: Input) -> Solicitation? {
    let state = input.state
    let access = input.access
    let now = input.now

    // ⛔ Tant qu'on ne sait pas, on n'affiche rien (trois états, jamais deux).
    guard access.known, let status = input.status else { return nil }
    // ⭐ Absolu : qui a payé n'est plus jamais sollicité (§ 4).
    if status.isSubscriberAtPeace { return nil }
    // Plus rien à demander à quelqu'un qui a tout gagné.
    if access.lifetime { return nil }

    if state.announced != true {
      // ⚠️ Un mois déjà démarré ailleurs (même identité sur un autre iPhone) :
      // l'annonce « offert 1 mois » ne serait plus vraie. L'appelant la marque
      // vue sans la montrer (`announceAlreadyStarted`).
      if status.trial.startedAt != nil { return nil }
      // ⭐ Browther : le mois offert ne démarre qu'à la finalisation de Sawtunaa.
      guard input.extrasReleased else { return nil }
      return (state.days ?? 0) >= announceAfterDistinctDays ? .announce : nil
    }

    // ⚠️ Tout le reste attend que le produit ait rendu service (§ 3.1).
    guard input.atMeritMoment, meritAvailable(state, now: now) else { return nil }

    if access.isPaused(now: now) {
      return shouldShowPaused(state, now: now) ? .paused : nil
    }

    guard let left = access.daysLeft(now: now), left > 0, let until = access.until else { return nil }

    // Le palier en cours = le plus PETIT de ceux qu'on a atteints (à J−2, c'est
    // le 3, même si le 10 est passé) — et chacun ne sort qu'une fois par fin.
    guard let stage = reminderStage(daysLeft: left) else { return nil }
    let deadline = ReferralDate.string(until)
    let already = state.reminderShownFor == deadline ? state.reminderStageShown : nil
    if let already, already <= stage { return nil }

    if let reminderCase = status.reminder.case {
      return .reminder(daysLeft: left, stage: stage, reminderCase: reminderCase)
    }
    return .ending(daysLeft: left, stage: stage)
  }

  /// Le palier de rappel atteint : le plus petit des paliers ≥ jours restants.
  public static func reminderStage(daysLeft: Int) -> Int? {
    reminderStages.filter { daysLeft <= $0 }.min()
  }

  static func shouldShowPaused(_ state: ReferralPromptState, now: Date) -> Bool {
    let gap = pausedGapDays(alreadyShown: state.pausedShownCount ?? 0)
    guard gap > 0, let shownAt = ReferralDate.parse(state.pausedShownAt) else { return true }
    return now.timeIntervalSince(shownAt) >= Double(gap) * 86_400
  }

  /// Le mois a démarré sans que CET appareil ait montré l'annonce (même
  /// identité sur un autre iPhone, recette) : on la marque vue sans l'afficher
  /// — sinon elle promettrait « offert 1 mois » à quelqu'un dont le mois court.
  public static func announceAlreadyStarted(_ state: ReferralPromptState, status: ReferralStatus?) -> Bool {
    state.announced != true && status?.trial.startedAt != nil
  }

  // MARK: - Les bonnes nouvelles (écrans 8 et 8 bis)

  /// Une invitation a-t-elle abouti depuis la dernière annonce ? ⚠️ Au tout
  /// premier statut (rien de vu), on s'aligne SANS rien annoncer — sinon une
  /// réinstallation ferait fêter des invitations validées depuis des mois.
  public static func newlyValidated(_ state: ReferralPromptState, validated: Int) -> Bool {
    guard let seen = state.seenValidated else { return false }
    return validated > seen
  }

  /// Le filleul vient-il d'être validé ? Seulement s'il était « en cours » la dernière fois.
  public static func refereeJustValidated(_ state: ReferralPromptState, referredBy: ReferralStatus.ReferredBy?) -> Bool {
    state.seenRefereeStatus == .installed && referredBy?.status == .validated
  }

  // MARK: - Ce que l'affichage écrit

  public static func markValidatedSeen(_ state: ReferralPromptState, validated: Int) -> ReferralPromptState {
    var next = state
    next.seenValidated = validated
    return next
  }

  public static func markRefereeSeen(_ state: ReferralPromptState, referredBy: ReferralStatus.ReferredBy?) -> ReferralPromptState {
    var next = state
    switch referredBy?.status {
    case .installed: next.seenRefereeStatus = .installed
    case .validated: next.seenRefereeStatus = .validated
    case nil: next.seenRefereeStatus = ReferralPromptState.SeenReferee.none
    }
    return next
  }

  public static func markWelcomed(_ state: ReferralPromptState) -> ReferralPromptState {
    var next = state
    next.welcomed = true
    return next
  }

  public static func markAnnounced(_ state: ReferralPromptState) -> ReferralPromptState {
    var next = state
    next.announced = true
    return next
  }

  public static func markMeritUsed(_ state: ReferralPromptState, now: Date = Date()) -> ReferralPromptState {
    var next = state
    next.meritUsedDay = ReferralDate.localDayKey(now)
    return next
  }

  /// Un rappel a été montré pour CETTE échéance, à CE palier (10 puis 3).
  public static func markReminderShown(_ state: ReferralPromptState, deadline: Date?, stage: Int) -> ReferralPromptState {
    guard let deadline else { return state }
    var next = state
    next.reminderShownFor = ReferralDate.string(deadline)
    next.reminderStageShown = stage
    return next
  }

  /// L'écran J0 a été montré. ⚠️ Le compteur repart de zéro quand la
  /// couverture s'est rouverte entre-temps (une invitation validée, puis une
  /// nouvelle pause) : sinon quelqu'un qui a déjà vu l'écran trois fois ne le
  /// reverrait plus qu'une fois par quinzaine pour une pause toute neuve.
  public static func markPausedShown(_ state: ReferralPromptState, pausedSince: Date?, now: Date = Date()) -> ReferralPromptState {
    let since = pausedSince.map(ReferralDate.string)
    let restarted = since != nil && state.pausedSince != since
    var next = state
    next.pausedSince = since ?? state.pausedSince
    next.pausedShownAt = ReferralDate.string(now)
    next.pausedShownCount = restarted ? 1 : (state.pausedShownCount ?? 0) + 1
    return next
  }

  /// 🔴 Le circuit des trois façons s'ouvre (J0, puis 2b ouvert depuis lui).
  public static func markCircuitOpen(_ state: ReferralPromptState, entry: ReferralPromptState.Circuit) -> ReferralPromptState {
    guard state.circuit == nil else { return state }
    var next = state
    next.circuit = entry
    return next
  }

  /// Une des trois sorties a été prise (inviter, payer, une du'a) — ou il n'y
  /// a plus rien à demander.
  public static func markCircuitClosed(_ state: ReferralPromptState) -> ReferralPromptState {
    guard state.circuit != nil else { return state }
    var next = state
    next.circuit = nil
    return next
  }

  /// Ce qu'il faut ROUVRIR au lancement : l'écran par lequel le circuit a
  /// commencé. ⛔ Rien tant que le statut n'est pas connu, ⛔ jamais à qui a
  /// payé ou obtenu l'accès à vie entre-temps, et plus rien si la pause elle-même
  /// a disparu (une invitation validée) : le circuit n'a plus d'objet.
  public static func circuitToRestore(
    _ state: ReferralPromptState,
    status: ReferralStatus?,
    access: AccessState,
    now: Date = Date()
  ) -> ReferralPromptState.Circuit? {
    guard let circuit = state.circuit, let status, access.known else { return nil }
    if status.isSubscriberAtPeace || access.lifetime { return nil }
    guard access.isPaused(now: now) else { return nil }
    return circuit
  }
}
