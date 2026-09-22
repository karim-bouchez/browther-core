// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BrowtherAnalytics
import BrowtherReferral
import Foundation
import Preferences
import Sawtunaa
import Shared
import UIKit

/// L'orchestrateur du parrainage — `docs/PARRAINAGE.md`, brief C (§ 10.4),
/// appliqué avec les leçons des premiers clients (§ 12) ; pendant iOS de
/// `fajrunaa/services/referral/controller.ts`.
///
/// ## Ce qu'il porte, et ce qu'il ne porte pas
///
/// Il porte les GESTES (démarrer le mois, partager, saisir un code) et
/// l'ORCHESTRATION (se présenter au service, retenter, relever les jours du
/// filleul, décider d'un écran sur le Nouvel Onglet). Les RÈGLES vivent dans le
/// module `BrowtherReferral` (pur, testé : `private/scripts/ios-referral-tests`)
/// — ⛔ jamais recopiées ici. Les TEXTES dans `Strings.BrowtherReferral`.
///
/// ## Quatre invariants
///
/// 🔴 **Rien ne touche au chemin de navigation** : aucune requête ne retient
/// un écran, toute erreur du service est avalée.
/// 🔴 **Sens de la panne : ouvert** (§ 7) — dernier statut connu, et sans statut
/// du tout, RIEN n'est en pause (§ 11.2).
/// 🔴 **Trois états, jamais deux** : tant que le statut n'est pas connu, ni
/// pause, ni sollicitation.
/// 🔴 **Un aperçu de recette n'écrit RIEN** (§ 12.7) : ni état, ni verrou, ni
/// mois démarré, ni analytique `paywall_*`.
@MainActor
final class BrowtherReferralController: ObservableObject {
  static let shared = BrowtherReferralController()

  /// Le parrainage existe-t-il dans CE binaire ? (`ReferralLaunch`)
  @Published private(set) var enabled: Bool
  /// Le statut tel que le service l'a rendu (ou le dernier connu).
  @Published private(set) var status: ReferralStatus?
  /// ⭐ Un statut FRAIS de cette session — l'OUVERTURE d'un écran l'exige ; le
  /// cache suffit pour peindre.
  @Published private(set) var fresh = false
  @Published private(set) var prompt: ReferralPromptState
  @Published private(set) var subjectRef: String?
  /// L'intention de la jauge « jouet » : la réponse à « combien penses-tu
  /// pouvoir inviter ? » survit d'un écran à l'autre du MÊME moment (§ 12.20).
  @Published var gaugeIntention: Int?
  /// Le vrai paiement existe dans ce binaire (RevenueCat, § 7.4).
  let storeBilling = ReferralPurchases.isReady
  /// L'abonnement d'après l'APPAREIL (RevenueCat) — connu avant le webhook.
  @Published private(set) var entitlement: LocalEntitlement?
  /// Les deux formules de l'offre, par période (vides dans un build de dev).
  @Published private(set) var packages: [BillingPeriod: RevenueCatPackage] = [:]
  /// La formule choisie : ⭐ l'annuel par défaut (§ 3, écran 7).
  @Published var period: BillingPeriod = .yearly

  private var client: ReferralClient?
  private let storage = ReferralStorage.shared
  private var booted = false
  private var registered = false
  private var registering = false
  private var retryAttempt = 0
  private var lastRefresh: Date?
  private var trialCatchUpFor: String?
  private var reporting = false
  private var foregroundObserver: NSObjectProtocol?

  /// Nouvelles tentatives quand le service ne répond pas — puis au retour au premier plan.
  private static let retryDelays: [TimeInterval] = [2, 5, 15, 60]
  /// Relire le statut au retour au premier plan, pas plus souvent.
  private static let refreshEvery: TimeInterval = 10 * 60
  /// ⭐ Les 3 jours s'annoncent UN PEU APRÈS le partage (§ 12.26).
  static let graceToastDelay: TimeInterval = 1.5

  private init() {
    enabled = ReferralLaunch.isEnabled(
      isStoreBuild: AppConstants.buildChannel == .release,
      storeBillingReady: ReferralPurchases.isReady
    )
    prompt = ReferralStorage.shared.prompt
  }

  // MARK: - Ce que les écrans lisent

  /// 🔴 **max(accès payé LOCAL, couverture du service)** (§ 7.4) : le webhook
  /// arrive quelques secondes après l'achat — et JAMAIS pour un abonnement
  /// restauré sur une autre identité.
  var known: ReferralStatus? {
    status?.merging(entitlement: entitlement)
  }

  /// Les prix à afficher : ceux du store, sinon le repli.
  var prices: ReferralStorePrices { ReferralStorePrices(packages: packages) }

  var access: AccessState {
    guard enabled, subjectRef != nil else { return .unknown }
    return AccessState(status: known)
  }

  var scale: MilestoneScale { MilestoneScale(status: known) }

  func isPaused(now: Date = Date()) -> Bool {
    enabled && extrasReleased && access.isPaused(now: now)
  }

  /// ⭐ **Tant que Sawtunaa n'est pas finalisé, RIEN n'est en pause et rien ne
  /// sollicite** (§ 9 : « d'ici là tout est ouvert ») — ni rappel, ni J0, ni
  /// garde, ni circuit. ⚠️ Même si le service dit le contraire : un filleul
  /// dont le code a démarré les mois AVANT le lancement ne doit pas voir une
  /// pause d'une fonctionnalité qu'on ne lui a jamais annoncée. Seules les
  /// bonnes nouvelles (8, 8 bis) passent.
  var extrasReleased: Bool {
    ReferralLaunch.extrasReleased || recetteExtrasReleased
  }

  /// « Payer » est proposé : ⚠️ seulement quand le vrai paiement existe (iOS
  /// n'a pas de porte factice, § 12.27 : elle est Android).
  var billingAvailable: Bool { storeBilling }

  // MARK: - Le démarrage

  /// Une fois par lancement — idempotent.
  func boot() {
    guard !booted else { return }
    booted = true
    guard enabled else { return }
    let subject = storage.recetteSubject ?? ReferralIdentity.deviceSubject()
    guard let subject else {
      // ⛔ Sans identité stable, personne à qui rattacher un code : tout ouvert.
      enabled = false
      return
    }
    subjectRef = subject
    client = ReferralClient(
      identity: ReferralIdentityBody(product: ReferralProduct.key, subjectRef: subject, platform: .ios)
    )
    status = storage.cachedStatus(for: subject)
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willEnterForegroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.onForeground() }
    }
    Task { await register() }
    Task { await startBilling(subject) }
  }

  // MARK: - Le paiement (RevenueCat, § 7.4)

  private func startBilling(_ subject: String) async {
    guard storeBilling else { return }
    let purchases = ReferralPurchases.shared
    await purchases.configure(subjectRef: subject)
    entitlement = ReferralPurchases.entitlement(of: await purchases.customerInfo())
    packages = await purchases.packages()
    purchases.watch { [weak self] info in
      self?.entitlement = ReferralPurchases.entitlement(of: info)
    }
  }

  enum BuyOutcome {
    case purchased, cancelled, failed
  }

  /// ⭐ L'achat se termine DANS l'app : dès que l'App Store confirme, le circuit
  /// se ferme (payer en est une des trois sorties) et « Merci » s'ouvre. Le
  /// webhook du service suit à son rythme.
  func buy(_ period: BillingPeriod) async -> BuyOutcome {
    guard let package = packages[period] else { return .failed }
    track("billing_checkout_started", ["period": period.rawValue])
    switch await ReferralPurchases.shared.purchase(package) {
    case .purchased(let info):
      track("billing_checkout_completed", ["period": period.rawValue])
      entitlement = ReferralPurchases.entitlement(of: info)
      closeCircuit()
      Task { await refresh() }
      return .purchased
    case .cancelled:
      return .cancelled
    case .failed:
      track("billing_checkout_failed", ["period": period.rawValue])
      return .failed
    }
  }

  /// « Restaurer mes achats » — obligation Apple (§ 8). `true` = un abonnement
  /// est revenu.
  func restorePurchases() async -> Bool {
    let info = await ReferralPurchases.shared.restore()
    entitlement = ReferralPurchases.entitlement(of: info)
    guard entitlement != nil else { return false }
    closeCircuit()
    Task { await refresh() }
    return true
  }

  private func register() async {
    guard let client, !registering else { return }
    registering = true
    defer { registering = false }
    do {
      adopt(try await client.register())
      registered = true
      retryAttempt = 0
      lastRefresh = Date()
      afterFreshStatus()
    } catch {
      // 🔴 Sens de la panne : on garde ce qu'on sait, et on retente — puis au
      // retour au premier plan. ⛔ Jamais une boucle.
      guard retryAttempt < Self.retryDelays.count else { return }
      let delay = Self.retryDelays[retryAttempt]
      retryAttempt += 1
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        Task { await self?.register() }
      }
    }
  }

  /// Relire le statut (tirer pour rafraîchir, retour d'un geste).
  func refresh() async {
    guard let client else { return }
    do {
      adopt(try await client.status())
      lastRefresh = Date()
      afterFreshStatus()
    } catch {
      // Silencieux : sens de la panne.
    }
  }

  func onForeground() {
    guard enabled, client != nil else { return }
    if !registered {
      retryAttempt = 0
      Task { await register() }
      return
    }
    if let lastRefresh, Date().timeIntervalSince(lastRefresh) < Self.refreshEvery { return }
    Task { await refresh() }
  }

  private func adopt(_ next: ReferralStatus) {
    guard let subjectRef else { return }
    status = next
    fresh = true
    storage.saveStatus(next, for: subjectRef)
  }

  private func updatePrompt(_ change: (ReferralPromptState) -> ReferralPromptState) {
    let next = change(prompt)
    guard next != prompt else { return }
    prompt = next
    storage.prompt = next
  }

  /// Ce qui suit chaque statut FRAIS : rattrapages, filleul, photo du jour.
  private func afterFreshStatus() {
    guard let status, let client, let subjectRef else { return }

    // ⭐ Une annonce par INSTALLATION (§ 12.11) : une identité qui arrive APRÈS
    // l'annonce (recette) n'aurait jamais son mois, et resterait « avant
    // l'annonce » pour toujours.
    if prompt.announced == true, status.trial.startedAt == nil, trialCatchUpFor != subjectRef {
      trialCatchUpFor = subjectRef
      Task {
        do {
          adopt(try await client.startTrial())
        } catch {
          trialCatchUpFor = nil
        }
      }
    }
    // Le mois a démarré ailleurs (même trousseau iCloud, autre iPhone) :
    // l'annonce « offert 1 mois » ne serait plus vraie — on la tient pour vue.
    // ⚠️ Pas avant le lancement : l'annonce doit rester à montrer ce jour-là.
    if extrasReleased, ReferralPrompt.announceAlreadyStarted(prompt, status: status) {
      updatePrompt(ReferralPrompt.markAnnounced)
    }
    // Aligner ce qui n'a rien à annoncer (premier statut, filleul qui vient de
    // saisir son code) — ⛔ jamais une validation qu'on n'a pas encore montrée.
    updatePrompt { state in
      var next = state
      if state.seenValidated == nil {
        next = ReferralPrompt.markValidatedSeen(next, validated: status.milestones.validated)
      }
      if !ReferralPrompt.refereeJustValidated(state, referredBy: status.referredBy) {
        next = ReferralPrompt.markRefereeSeen(next, referredBy: status.referredBy)
      }
      return next
    }
    Task { await reportRefereeDays() }
    sendDailySnapshot()
  }

  // MARK: - L'usage (§ 3.1, § 9)

  /// Pages réellement chargées aujourd'hui — le « N-ième onglet du jour ».
  private var pagesToday = (day: "", count: 0)
  /// Le total de musique retirée au premier passage du jour — un retrait de
  /// musique AUJOURD'HUI est l'autre moment de mérite de Browther (§ 3.1).
  private var musicAtDayStart = (day: "", seconds: 0)

  /// Une vraie page web vient de finir de charger dans un onglet normal
  /// (appelé par `BrowtherSurfaces.recordPageLoad`, à chaque fin de navigation).
  func notePageLoaded(now: Date = Date()) {
    boot()
    let today = ReferralDate.localDayKey(now)
    pagesToday = pagesToday.day == today ? (today, pagesToday.count + 1) : (today, 1)
    noteMusicDayStart(today)
    guard enabled else { return }
    updatePrompt { ReferralPrompt.recordBrowsingDay($0, now: now) }
    var days = storage.defaultBrowserDays
    guard !days.browsingDays.contains(today) || !days.hasProof(on: now) else { return }
    days.recordBrowsing(on: now)
    if Self.accurateDefaultToday(now: now) { days.recordProof(on: now) }
    storage.defaultBrowserDays = days
    checkDefaultBrowserIfUseful(now: now)
    Task { await reportRefereeDays() }
  }

  /// ⭐ Un lien `http(s)` arrivé depuis une autre app (WhatsApp, Mail…) : iOS
  /// ne l'envoie qu'au navigateur PAR DÉFAUT — la preuve du jour (§ 9).
  func noteExternalWebURLOpened(now: Date = Date()) {
    boot()
    guard enabled else { return }
    var days = storage.defaultBrowserDays
    guard !days.hasProof(on: now) else { return }
    days.recordProof(on: now)
    storage.defaultBrowserDays = days
    Task { await reportRefereeDays() }
  }

  /// Le résultat de l'API d'Apple, tel que `DefaultBrowserHelper` l'a mis en
  /// cache — ⚠️ seulement s'il a été obtenu AUJOURD'HUI (une preuve, pas un
  /// « probablement »).
  private static func accurateDefaultToday(now: Date) -> Bool {
    guard Preferences.General.isDefaultAPILastResult.value == true,
      let date = Preferences.General.isDefaultAPILastResultDate.value
    else { return false }
    return ReferralDate.localDayKey(date) == ReferralDate.localDayKey(now)
  }

  private var defaultCheckDay: String?

  /// ⭐ Le filleul en cours : une fois par jour, demander à iOS si Browther est
  /// le navigateur par défaut — ⚠️ l'API est RATIONNÉE par Apple, d'où les
  /// conditions : un filleul EN COURS, un jour déjà navigué, pas encore
  /// prouvé, et pas déjà demandé aujourd'hui. Refusée (quota), le jour se
  /// prouvera par un lien reçu d'une autre app.
  private func checkDefaultBrowserIfUseful(now: Date) {
    guard #available(iOS 18.2, *) else { return }
    guard status?.referredBy?.status == .installed else { return }
    let today = ReferralDate.localDayKey(now)
    guard defaultCheckDay != today, !storage.defaultBrowserDays.hasProof(on: now) else { return }
    defaultCheckDay = today
    guard (try? UIApplication.shared.isDefault(.webBrowser)) == true else { return }
    var days = storage.defaultBrowserDays
    days.recordProof(on: now)
    storage.defaultBrowserDays = days
  }

  /// ⭐ Le FILLEUL déclare ses jours « par défaut » au service (§ 5.2, § 9) —
  /// seulement ceux qui SUIVENT la saisie du code, un par jour, jamais deux
  /// fois. Le service déduplique aussi (`eventKey`). ⛔ Rien pour qui n'a pas
  /// de parrain.
  private func reportRefereeDays() async {
    guard let client, !reporting, let referredBy = status?.referredBy, referredBy.status == .installed
    else { return }
    reporting = true
    defer { reporting = false }
    let todo = storage.defaultBrowserDays.daysToReport(
      redeemedAt: ReferralDate.parse(referredBy.redeemedAt),
      limit: ReferralProduct.validationTargetDays + 2
    )
    guard !todo.isEmpty else { return }
    for day in todo {
      guard let occurredAt = DefaultBrowserDays.occurredAt(day: day) else { continue }
      do {
        let outcome = try await client.reportProgress(
          event: ReferralProduct.validationEvent,
          eventKey: "default:\(day)",
          occurredAt: occurredAt
        )
        var days = storage.defaultBrowserDays
        days.markReported(day)
        storage.defaultBrowserDays = days
        if outcome.progress?.validated == true { break }
      } catch {
        // Rattrapé au prochain passage.
        return
      }
    }
    await refresh()
  }

  private func noteMusicDayStart(_ today: String) {
    guard musicAtDayStart.day != today else { return }
    musicAtDayStart = (today, BrowtherStatsReporter.shared.musicSecondsTotal)
  }

  /// Le moment de mérite de Browther (§ 3.1) : la N-ième vraie page du jour,
  /// ou un retrait de musique aujourd'hui — et un seul par jour.
  func isMeritMoment(now: Date = Date()) -> Bool {
    let today = ReferralDate.localDayKey(now)
    noteMusicDayStart(today)
    let pages = pagesToday.day == today ? pagesToday.count : 0
    let music = BrowtherStatsReporter.shared.musicSecondsTotal - musicAtDayStart.seconds
    return pages >= ReferralPrompt.meritPagesPerDay || music >= 60
  }

  // MARK: - Les sollicitations (§ 3)

  enum Pending: Equatable {
    /// Une bonne nouvelle (8, 8 bis) — ⛔ pas une sollicitation.
    case notice(ReferralScreen)
    /// 🔴 Le circuit fermé rouvre tant qu'il n'a pas eu sa réponse (§ 12.16).
    case circuit(ReferralScreen)
    case decision(ReferralPrompt.Solicitation)
  }

  func pending(now: Date = Date(), merit: Bool? = nil) -> Pending? {
    guard enabled, let known, fresh else { return nil }
    let access = AccessState(status: known)
    if ReferralPrompt.newlyValidated(prompt, validated: known.milestones.validated) {
      return .notice(validatedScreen(known))
    }
    if ReferralPrompt.refereeJustValidated(prompt, referredBy: known.referredBy) {
      return .notice(.refereeDone)
    }
    guard extrasReleased else { return nil }
    if let entry = ReferralPrompt.circuitToRestore(prompt, status: known, access: access, now: now) {
      return .circuit(entry == .paused ? .paused : .support(locked: true))
    }
    let decision = ReferralPrompt.decide(
      .init(
        state: prompt,
        status: known,
        access: access,
        atMeritMoment: merit ?? isMeritMoment(now: now),
        extrasReleased: extrasReleased,
        now: now
      )
    )
    return decision.map(Pending.decision)
  }

  private func validatedScreen(_ status: ReferralStatus) -> ReferralScreen {
    let latest = status.invitations.items
      .filter { $0.status == .validated }
      .sorted { ($0.validatedAt ?? "") < ($1.validatedAt ?? "") }
      .last
    return .validated(
      months: max(1, latest?.creditedMonths ?? 1),
      until: status.access.until,
      lifetime: status.access.lifetime
    )
  }

  /// ⛔ **Jamais deux sollicitations le même jour** (§ 3.4), toutes surfaces
  /// confondues. Browther a un verrou de calme COMMUN (3 jours entre deux
  /// fiches) : le parrainage l'ARME, mais ne s'y soumet que pour la JOURNÉE
  /// (§ 12.25) — ses écrans sont datés, une fiche d'avis attend sans rien perdre.
  static func canSolicitToday(now: Date = Date()) -> Bool {
    guard let last = Preferences.BrowtherSurfaces.lastSolicitationAt.value else { return true }
    return ReferralDate.localDayKey(last) != ReferralDate.localDayKey(now)
  }

  /// ⭐ **Priorité au parrainage** (§ 3.4, question 16) : le coordinateur lui
  /// demande, AVANT d'ouvrir une autre fiche, s'il a quelque chose à dire
  /// maintenant — et lui cède la place.
  func wantsNewTabPage(now: Date = Date()) -> Bool {
    guard let pending = pending(now: now) else { return false }
    if case .decision = pending { return Self.canSolicitToday(now: now) }
    return true
  }

  /// 🧪 Ce qu'une tentative a donné — l'outil de recette doit DIRE pourquoi
  /// rien ne s'est ouvert (§ 12.18).
  enum Attempt: Equatable {
    case shown(String)
    case none
    case lockedToday
    case busy
    case unknown
  }

  /// ⭐ **Une seule fonction décide et ouvre** — le coordinateur l'appelle au
  /// bout de son délai, l'outil de recette sans attendre.
  /// `recette` : l'outil ferme les Paramètres et tente AUSSITÔT — ⚠️ pas
  /// forcément sur un Nouvel Onglet ; il suffit que rien ne soit présenté.
  @discardableResult
  func attemptSolicitation(
    in bvc: BrowserViewController,
    now: Date = Date(),
    merit: Bool? = nil,
    recette: Bool = false
  ) -> Attempt {
    guard enabled, status != nil, fresh else { return .unknown }
    let free = recette ? bvc.presentedViewController == nil : bvc.browtherIsScreenFreeForSolicitation()
    guard free else { return .busy }
    guard let pending = pending(now: now, merit: merit) else { return .none }

    switch pending {
    case .notice(let screen):
      if let known {
        updatePrompt { state in
          if case .validated = screen {
            return ReferralPrompt.markCircuitClosed(
              ReferralPrompt.markValidatedSeen(state, validated: known.milestones.validated)
            )
          }
          return ReferralPrompt.markRefereeSeen(state, referredBy: known.referredBy)
        }
        if case .validated = screen {
          track("referral_validated", ["validated": known.milestones.validated])
        }
      }
      BrowtherReferralPresenter.present(screen, from: bvc)
      return .shown(screen.analyticsName)
    case .circuit(let screen):
      // ⚠️ Ce n'est PAS une nouvelle sollicitation : ni cadence J0, ni `paywall_shown`.
      BrowtherReferralPresenter.present(screen, from: bvc)
      return .shown(screen.analyticsName)
    case .decision(let decision):
      guard Self.canSolicitToday(now: now) else { return .lockedToday }
      BrowtherSurfaces.markSolicitationShown(now: now)
      remember(decision, now: now)
      let screen = ReferralScreen(decision)
      track("paywall_shown", ["screen": screen.analyticsName])
      BrowtherReferralPresenter.present(screen, from: bvc)
      if decision == .announce { startTrialNow() }
      return .shown(screen.analyticsName)
    }
  }

  /// Ce que l'affichage écrit — ⛔ jamais avant d'avoir réellement ouvert l'écran.
  private func remember(_ decision: ReferralPrompt.Solicitation, now: Date) {
    let access = self.access
    let coverageEnd = ReferralDate.parse(status?.reminder.nextCoverageEnd)
    updatePrompt { state in
      switch decision {
      case .announce:
        return ReferralPrompt.markAnnounced(state)
      case .paused:
        let merited = ReferralPrompt.markMeritUsed(state, now: now)
        // ⭐ J0 ouvre le circuit : il survivra au lancement suivant (§ 12.16).
        return ReferralPrompt.markCircuitOpen(
          ReferralPrompt.markPausedShown(merited, pausedSince: coverageEnd ?? access.until, now: now),
          entry: .paused
        )
      case .ending(_, let stage), .reminder(_, let stage, _):
        return ReferralPrompt.markReminderShown(
          ReferralPrompt.markMeritUsed(state, now: now),
          deadline: access.until,
          stage: stage
        )
      }
    }
  }

  /// ⭐ Le mois démarre à l'affichage de l'annonce (§ 4), ⛔ pas à l'installation.
  private func startTrialNow() {
    guard let client else { return }
    Task {
      if let next = try? await client.startTrial() { adopt(next) }
    }
  }

  // MARK: - Les gestes

  /// L'écran O a été vu dans l'INTRODUCTION : ⛔ il ne reviendra jamais.
  func markWelcomeSeen() {
    updatePrompt(ReferralPrompt.markWelcomed)
  }

  /// « Me le rappeler plus tard » sur l'annonce : un TOAST dit ce que « plus
  /// tard » veut dire (0 bis, § 12.9) — ⛔ pas un « tu es sûr ? ». Il reste
  /// jusqu'à ce qu'on le ferme (§ 12.26).
  func announceLaterToast() {
    let until = access.until
    BrowtherReferralToast.show(
      title: Strings.BrowtherReferral.laterTitle,
      body: [
        until.map { Strings.BrowtherReferral.laterBody(Self.formatDate($0)) }
          ?? Strings.BrowtherReferral.laterBodyNoDate,
        Strings.BrowtherReferral.laterWhere,
      ].joined(separator: " "),
      persistent: true
    )
  }

  /// Un partage a ABOUTI (destinataire choisi, ou message copié). ⛔ Ne crée
  /// aucune invitation : il ne sert qu'au moment « partage » des 3 jours (§ 4),
  /// dits APRÈS coup, dans un toast, et seulement s'ils ont été offerts.
  /// ⭐ Inviter EST une des trois sorties du circuit.
  func shareDone(from screen: String, preview: Bool = false) {
    closeCircuit(preview: preview)
    guard let client else { return }
    Task {
      guard let outcome = try? await client.share(), outcome.grace.granted else { return }
      if !preview {
        track("referral_grace", ["moment": "share", "screen": screen])
      }
      let until = ReferralDate.parse(outcome.grace.coveredUntil)
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.graceToastDelay) {
        BrowtherReferralToast.show(
          title: Strings.BrowtherReferral.graceTitle,
          body: [
            Strings.BrowtherReferral.graceBody,
            until.map { Strings.BrowtherReferral.graceStatus(Self.formatDate($0)) },
          ]
          .compactMap { $0 }
          .joined(separator: " "),
          persistent: true
        )
      }
      await refresh()
    }
  }

  /// Le code d'un proche, saisi à la main (introduction ou écran Parrainage).
  /// `nil` = service injoignable.
  func redeem(code: String, source: String) async -> RedeemOutcome? {
    boot()
    guard let client else { return nil }
    do {
      let outcome = try await client.redeem(code: code)
      if case .accepted = outcome {
        track("referral_redeemed", ["source": source])
        await refresh()
      }
      return outcome
    } catch {
      return nil
    }
  }

  /// 🔴 Une des trois sorties a été prise : le circuit ne rouvrira plus (§ 12.16).
  func closeCircuit(preview: Bool = false) {
    guard !preview else { return }
    updatePrompt(ReferralPrompt.markCircuitClosed)
  }

  /// ⭐ **La garde** — `false` ⇒ un **toast** dit que c'est en pause, avec
  /// « Soutenir dev&din » qui ouvre les trois façons ; l'appelant s'arrête.
  /// ⛔ On ne masque JAMAIS le bouton : on l'affiche, et la garde convertit
  /// (§ 12.16). Hors parrainage, statut inconnu, avant l'annonce : `true`.
  /// ⛔ Basarunaa n'a pas de garde, jamais (§ 9).
  func requireExtra(_ feature: ExtraFeature, presentingFrom viewController: UIViewController?) -> Bool {
    guard isPaused() else { return true }
    let title: String
    switch feature {
    case .musicRemoval: title = Strings.BrowtherReferral.lockedMusicRemoval
    }
    BrowtherReferralToast.show(
      title: title,
      body: Strings.BrowtherReferral.lockedBody,
      action: (Strings.BrowtherReferral.supportDevndin, { [weak viewController] in
        self.track("paywall_action", ["screen": "locked", "action": "support"])
        guard let host = viewController ?? BrowtherReferralPresenter.topController() else { return }
        // Ouverte par la personne elle-même : une fenêtre ORDINAIRE (§ 12.16).
        BrowtherReferralPresenter.present(.support(locked: false), from: host)
      }),
      persistent: false
    )
    track("paywall_shown", ["screen": "locked", "feature": feature.rawValue])
    return false
  }

  // MARK: - La pause, pour de vrai (⛔ « blocage seulement affiché », § 11.2)

  /// Le retrait de la musique était ALLUMÉ quand la couverture est tombée :
  /// sans ceci, quelqu'un qui le laisse allumé ne verrait jamais la pause (la
  /// garde ne porte que sur le geste d'allumer). Il s'éteint au Nouvel Onglet
  /// suivant — ⚠️ pas au milieu d'une vidéo : changer ce réglage recharge
  /// l'onglet courant, et sur un Nouvel Onglet ça ne coûte rien —, avec le
  /// toast de la garde (« Soutenir dev&din »). Une fois par pause.
  ///
  /// Validé par Karim le 2026-09-22 (`private/docs/PARRAINAGE.md` § 3). Dormant
  /// tant que Sawtunaa n'est pas finalisé (rien n'est en pause avant l'annonce).
  func enforcePauseIfNeeded(in bvc: BrowserViewController, now: Date = Date()) {
    guard isPaused(now: now), Preferences.Sawtunaa.enabled.value else { return }
    Preferences.Sawtunaa.enabled.value = false
    track("feature_paused", ["feature": ExtraFeature.musicRemoval.rawValue])
    _ = requireExtra(.musicRemoval, presentingFrom: bvc)
  }

  // MARK: - La photo du jour (analytique)

  /// Une par appareil et par jour : couverture, source, jours restants,
  /// validées, en cours, clics, filleul, abonnement — ⛔ ni code, ni lien, ni date.
  private func sendDailySnapshot(now: Date = Date()) {
    guard let known else { return }
    let today = ReferralDate.localDayKey(now)
    guard storage.snapshotDay != today else { return }
    storage.snapshotDay = today
    let access = AccessState(status: known)
    var properties: [String: Any] = [
      "source": access.source.rawValue,
      "paused": access.isPaused(now: now),
      "before_trial": access.beforeTrial,
      "lifetime": access.lifetime,
      "validated": known.milestones.validated,
      "in_progress": known.invitations.installed,
      "subscription": known.subscription.active,
      "referee": known.referredBy?.status.rawValue ?? "none",
    ]
    if let left = access.daysLeft(now: now) { properties["days_left"] = left }
    if let clicks = known.referral.clicks { properties["clicks"] = clicks }
    track("referral_state", properties)
  }

  func track(_ event: String, _ properties: [String: Any]) {
    BrowtherSurfaces.track(event, properties)
  }

  // MARK: - 🧪 Recette (§ 12.18)

  /// 🧪 Faire comme si Sawtunaa était finalisé (en mémoire, le temps d'un
  /// lancement) : sans ça, l'annonce — et donc tout ce qui la suit — ne se
  /// recette pas tant que `ReferralLaunch.extrasReleased` est faux.
  @Published var recetteExtrasReleased = false

  /// 🧪 Lever le verrou du jour (une sollicitation par jour, toutes surfaces).
  func liftDayLockForRecette() {
    Preferences.BrowtherSurfaces.lastSolicitationAt.value = nil
  }

  /// Poser une situation COMPLÈTE côté service et remettre l'appareil en
  /// cohérence avec elle — sinon un « neuf » qui aurait déjà vu l'annonce ne
  /// la reverrait jamais.
  func applyRecette(token: String, state: RecetteState) async throws {
    guard let subjectRef else { throw ReferralUnavailable(status: nil) }
    let recetteClient = ReferralClient(
      identity: ReferralIdentityBody(product: ReferralProduct.key, subjectRef: subjectRef, platform: .ios)
    )
    let next = try await recetteClient.applyRecette(token: token, state: state)
    var fresh = ReferralPromptState()
    fresh.welcomed = true
    fresh.lastDay = prompt.lastDay
    fresh.days = prompt.days
    fresh.announced = state.trialStarted ? true : nil
    fresh = ReferralPrompt.markValidatedSeen(fresh, validated: next.milestones.validated)
    fresh = ReferralPrompt.markRefereeSeen(fresh, referredBy: next.referredBy)
    prompt = fresh
    storage.prompt = fresh
    adopt(next)
    lastRefresh = Date()
  }

  /// 🧪 Oublier ce que l'appareil a vu (annonce, rappels, circuit).
  func forgetPromptForRecette() {
    prompt = ReferralPromptState()
    storage.prompt = prompt
  }

  /// 🧪 Repartir d'un appareil neuf (une identité de recette par-dessus la
  /// vraie), ou revenir à la vraie — prend effet au lancement suivant.
  func setRecetteIdentity(fresh: Bool) {
    storage.recetteSubject = fresh ? UUID().uuidString.lowercased() : nil
    forgetPromptForRecette()
    storage.defaultBrowserDays = DefaultBrowserDays()
  }

  /// 🧪 Compter aujourd'hui comme un jour « par défaut » — ⚠️ un build de dev ne
  /// peut PAS être navigateur par défaut (l'entitlement n'est que sur la
  /// Release) : sans ce geste, la validation du filleul ne se recette pas.
  func recordDefaultDayForRecette(now: Date = Date()) {
    var days = storage.defaultBrowserDays
    days.recordProof(on: now)
    days.recordBrowsing(on: now)
    storage.defaultBrowserDays = days
    Task { await reportRefereeDays() }
  }

  func resetGaugeUnderstoodForRecette() {
    storage.gaugeUnderstood = false
  }

  func debugSummary(now: Date = Date()) -> String {
    let access = self.access
    let days = storage.defaultBrowserDays
    var lines = [
      "Parrainage : \(enabled ? "allumé" : "éteint")",
      "Sujet : \(subjectRef.map { String($0.prefix(8)) + "…" } ?? "—")\(storage.recetteSubject != nil ? " (recette)" : "")",
      "Statut : \(status == nil ? "inconnu" : fresh ? "frais" : "en cache")",
    ]
    if let known {
      lines += [
        "Code : \(known.referral.code)",
        "Couverture : \(access.source.rawValue) \(known.access.until ?? "") \(access.beforeTrial ? "(avant l'annonce)" : "")",
        "En pause : \(access.isPaused(now: now) ? "oui" : "non")",
        "Invitations : \(known.milestones.validated) validées · \(known.invitations.installed) en cours",
        "Filleul : \(known.referredBy.map { "\($0.status.rawValue) \(Int($0.progress?.current ?? 0))/\(Int($0.progress?.target ?? 0))" } ?? "non")",
        "Rappel : \(known.reminder.case?.rawValue ?? "—")",
      ]
    }
    lines += [
      "Annonce vue : \(prompt.announced == true ? "oui" : "non") · jours de navigation : \(prompt.days ?? 0)",
      "Sawtunaa finalisé : \(ReferralLaunch.extrasReleased ? "oui" : "non (pas d'annonce)")",
      "Mérite maintenant : \(isMeritMoment(now: now) ? "oui" : "non") · jour libre : \(Self.canSolicitToday(now: now) ? "oui" : "non")",
      "Jours « par défaut » : prouvés \(days.proofDays.suffix(5).joined(separator: ", "))",
      "   navigués \(days.browsingDays.suffix(5).joined(separator: ", "))",
      "   déclarés \(days.reportedDays.suffix(5).joined(separator: ", "))",
    ]
    switch pending(now: now) {
    case .notice(let screen)?: lines.append("Dû : bonne nouvelle (\(screen.analyticsName))")
    case .circuit(let screen)?: lines.append("Dû : circuit à rouvrir (\(screen.analyticsName))")
    case .decision(let decision)?: lines.append("Dû : \(ReferralScreen(decision).analyticsName)")
    case nil: lines.append("Dû : rien")
    }
    return lines.joined(separator: "\n")
  }

  // MARK: - Utilitaires

  /// Une date de fin, dans la langue de l'app (« 3 novembre »).
  static func formatDate(_ date: Date, withYear: Bool = false) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "fr")
    formatter.setLocalizedDateFormatFromTemplate(withYear ? "d MMMM y" : "d MMMM")
    return formatter.string(from: date)
  }
}
