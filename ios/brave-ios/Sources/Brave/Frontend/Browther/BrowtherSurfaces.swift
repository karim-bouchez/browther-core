// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowtherAnalytics
import Foundation
import Growth
import Onboarding
import Preferences
import Shared

/// État persistant des surfaces communes dev&din (verrou, mérite, avis,
/// notation, « Ce qui a changé ») et les évènements PostHog qui les mesurent.
///
/// La décision vit dans `BrowtherSurfacesRules` (pur) ; ici on lit, on écrit, on
/// émet. Rien ne throw et rien ne touche au chemin de navigation : au pire une
/// fiche vient une fois de trop ou de moins.
///
/// Doc : `private/docs/SURFACES_IOS.md`. Spec : `docs/SURFACES-COMMUNES.md`.
enum BrowtherSurfaces {

  typealias Rules = BrowtherSurfacesRules

  /// L'onboarding est derrière la personne. `undetermined` est résolu au
  /// lancement (`AppDelegate`), il ne reste que `unseen` à écarter.
  static var isOnboardingDone: Bool {
    let state = Preferences.Onboarding.basicOnboardingCompleted.value
    return state == OnboardingState.completed.rawValue
      || state == OnboardingState.skipped.rawValue
  }

  // MARK: - Verrou de calme (§2.1)

  static func isQuiet(now: Date = Date()) -> Bool {
    Rules.isQuiet(
      lastSolicitation: Preferences.BrowtherSurfaces.lastSolicitationAt.value,
      now: now
    )
  }

  /// ⚠️ À appeler quand une fiche est RÉELLEMENT affichée, jamais quand elle
  /// devient éligible : une fiche écartée par la priorité ne doit pas consommer
  /// le silence d'une autre.
  static func markSolicitationShown(now: Date = Date()) {
    Preferences.BrowtherSurfaces.lastSolicitationAt.value = now
  }

  // MARK: - Unité de mérite

  static var browsingDays: Int { Preferences.BrowtherSurfaces.browsingDays.value }

  /// Une vraie page web vient de finir de charger dans un onglet normal.
  /// Appelé à chaque fin de navigation : le travail réel n'a lieu qu'une fois
  /// par jour.
  static func recordPageLoad(now: Date = Date()) {
    let today = Rules.dayKey(now)
    guard
      let next = Rules.browsingDaysAfterPageLoad(
        count: Preferences.BrowtherSurfaces.browsingDays.value,
        lastDay: Preferences.BrowtherSurfaces.lastBrowsingDay.value,
        today: today
      )
    else { return }
    Preferences.BrowtherSurfaces.browsingDays.value = next
    Preferences.BrowtherSurfaces.lastBrowsingDay.value = today
  }

  // MARK: - Coordination

  /// La sollicitation due pour la session qui commence (cf. `Rules`).
  static func pendingSolicitation(now: Date = Date()) -> Rules.Solicitation? {
    Rules.pendingSolicitation(
      .init(
        onboardingDone: isOnboardingDone,
        whatsNewHoldsSession: whatsNewHoldsSession(now: now),
        lastSolicitation: Preferences.BrowtherSurfaces.lastSolicitationAt.value,
        browsingDays: browsingDays,
        feedback: feedbackState,
        lastRatingRequest: lastRatingRequest,
        now: now
      )
    )
  }

  // MARK: - Avis écrit (§3.2)

  enum FeedbackSource: String {
    /// La fiche est venue d'elle-même.
    case spontaneous
    /// Réglages › Nous écrire.
    case permanent
  }

  static var feedbackState: Rules.FeedbackState {
    .init(
      submitted: Preferences.BrowtherSurfaces.feedbackSubmitted.value,
      optedOut: Preferences.BrowtherSurfaces.feedbackOptedOut.value,
      dismissals: Preferences.BrowtherSurfaces.feedbackDismissals.value,
      mutedUntil: Preferences.BrowtherSurfaces.feedbackMutedUntil.value
    )
  }

  /// Le relais passe par PostHog : si la personne a coupé les statistiques,
  /// rien ne partirait — la fiche le dit au lieu d'afficher un « merci » pour
  /// un envoi qui n'a pas eu lieu (même règle que « Signaler ce site »).
  static var canSendFeedback: Bool { Preferences.BrowtherAnalytics.posthogEnabled.value }

  static func noteFeedbackShown(source: FeedbackSource) {
    track("feedback_shown", ["source": source.rawValue, "browsing_days": browsingDays])
  }

  /// Envoie le message. ⚠️ `feedback_submitted` est un CONTRAT avec le worker
  /// (`private/workers/posthog-telegram-webhook/`) : le renommer coupe le relais
  /// en silence. `message` est le SEUL texte libre de toute l'app — c'est lui
  /// qui la met en catégorie App Privacy « User Content ».
  ///
  /// Pas d'accusé de réception : `capture()` ne rend rien. Le SDK persiste sa
  /// file et retente, donc la perte est rare — mais la confirmation ne promet
  /// que « c'est transmis ».
  @discardableResult
  static func submitFeedback(_ raw: String, source: FeedbackSource) -> Bool {
    let message = Rules.sanitizeFeedback(raw)
    guard message.count >= Rules.feedbackMinLength else { return false }
    track(
      "feedback_submitted",
      [
        "message": message,
        "length": message.count,
        "source": source.rawValue,
        // Les builds de développement envoient aussi : le relais l'affiche pour
        // qu'un message de recette ne se lise pas comme un vrai avis.
        "channel": AppConstants.buildChannel.rawValue,
        "locale": Locale.current.identifier,
      ]
    )
    // Quelqu'un attend ce message à l'autre bout : pas de lot de 30 s. Si
    // l'app meurt avant, le SDK a persisté sa file et l'enverra au lancement.
    BrowtherAnalyticsService.shared.flush()
    Preferences.BrowtherSurfaces.feedbackSubmitted.value = true
    Preferences.BrowtherSurfaces.feedbackMutedUntil.value = nil
    return true
  }

  /// Fermée sans envoyer. Seule la venue spontanée recule (7 → 30 → 120 j) :
  /// refermer la ligne des Réglages n'est pas un refus.
  static func noteFeedbackDismissed(source: FeedbackSource, now: Date = Date()) {
    var dismissals = feedbackState.dismissals
    if source == .spontaneous {
      let next = Rules.feedbackStateAfterDismiss(feedbackState, now: now)
      Preferences.BrowtherSurfaces.feedbackDismissals.value = next.dismissals
      Preferences.BrowtherSurfaces.feedbackMutedUntil.value = next.mutedUntil
      dismissals = next.dismissals
    }
    track("feedback_dismissed", ["source": source.rawValue, "dismissals": dismissals])
  }

  /// La personne a ouvert sa messagerie depuis la fiche : elle a pris la
  /// parole, la venue spontanée s'éteint comme après un envoi (§2.6). On ne
  /// sait pas si le mail est parti — mais la redemander serait sourd à ce geste.
  static func noteFeedbackAnsweredByEmail() {
    Preferences.BrowtherSurfaces.feedbackSubmitted.value = true
    Preferences.BrowtherSurfaces.feedbackMutedUntil.value = nil
  }

  /// « Ne plus me demander » — n'éteint que la venue spontanée. La ligne des
  /// Réglages reste : rien ne ferme jamais le seul canal de signalement.
  static func noteFeedbackOptedOut() {
    Preferences.BrowtherSurfaces.feedbackOptedOut.value = true
    Preferences.BrowtherSurfaces.feedbackMutedUntil.value = nil
    track("feedback_opted_out", [:])
  }

  // MARK: - Notation (§3.4)

  /// La plus récente des deux demandes : la nôtre, ou celle héritée de Brave
  /// (`AppReviewManager`, coupé depuis — cf. son garde `Browther:`).
  static var lastRatingRequest: Date? {
    [
      Preferences.BrowtherSurfaces.ratingRequestedAt.value,
      Preferences.Review.lastReviewDate.value,
    ].compactMap { $0 }.max()
  }

  enum RatingSource: String {
    case spontaneous
    case permanent
  }

  /// Demande transmise à l'OS (spontanée) ou fiche App Store ouverte (Réglages).
  /// ⚠️ L'OS ne dit jamais s'il a affiché son dialogue, ni ce qu'on y a fait :
  /// cet évènement mesure la demande, pas l'affichage.
  ///
  /// La date est posée dans les DEUX cas : qui vient d'ouvrir la fiche App Store
  /// de lui-même a très probablement noté — le lui redemander trois jours plus
  /// tard serait sourd à ce geste.
  static func noteRatingRequested(source: RatingSource, now: Date = Date()) {
    Preferences.BrowtherSurfaces.ratingRequestedAt.value = now
    track("rating_requested", ["source": source.rawValue, "browsing_days": browsingDays])
  }

  // MARK: - « Ce qui a changé » (§3.6)

  static var whatsNewState: Rules.WhatsNewState {
    .init(
      seenId: Preferences.BrowtherSurfaces.whatsNewSeenId.value,
      closedId: Preferences.BrowtherSurfaces.whatsNewClosedId.value,
      shownAt: Preferences.BrowtherSurfaces.whatsNewShownAt.value,
      appearances: Preferences.BrowtherSurfaces.whatsNewAppearances.value,
      lastAppearanceAt: Preferences.BrowtherSurfaces.whatsNewLastAppearanceAt.value
    )
  }

  /// Affichage de recette en attente : montré par le prochain Nouvel Onglet,
  /// sans rien écrire ni émettre (§2.8). En mémoire seulement.
  static var whatsNewRehearsal: Rules.WhatsNewRelease?

  /// La release que l'encart doit montrer maintenant, ou `nil`.
  static func whatsNewCard(now: Date = Date()) -> Rules.WhatsNewRelease? {
    Rules.whatsNewCard(
      releases: BrowtherWhatsNewCatalog.releases,
      state: whatsNewState,
      onboardingDone: isOnboardingDone,
      now: now
    )
  }

  static func whatsNewHoldsSession(now: Date = Date()) -> Bool {
    Rules.whatsNewHoldsSession(
      releases: BrowtherWhatsNewCatalog.releases,
      state: whatsNewState,
      onboardingDone: isOnboardingDone,
      now: now
    )
  }

  /// L'encart vient d'apparaître (la cellule est demandée — appelé souvent :
  /// le Nouvel Onglet recharge sa grille à chaque mise en page). Ne compte
  /// qu'une apparition par heure (`Rules.whatsNewStateAfterDisplay`).
  ///
  /// Marqué à l'affichage, pas à la fermeture : qui a vu l'encart l'a vu, le
  /// sens de la panne acceptable est « annoncé une fois de moins », jamais
  /// « harcelé ». Et il prend la place du bandeau « accès anticipé » pour cette
  /// version : les deux ne s'enchaînent pas (un seul encart par mise à jour).
  static func noteWhatsNewDisplayed(_ release: Rules.WhatsNewRelease, now: Date = Date()) {
    let before = whatsNewState
    let after = Rules.whatsNewStateAfterDisplay(before, release: release, now: now)
    guard after != before else { return }
    let prefs = Preferences.BrowtherSurfaces.self
    prefs.whatsNewSeenId.value = after.seenId
    prefs.whatsNewShownAt.value = after.shownAt
    prefs.whatsNewAppearances.value = after.appearances
    prefs.whatsNewLastAppearanceAt.value = after.lastAppearanceAt
    guard before.seenId != release.id else { return }
    Preferences.General.browtherBetaNoticeDismissedVersion.value = currentAppVersion
    track(
      "whats_new_shown",
      [
        "release_id": release.id,
        "source": "spontaneous",
        "lines": release.lines["en"]?.count ?? 0,
      ]
    )
  }

  /// Fermé — `acknowledged` = « J'ai compris » (l'action qui compte pour une
  /// fiche qui ne demande rien : l'avoir lue jusqu'au bouton), sinon la croix.
  static func noteWhatsNewClosed(
    _ release: Rules.WhatsNewRelease,
    acknowledged: Bool,
    now: Date = Date()
  ) {
    Preferences.BrowtherSurfaces.whatsNewClosedId.value = release.id
    var props: [String: Any] = ["release_id": release.id]
    if let shownAt = Preferences.BrowtherSurfaces.whatsNewShownAt.value {
      props["seconds_open"] = Int(max(0, now.timeIntervalSince(shownAt)))
    }
    track(acknowledged ? "whats_new_acknowledged" : "whats_new_dismissed", props)
  }

  /// ⭐⭐ Fin d'onboarding : la release courante est marquée vue ET fermée,
  /// sans jamais être affichée. Rien n'a changé pour quelqu'un qui arrive — tout
  /// est nouveau ; lui servir des correctifs le jour de l'installation décrirait
  /// un produit défaillant à quelqu'un qui n'a rien constaté.
  static func seedWhatsNewAfterOnboarding() {
    guard let id = BrowtherWhatsNewCatalog.releases.first?.id else { return }
    Preferences.BrowtherSurfaces.whatsNewSeenId.value = id
    Preferences.BrowtherSurfaces.whatsNewClosedId.value = id
  }

  static var currentAppVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
  }

  // MARK: - Recette (§2.8)

  /// Photographie lisible de l'état — menu Developer Options.
  static func debugSummary(now: Date = Date()) -> String {
    func format(_ date: Date?) -> String {
      guard let date else { return "—" }
      return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }
    let last = Preferences.BrowtherSurfaces.lastSolicitationAt.value
    let quietUntil = last.map { $0.addingTimeInterval(Rules.quietPeriod) }
    let feedback = feedbackState
    let whatsNew = whatsNewState
    return [
      "Jours de navigation : \(browsingDays) (avis ≥ \(Rules.feedbackAfterBrowsingDays), note ≥ \(Rules.ratingAfterBrowsingDays))",
      "Dernière sollicitation : \(format(last))",
      "Verrou : \(isQuiet(now: now) ? "libre" : "jusqu'au \(format(quietUntil))")",
      "Avis : envoyé \(feedback.submitted ? "oui" : "non") · ne plus demander \(feedback.optedOut ? "oui" : "non") · fermetures \(feedback.dismissals) · muet jusqu'au \(format(feedback.mutedUntil))",
      "Note : dernière demande \(format(lastRatingRequest))",
      "Nouveautés : vue \(whatsNew.seenId ?? "—") · fermée \(whatsNew.closedId ?? "—") · \(whatsNew.appearances)/\(Rules.whatsNewMaxAppearances) apparitions, dernière \(format(whatsNew.lastAppearanceAt))",
      "Onboarding terminé : \(isOnboardingDone ? "oui" : "non")",
      "Due maintenant : \(pendingSolicitation(now: now)?.rawValue ?? "rien")",
    ].joined(separator: "\n")
  }

  /// Remise à zéro complète — équivalent d'une réinstallation pour ces seules
  /// surfaces. Recette uniquement.
  static func resetForRehearsal() {
    let prefs = Preferences.BrowtherSurfaces.self
    prefs.lastSolicitationAt.reset()
    prefs.browsingDays.reset()
    prefs.lastBrowsingDay.reset()
    prefs.feedbackSubmitted.reset()
    prefs.feedbackOptedOut.reset()
    prefs.feedbackDismissals.reset()
    prefs.feedbackMutedUntil.reset()
    prefs.ratingRequestedAt.reset()
    prefs.whatsNewSeenId.reset()
    prefs.whatsNewClosedId.reset()
    prefs.whatsNewShownAt.reset()
    prefs.whatsNewAppearances.reset()
    prefs.whatsNewLastAppearanceAt.reset()
  }

  // MARK: - Analytics

  /// No-op si les statistiques sont coupées (`BrowtherAnalyticsService`).
  static func track(_ event: String, _ properties: [String: Any]) {
    BrowtherAnalyticsService.shared.track(event: event, properties: properties)
  }
}

// MARK: - Préférences

extension Preferences {
  /// Surfaces communes dev&din (`BrowtherSurfaces`).
  enum BrowtherSurfaces {
    /// Dernière sollicitation RÉELLEMENT affichée — le verrou de 3 jours.
    static let lastSolicitationAt = Option<Date?>(
      key: "browther.surfaces.last-solicitation-at",
      default: nil
    )
    /// Cumul des jours distincts de navigation. Ne redescend jamais.
    static let browsingDays = Option<Int>(key: "browther.surfaces.browsing-days", default: 0)
    static let lastBrowsingDay = Option<String>(
      key: "browther.surfaces.last-browsing-day",
      default: ""
    )
    static let feedbackSubmitted = Option<Bool>(
      key: "browther.surfaces.feedback.submitted",
      default: false
    )
    static let feedbackOptedOut = Option<Bool>(
      key: "browther.surfaces.feedback.opted-out",
      default: false
    )
    static let feedbackDismissals = Option<Int>(
      key: "browther.surfaces.feedback.dismissals",
      default: 0
    )
    static let feedbackMutedUntil = Option<Date?>(
      key: "browther.surfaces.feedback.muted-until",
      default: nil
    )
    static let ratingRequestedAt = Option<Date?>(
      key: "browther.surfaces.rating.requested-at",
      default: nil
    )
    static let whatsNewSeenId = Option<String?>(
      key: "browther.surfaces.whats-new.seen-id",
      default: nil
    )
    static let whatsNewClosedId = Option<String?>(
      key: "browther.surfaces.whats-new.closed-id",
      default: nil
    )
    static let whatsNewShownAt = Option<Date?>(
      key: "browther.surfaces.whats-new.shown-at",
      default: nil
    )
    /// Apparitions de l'encart pour la release `whatsNewSeenId` (3 au plus).
    static let whatsNewAppearances = Option<Int>(
      key: "browther.surfaces.whats-new.appearances",
      default: 0
    )
    static let whatsNewLastAppearanceAt = Option<Date?>(
      key: "browther.surfaces.whats-new.last-appearance-at",
      default: nil
    )
  }
}
