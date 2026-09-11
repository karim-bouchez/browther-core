// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Règles PURES des « surfaces communes » dev&din sur Browther iOS : ce qui
/// décide, sans rien lire ni écrire (l'état vit dans `BrowtherSurfaces`).
///
/// Spec transverse : `docs/SURFACES-COMMUNES.md` (repo `docs`), qui ne se
/// re-débat pas ici. Ce fichier n'importe que Foundation pour pouvoir être
/// compilé et testé seul (`private/docs/SURFACES_IOS.md` § Tests).
///
/// ## Les quatre choix propres à Browther
///
/// - **Unité de mérite = jour distinct où une vraie page web a fini de charger
///   dans un onglet normal** (§2.3). Ouvrir l'app sans naviguer ne prouve pas
///   que le navigateur a servi ; y lire des pages, si. C'est un CUMUL, jamais une
///   série (§2.4) : il ne redescend pas.
/// - **Paliers : avis à 3 jours, notation à 7** — mesurés dans PostHog le
///   2026-09-11 (installs iOS sur 90 j, `app_launched` en jours distincts) :
///   39 installs sur 150 ont atteint 3 jours, 23 en ont atteint 7. Un palier
///   plus haut ne toucherait presque personne (le piège Tranquileaty/Darsunaa).
///   ⚠️ Au brief C du parrainage (annonce au 3ᵉ jour), l'avis passera à 4 :
///   son palier doit rester STRICTEMENT entre l'annonce et la notation (§2.2).
/// - **« Ce qui a changé » est un encart du Nouvel Onglet, pas une feuille** :
///   elle prend la place du bandeau « accès anticipé », qui revenait déjà à
///   chaque version (piste du brief). Dans un navigateur, une feuille modale au
///   lancement coupe quelqu'un qui venait taper une adresse.
/// - **Le verrou couvre aussi les callouts de Brave** encore actifs (barre du
///   bas, navigateur par défaut) : ce sont des fiches qui s'ouvrent d'elles-mêmes.
enum BrowtherSurfacesRules {

  static let hour: TimeInterval = 60 * 60
  static let day: TimeInterval = 24 * hour

  // MARK: - Verrou de calme (§2.1)

  /// Une seule sollicitation tous les 3 jours, toutes surfaces confondues.
  static let quietPeriod: TimeInterval = 3 * day

  /// Le silence est-il revenu ? `nil` = jamais rien montré.
  ///
  /// Une horloge reculée (date remise en arrière) prolonge le silence au lieu
  /// de l'abréger : le sens de la panne acceptable est « une sollicitation de
  /// moins », jamais « deux coup sur coup ».
  static func isQuiet(lastSolicitation: Date?, now: Date) -> Bool {
    guard let lastSolicitation else { return true }
    return now.timeIntervalSince(lastSolicitation) >= quietPeriod
  }

  // MARK: - Unité de mérite (§2.3, §2.4)

  /// Clé du jour LOCAL (`yyyy-MM-dd`) : c'est le jour vécu par la personne qui
  /// compte, pas le jour UTC — naviguer à 23 h puis à 1 h, ce sont deux jours.
  static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }

  /// Nouveau compte de jours après un chargement de page, ou `nil` si ce jour
  /// était déjà compté. Ne redescend jamais.
  static func browsingDaysAfterPageLoad(count: Int, lastDay: String, today: String) -> Int? {
    today == lastDay ? nil : max(0, count) + 1
  }

  // MARK: - Avis écrit (§3.2)

  /// Jours de navigation avant que la fiche vienne d'elle-même.
  static let feedbackAfterBrowsingDays = 3

  /// Bornes du message. Le minimum écarte les « ok » et les appuis par erreur ;
  /// le maximum est une borne de SÉCURITÉ, pas de confort : ce texte part dans
  /// un évènement analytique, un champ non borné finit par transporter un
  /// presse-papier entier.
  static let feedbackMinLength = 4
  static let feedbackMaxLength = 1000

  /// Recul après une fermeture sans envoi (§2.6). La dernière valeur SE RÉPÈTE :
  /// qui ferme distraitement en août peut vouloir écrire en décembre.
  static let feedbackDismissMuteDays = [7, 30, 120]

  struct FeedbackState: Equatable {
    /// Un message est parti → plus de venue spontanée (la ligne des Réglages reste).
    var submitted = false
    /// « Ne plus me demander » → éteinte pour de bon (la ligne reste, elle aussi).
    var optedOut = false
    /// Fermetures sans envoi, qui pilotent le recul.
    var dismissals = 0
    /// Rien avant cette date ; `nil` = pas de recul en cours.
    var mutedUntil: Date?
  }

  /// La fiche peut-elle venir d'elle-même ? Ne concerne QUE la venue spontanée :
  /// l'entrée des Réglages n'appelle jamais ceci — qui veut écrire doit pouvoir
  /// écrire, deux fois de suite s'il le faut.
  static func feedbackIsDue(_ state: FeedbackState, browsingDays: Int, now: Date) -> Bool {
    if state.submitted || state.optedOut { return false }
    if browsingDays < feedbackAfterBrowsingDays { return false }
    if let mutedUntil = state.mutedUntil, now < mutedUntil { return false }
    return true
  }

  static func feedbackStateAfterDismiss(_ state: FeedbackState, now: Date) -> FeedbackState {
    var next = state
    next.dismissals = state.dismissals + 1
    let index = min(next.dismissals, feedbackDismissMuteDays.count) - 1
    next.mutedUntil = now.addingTimeInterval(TimeInterval(feedbackDismissMuteDays[index]) * day)
    return next
  }

  /// Normalise le message avant envoi : bords, retours à la ligne en rafale,
  /// longueur. ⚠️ RIEN d'autre — ni filtre ni censure : il doit arriver tel que
  /// la personne l'a écrit, fautes comprises. C'est la seule chose qu'on ait d'elle.
  static func sanitizeFeedback(_ raw: String) -> String {
    var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
    while text.contains("\n\n\n") {
      text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return String(text.prefix(feedbackMaxLength))
  }

  static func isFeedbackSubmittable(_ raw: String) -> Bool {
    sanitizeFeedback(raw).count >= feedbackMinLength
  }

  // MARK: - Notation (§3.4)

  /// Au-dessus du palier de l'avis : on écoute avant de demander (§2.2).
  static let ratingAfterBrowsingDays = 7

  /// L'OS ne dit jamais si la personne a noté ou fermé : on ne peut qu'espacer.
  /// ~120 j ≈ le plafond iOS de 3 affichages par an.
  static let ratingSpacing: TimeInterval = 120 * day

  /// `lastRequest` compte AUSSI la demande héritée de Brave
  /// (`Preferences.Review.lastReviewDate`) : quelqu'un qu'elle a sollicité le
  /// mois dernier ne doit pas l'être de nouveau parce que le code a changé.
  static func ratingIsDue(browsingDays: Int, lastRequest: Date?, now: Date) -> Bool {
    if browsingDays < ratingAfterBrowsingDays { return false }
    guard let lastRequest else { return true }
    return now.timeIntervalSince(lastRequest) >= ratingSpacing
  }

  // MARK: - Coordination (§2.2)

  enum Solicitation: String, Equatable {
    case feedback
    case rating
  }

  struct SessionInput {
    var onboardingDone: Bool
    /// « Ce qui a changé » est due ou vient d'être montrée : elle garde la session.
    var whatsNewHoldsSession: Bool
    var lastSolicitation: Date?
    var browsingDays: Int
    var feedback: FeedbackState
    var lastRatingRequest: Date?
    var now: Date
  }

  /// LA sollicitation due pour cette session, ou `nil`. Un seul endroit décide,
  /// dans l'ordre écrit noir sur blanc : avis → notation (on écoute avant de
  /// demander, §2.2). Pas de partage : le parrainage le remplacera (brief C).
  static func pendingSolicitation(_ input: SessionInput) -> Solicitation? {
    guard input.onboardingDone else { return nil }
    guard !input.whatsNewHoldsSession else { return nil }
    guard isQuiet(lastSolicitation: input.lastSolicitation, now: input.now) else { return nil }
    if feedbackIsDue(input.feedback, browsingDays: input.browsingDays, now: input.now) {
      return .feedback
    }
    if ratingIsDue(
      browsingDays: input.browsingDays,
      lastRequest: input.lastRatingRequest,
      now: input.now
    ) {
      return .rating
    }
    return nil
  }

  // MARK: - « Ce qui a changé » (§3.6)

  struct WhatsNewRelease: Equatable {
    /// Clé de CONTENU posée à la main — jamais le numéro de version. ⛔ Un id
    /// diffusé ne se modifie plus : le changer rouvre l'encart chez tous ceux
    /// qui l'ont déjà lu.
    var id: String
    /// Jour de la diffusion, `yyyy-MM-dd`, écrit à la main avec les lignes.
    /// `nil` = pas de surtitre (un catalogue incomplet ne casse rien).
    var date: String?
    /// Lignes par langue (`fr`, `en`, `ar`… ; `en` sert de repli). 3 à 5.
    var lines: [String: [String]]
  }

  struct WhatsNewState: Equatable {
    /// Dernier id AFFICHÉ (ou marqué par le seed de fin d'onboarding).
    var seenId: String?
    /// Dernier id fermé (croix ou « J'ai compris »).
    var closedId: String?
    /// Première apparition de l'encart pour `seenId` (sert à `seconds_open`).
    var shownAt: Date?
    /// Apparitions comptées pour `seenId` (cf. `whatsNewMaxAppearances`).
    var appearances = 0
    /// Début de la dernière apparition comptée.
    var lastAppearanceAt: Date?
  }

  /// Sans fermeture, l'encart se retire tout seul après 3 apparitions
  /// (décision Karim, 2026-09-11) : il est dans le flux, pas dans une feuille
  /// qu'on balaie, donc qui ne le ferme pas le reverrait à chaque Nouvel Onglet.
  /// Trois fois, c'est l'avoir vu — au-delà, ce serait du bruit.
  static let whatsNewMaxAppearances = 3

  /// Une « apparition », c'est une OCCASION de le voir, pas un onglet : ouvrir
  /// trois Nouveaux Onglets d'affilée n'en fait qu'une. Tout affichage dans
  /// l'heure qui suit une apparition comptée appartient à la même.
  static let whatsNewAppearanceGap: TimeInterval = hour

  /// Sommes-nous dans la fenêtre de la dernière apparition comptée ?
  private static func isWithinAppearance(_ state: WhatsNewState, now: Date) -> Bool {
    guard let last = state.lastAppearanceAt, now >= last else { return false }
    return now.timeIntervalSince(last) < whatsNewAppearanceGap
  }

  /// La release à afficher dans l'encart, ou `nil`.
  ///
  /// - La plus récente UNIQUEMENT, jamais le cumul des versions manquées : un
  ///   mur de texte ne se lit pas, donc pas même la ligne qui concerne la personne.
  /// - Jamais pour un nouvel arrivant : la fin de l'onboarding marque la release
  ///   courante comme vue ET fermée (seed). Un `seenId` absent avec un onboarding
  ///   fait veut dire « installé avant que l'encart existe » : il doit voir la
  ///   première.
  /// - Fermé → plus jamais. Sinon, visible jusqu'à la fin de sa 3ᵉ apparition.
  static func whatsNewCard(
    releases: [WhatsNewRelease],
    state: WhatsNewState,
    onboardingDone: Bool,
    now: Date
  ) -> WhatsNewRelease? {
    guard onboardingDone, let latest = releases.first else { return nil }
    if state.seenId != latest.id { return latest }
    if state.closedId == latest.id { return nil }
    if isWithinAppearance(state, now: now) { return latest }
    return state.appearances < whatsNewMaxAppearances ? latest : nil
  }

  /// Nouvel état après un affichage de l'encart. Idempotent dans une même
  /// apparition ; une release neuve repart de zéro.
  static func whatsNewStateAfterDisplay(
    _ state: WhatsNewState,
    release: WhatsNewRelease,
    now: Date
  ) -> WhatsNewState {
    var next = state
    if next.seenId != release.id {
      next.seenId = release.id
      next.shownAt = now
      next.appearances = 0
      next.lastAppearanceAt = nil
    }
    if isWithinAppearance(next, now: now) { return next }
    next.appearances += 1
    next.lastAppearanceAt = now
    return next
  }

  /// L'encart garde-t-il la session ? Tant qu'il est dû ou visible, et pendant
  /// l'apparition en cours même s'il vient d'être fermé : les fiches qui
  /// demandent attendent (§3.6 — il ne consomme pas le verrou, mais rien ne
  /// s'ouvre par-dessus ni juste après).
  static func whatsNewHoldsSession(
    releases: [WhatsNewRelease],
    state: WhatsNewState,
    onboardingDone: Bool,
    now: Date
  ) -> Bool {
    if whatsNewCard(releases: releases, state: state, onboardingDone: onboardingDone, now: now)
      != nil
    {
      return true
    }
    return isWithinAppearance(state, now: now)
  }

  /// Les lignes dans la langue de l'app : code complet (`pt-BR`), puis langue
  /// seule (`pt`), puis anglais. Les lignes d'une release ne sont rédigées qu'en
  /// fr / en / ar : un utilisateur allemand lit l'anglais, c'est assumé.
  static func lines(of release: WhatsNewRelease, localization: String) -> [String] {
    let normalized = localization.replacingOccurrences(of: "_", with: "-")
    if let lines = release.lines[normalized], !lines.isEmpty { return lines }
    let language = String(normalized.split(separator: "-").first ?? "")
    if let lines = release.lines[language], !lines.isEmpty { return lines }
    return release.lines["en"] ?? []
  }

  /// `yyyy-MM-dd` → minuit LOCAL du jour dit, ou `nil`. ⚠️ Jamais via un
  /// parseur ISO qui poserait minuit UTC : à l'ouest de Greenwich, l'encart
  /// daterait de la veille.
  static func parseReleaseDate(_ iso: String, calendar: Calendar = .current) -> Date? {
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, iso.count == 10 else { return nil }
    let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
    guard let date = calendar.date(from: components) else { return nil }
    // Rattrape un 31 février, que `Calendar` accepterait en débordant sur mars.
    let back = calendar.dateComponents([.year, .month, .day], from: date)
    guard back.year == parts[0], back.month == parts[1], back.day == parts[2] else { return nil }
    return date
  }
}
