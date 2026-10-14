// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BrowtherReferral
import SwiftUI
import UIKit

/// 🧪 **Recetter pour de vrai : un outil qui POSE l'état** — `docs/PARRAINAGE.md`
/// § 12.18 et § 12.26. Paramètres › « Browther — recette » (hors build du
/// store). Interne, non traduit.
///
/// - **Poser une situation** (service + appareil) : un scénario en un clic,
///   avec N invitations validées / en cours. ⭐ Il ouvre l'écran du scénario
///   DIRECTEMENT (verrou du jour levé, mérite posé) — « j'ai fait J−3 mais j'ai
///   rien » ne doit pas arriver ; et il DIT pourquoi rien ne s'est ouvert.
/// - 🔴 Le jeton d'administration se SAISIT ici et reste sur l'appareil — ⛔
///   jamais une constante de build.
/// - ⚠️ **Un build de dev ne peut pas être navigateur par défaut** (l'entitlement
///   n'est que sur la Release) : « Compter aujourd'hui comme jour par défaut »
///   est le seul moyen de recetter la validation d'un filleul.
/// - Revoir un écran : ⛔ n'écrit rien (§ 12.7).
struct ReferralRecetteView: View {
  /// Ferme les Paramètres puis tente la sollicitation sur le navigateur ;
  /// rend ce qui s'est passé.
  var provoke: (@MainActor (_ merit: Bool) async -> String)?
  /// Ferme les Paramètres puis montre un écran en aperçu.
  var preview: ((ReferralScreen) -> Void)?
  /// Ferme les Paramètres puis montre le partage proposé en aperçu.
  var previewSharePrompt: (
    (ReferralSharePrompt.Profile, ReferralSharePrompt.Tab, ReferralSharePrompt.Headline) -> Void
  )?

  @ObservedObject private var controller = BrowtherReferralController.shared
  @State private var token = ReferralStorage.shared.recetteToken ?? ""
  @State private var validated = 0
  @State private var installed = 0
  @State private var message: String?
  @State private var busy = false

  var body: some View {
    Form {
      Section("Où j'en suis") {
        Text(controller.debugSummary())
          .font(.system(.footnote, design: .monospaced))
          .textSelection(.enabled)
        Button("Relire le statut") {
          Task { await controller.refresh() }
        }
      }

      Section {
        SecureField("Jeton d'administration (ADMIN_API_TOKEN)", text: $token)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .onChange(of: token) { _, next in
            ReferralStorage.shared.recetteToken = next.isEmpty ? nil : next
          }
        Stepper("Invitations validées : \(validated)", value: $validated, in: 0...12)
        Stepper("Invitations en cours : \(installed)", value: $installed, in: 0...5)
        Toggle("Faire comme si Sawtunaa était finalisé", isOn: $controller.recetteExtrasReleased)
        ForEach(Scenario.allCases) { scenario in
          Button(scenario.label) { apply(scenario) }
            .disabled(token.isEmpty || busy)
        }
        if let message {
          Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("Poser une situation")
      } footer: {
        Text(
          "Le service est remplacé en entier (couverture, invitations, abonnement), puis l'écran du scénario "
            + "s'ouvre sur le navigateur. « Neuf » n'annonce rien tant que Sawtunaa n'est pas finalisé : "
            + "cocher l'interrupteur au-dessus."
        )
      }

      Section {
        Text(sharePromptLine)
          .font(.footnote)
        Button("Réarmer le partage proposé · Statut WhatsApp") { arm(.status) }
        Button("Réarmer le partage proposé · Message") { arm(.message) }
      } header: {
        Text("Partage proposé (§ 12.45)")
      } footer: {
        Text(
          "Réarmer efface ce que l'appareil en a retenu (dernier affichage, partage, fermetures, « ne plus me "
            + "redemander ») et choisit l'onglet. Il sort alors à « Provoquer maintenant », dans le profil posé "
            + "(« Mois en cours », « Abonné », « À vie ») — sauf si un écran daté est dû avant lui. Sans WhatsApp, "
            + "toujours « Message »."
        )
      }

      Section("Cet appareil") {
        Button("Provoquer maintenant (mérite posé)") {
          Task {
            controller.liftDayLockForRecette()
            message = await provoke?(true)
          }
        }
        Button("Compter aujourd'hui comme jour « par défaut »") {
          controller.recordDefaultDayForRecette()
          message = "Jour compté : il part au service si ce sujet a un parrain."
        }
        Button("Lever le verrou du jour") {
          controller.liftDayLockForRecette()
          message = "Verrou du jour levé."
        }
        Button("Rejouer la démo de la jauge") {
          controller.resetGaugeUnderstoodForRecette()
          message = "La jauge rejouera sa démo."
        }
        Button("Oublier ce que j'ai vu (annonce, rappels, circuit)") {
          controller.forgetPromptForRecette()
          message = "Oublié."
        }
        Button("Repartir d'un appareil neuf (au prochain lancement)") {
          controller.setRecetteIdentity(fresh: true)
          message = "Nouvelle identité au prochain lancement de Browther."
        }
        Button("Revenir à la vraie identité (au prochain lancement)") {
          controller.setRecetteIdentity(fresh: false)
          message = "Vraie identité au prochain lancement de Browther."
        }
      }

      Section {
        ForEach(PreviewItem.all) { item in
          Button(item.label) {
            controller.previewSupportThanks(until: item.onceUntil)
            preview?(item.screen)
          }
        }
        ForEach(SharePromptPreview.all) { item in
          Button(item.label) { previewSharePrompt?(item.profile, item.tab, item.headline) }
        }
        Button("Toast 0 bis — « C'est noté »") { controller.announceLaterToast() }
        Button("Toast — garde du retrait de la musique") {
          // Le MÊME code que la vraie garde, ⛔ rien de compté (§ 12.41).
          controller.showLockedToast(.musicRemoval, presentingFrom: nil, preview: true)
        }
      } header: {
        Text("Revoir un écran (n'écrit rien)")
      }
    }
    .navigationTitle("Parrainage — recette")
  }

  /// 🧪 Pourquoi le partage proposé sortirait, ou se tait — les dix raisons
  /// de `ReferralSharePrompt.Silence` (brief § 2.6).
  private var sharePromptLine: String {
    switch controller.sharePromptVerdict() {
    case .due(let decision):
      return "Dû au prochain moment de mérite — profil \(decision.profile.rawValue), onglet \(decision.openedOn.rawValue)."
    case .silent(let reason):
      return "Se tait : \(reason.rawValue) — \(Self.explain(reason))"
    }
  }

  private static func explain(_ reason: ReferralSharePrompt.Silence) -> String {
    switch reason {
    case .unknown: return "statut inconnu."
    case .noMerit: return "pas de moment de mérite (5 pages ou 60 s de musique aujourd'hui)."
    case .paused: return "fonctionnalités en pause : J0 est le créneau."
    case .beforeAnnounce: return "l'annonce n'a pas été montrée (elle dort tant que Sawtunaa n'est pas finalisé)."
    case .muted: return "« Ne plus me redemander »."
    case .tooEarly: return "moins de 7 jours depuis l'annonce."
    case .recentPrompt: return "déjà proposé il y a moins de 30 jours (60 après deux fermetures)."
    case .recentShare: return "un partage a abouti il y a moins de 30 jours."
    case .recentScreen: return "un autre écran du parrainage il y a moins de 7 jours."
    case .reminderSoon: return "un rappel (J−10) tombe dans moins de 7 jours."
    }
  }

  private func arm(_ tab: ReferralSharePrompt.Tab) {
    controller.armSharePromptForRecette(tab: tab)
    controller.liftDayLockForRecette()
    message = "Partage proposé réarmé (\(tab.rawValue)). « Provoquer maintenant » le fait sortir."
  }

  private func apply(_ scenario: Scenario) {
    busy = true
    message = nil
    Task {
      do {
        try await controller.applyRecette(token: token, state: scenario.state(validated: validated, installed: installed))
        controller.liftDayLockForRecette()
        message = await provoke?(true) ?? "Posé."
      } catch {
        message = "Le service a refusé (jeton ? réseau ?)."
      }
      busy = false
    }
  }

  enum Scenario: String, CaseIterable, Identifiable {
    case fresh, running, j10, j3, j0, subscribed, cancelled, supportOnce, lifetime
    var id: String { rawValue }

    var label: String {
      switch self {
      case .fresh: return "Neuf (avant l'annonce)"
      case .running: return "Mois en cours (20 j)"
      case .j10: return "J−10"
      case .j3: return "J−3"
      case .j0: return "J0 (tombée hier)"
      case .subscribed: return "Abonné"
      case .cancelled: return "Résilié (3 j)"
      case .supportOnce: return "Soutien ponctuel (6 mois)"
      case .lifetime: return "À vie"
      }
    }

    func state(validated: Int, installed: Int) -> RecetteState {
      switch self {
      case .fresh:
        return RecetteState(trialStarted: false, daysLeft: nil, validated: validated, installed: installed)
      case .running:
        return RecetteState(trialStarted: true, daysLeft: 20, validated: validated, installed: installed)
      case .j10:
        return RecetteState(trialStarted: true, daysLeft: 10, validated: validated, installed: installed)
      case .j3:
        return RecetteState(trialStarted: true, daysLeft: 3, validated: validated, installed: installed)
      case .j0:
        return RecetteState(trialStarted: true, daysLeft: -1, validated: validated, installed: installed)
      case .subscribed:
        return RecetteState(
          trialStarted: true, daysLeft: nil, validated: validated, installed: installed,
          subscription: .active, subscriptionDaysLeft: 30
        )
      case .cancelled:
        return RecetteState(
          trialStarted: true, daysLeft: nil, validated: validated, installed: installed,
          subscription: .cancelled, subscriptionDaysLeft: 3
        )
      case .supportOnce:
        // ⭐ § 12.43 : 6 mois ajoutés au bout des 5 jours restants — « couvert
        // jusqu'au … » sur l'écran 7, aucune sollicitation tant qu'ils courent.
        return RecetteState(trialStarted: true, daysLeft: 5, validated: validated, installed: installed, support: 6)
      case .lifetime:
        return RecetteState(trialStarted: true, daysLeft: nil, lifetime: true, validated: validated, installed: installed)
      }
    }
  }

  /// Le partage proposé, dans chaque profil et sur chaque onglet — ⛔ n'écrit
  /// rien. Le titre suit le compteur RÉEL de l'appareil, sauf « sans compteur ».
  struct SharePromptPreview: Identifiable {
    let label: String
    let profile: ReferralSharePrompt.Profile
    let tab: ReferralSharePrompt.Tab
    let headline: ReferralSharePrompt.Headline
    var id: String { label }

    @MainActor
    static var all: [SharePromptPreview] {
      let real = BrowtherReferralController.sharePromptHeadline
      let none = ReferralSharePrompt.headline(musicSeconds: 0, personsBlurred: 0)
      let both = ReferralSharePrompt.headline(musicSeconds: 12 * 3600, personsBlurred: 1240)
      return [
        .init(label: "Partage proposé — mois offerts · Statut", profile: .offered, tab: .status, headline: real),
        .init(label: "Partage proposé — mois offerts · Message", profile: .offered, tab: .message, headline: real),
        .init(label: "Partage proposé — abonné · Statut", profile: .paid, tab: .status, headline: real),
        .init(label: "Partage proposé — abonné · Message", profile: .paid, tab: .message, headline: real),
        .init(label: "Partage proposé — à vie · Statut", profile: .lifetime, tab: .status, headline: real),
        .init(label: "Partage proposé — à vie · Message", profile: .lifetime, tab: .message, headline: real),
        .init(label: "Partage proposé — sans compteur", profile: .offered, tab: .status, headline: none),
        .init(label: "Partage proposé — compteur 12 h · 1 240", profile: .offered, tab: .status, headline: both),
      ]
    }
  }

  struct PreviewItem: Identifiable {
    let label: String
    let screen: ReferralScreen
    /// 🧪 « Merci » d'un soutien ponctuel : la date de fin à montrer.
    var onceUntil: String?
    var id: String { label }

    static let all: [PreviewItem] = [
      .init(label: "O — le code d'un proche", screen: .welcome),
      .init(label: "0 — l'annonce", screen: .announce),
      .init(label: "1 — J−3 (première fin)", screen: .ending(daysLeft: 3)),
      .init(label: "2 — J0", screen: .paused(chosen: false)),
      .init(label: "2b — les trois façons (fermé)", screen: .support(locked: true)),
      .init(label: "3 — rappel « en bonne voie »", screen: .reminder(daysLeft: 3, reminderCase: .inProgress)),
      .init(label: "3 — rappel « fin de mois gagnés »", screen: .reminder(daysLeft: 10, reminderCase: .earnedMonthsEnding)),
      .init(label: "3 — rappel « abonnement annulé »", screen: .reminder(daysLeft: 3, reminderCase: .subscriptionCancelled)),
      // ⭐ La capture de vérification d'App Store Connect se prend ICI : le
      // bouton a son vrai visage même sans offre (build de dev).
      .init(label: "7 — payer (capture App Store)", screen: .billing),
      .init(label: "7 bis — merci", screen: .thanks),
      .init(
        label: "7 bis — merci · une seule fois",
        screen: .thanks,
        onceUntil: ReferralDate.string(Date().addingTimeInterval(6 * 30 * 86_400))
      ),
      .init(label: "8 — invitation validée", screen: .validated(months: 2, until: "2026-12-01T10:00:00.000Z", lifetime: false)),
      .init(label: "8 — à vie", screen: .validated(months: 1, until: nil, lifetime: true)),
      .init(label: "8 bis — merci (filleul)", screen: .refereeDone),
    ]
  }
}
