// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import Shared
import SwiftUI
import UIKit

/// Fiche « Ton avis » — le formulaire d'avis écrit (§3.2).
///
/// Deux portes, et c'est délibéré (§2.9) : Réglages › Nous écrire (permanente,
/// celle qui compte — elle est là le jour où ça casse) et la venue spontanée
/// après quelques jours de navigation (`BrowtherPromptCoordinator`), qui ne sert
/// qu'à atteindre ceux qui n'iraient jamais fouiller les Réglages.
///
/// Le message part comme propriété de `feedback_submitted` ; PostHog le relaie
/// au worker `private/workers/posthog-telegram-webhook/`, qui l'envoie à Karim.
/// Pas de réponse possible par ce chemin (ni compte ni adresse) : qui en veut
/// une a le lien e-mail, sous le bouton.
final class BrowtherFeedbackHostingController: UIHostingController<BrowtherFeedbackView> {
  private let model: BrowtherFeedbackModel

  /// `isRehearsal` : déclencheur de recette (§2.8) — la fiche s'affiche à
  /// l'identique mais n'écrit rien et n'émet rien, pas même l'envoi.
  init(source: BrowtherSurfaces.FeedbackSource, isRehearsal: Bool = false) {
    model = BrowtherFeedbackModel(source: source, isRehearsal: isRehearsal)
    super.init(rootView: BrowtherFeedbackView(model: model))
    model.dismiss = { [weak self] in
      self?.dismiss(animated: true)
    }
    modalPresentationStyle = .pageSheet
    if let sheet = sheetPresentationController {
      // Plein écran d'emblée : le clavier monte à la première frappe, une
      // hauteur moyenne ne laisserait plus voir le bouton d'envoi.
      sheet.detents = [.large()]
      sheet.prefersGrabberVisible = true
    }
  }

  @available(*, unavailable)
  required dynamic init?(coder aDecoder: NSCoder) {
    fatalError()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    model.didAppear()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    // Un seul chemin pour toutes les fermetures (croix, balayage, bouton
    // « Fermer » du merci) : c'est ici qu'on sait que la fiche est partie.
    if isBeingDismissed || presentingViewController == nil {
      model.didDisappear()
    }
  }
}

final class BrowtherFeedbackModel: ObservableObject {
  enum Phase {
    case editing
    case thanks
  }

  let source: BrowtherSurfaces.FeedbackSource
  let isRehearsal: Bool

  @Published var text = "" {
    didSet {
      // Borne à la saisie, pas seulement à l'envoi : couper en silence ce que
      // la personne a vu s'écrire serait pire que de l'arrêter au 1000ᵉ signe.
      if text.count > BrowtherSurfacesRules.feedbackMaxLength {
        text = String(text.prefix(BrowtherSurfacesRules.feedbackMaxLength))
      }
    }
  }
  @Published var phase: Phase = .editing
  @Published var isAskingRecipient = false
  @Published var isShowingNoMailApp = false
  @Published private(set) var copiedAddress = ""

  var dismiss: (() -> Void)?

  /// La personne a répondu (message envoyé, e-mail ouvert, ou « ne plus me
  /// demander ») : la fermeture qui suit n'est pas un refus.
  private var concluded = false
  private var appeared = false
  private var disappeared = false

  init(source: BrowtherSurfaces.FeedbackSource, isRehearsal: Bool) {
    self.source = source
    self.isRehearsal = isRehearsal
  }

  var canSend: Bool { BrowtherSurfaces.canSendFeedback }

  var isSubmittable: Bool {
    canSend && BrowtherSurfacesRules.isFeedbackSubmittable(text)
  }

  func didAppear() {
    guard !appeared else { return }
    appeared = true
    guard !isRehearsal else { return }
    if source == .spontaneous {
      // Armé à l'affichage RÉEL, jamais à l'éligibilité (§2.1).
      BrowtherSurfaces.markSolicitationShown()
    }
    BrowtherSurfaces.noteFeedbackShown(source: source)
  }

  func didDisappear() {
    guard !disappeared else { return }
    disappeared = true
    guard !concluded, !isRehearsal else { return }
    BrowtherSurfaces.noteFeedbackDismissed(source: source)
  }

  func send() {
    guard isSubmittable else { return }
    if !isRehearsal {
      BrowtherSurfaces.submitFeedback(text, source: source)
    }
    concluded = true
    phase = .thanks
  }

  func optOut() {
    if !isRehearsal {
      BrowtherSurfaces.noteFeedbackOptedOut()
    }
    concluded = true
    dismiss?()
  }

  func close() {
    dismiss?()
  }

  func askRecipient() {
    if !isRehearsal {
      BrowtherSurfaces.track("contact_shown", ["source": "feedback"])
    }
    isAskingRecipient = true
  }

  func cancelRecipient() {
    if !isRehearsal {
      BrowtherSurfaces.track("contact_dismissed", ["source": "feedback"])
    }
  }

  func contact(_ recipient: BrowtherContact.Recipient) {
    BrowtherContact.open(recipient, source: "feedback") { [weak self] opened in
      guard let self else { return }
      if opened {
        // Ouvrir sa messagerie, c'est avoir répondu : la fiche spontanée ne
        // reviendra pas, comme après un envoi (§2.6).
        self.concluded = true
        if !self.isRehearsal {
          BrowtherSurfaces.noteFeedbackAnsweredByEmail()
        }
      } else {
        self.copiedAddress = recipient.address
        self.isShowingNoMailApp = true
      }
    }
  }
}

struct BrowtherFeedbackView: View {
  @ObservedObject var model: BrowtherFeedbackModel
  @FocusState private var isEditorFocused: Bool

  var body: some View {
    NavigationStack {
      Group {
        switch model.phase {
        case .editing: form
        case .thanks: thanks
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            model.close()
          } label: {
            Image(systemName: "xmark")
          }
          .accessibilityLabel(Strings.close)
        }
      }
    }
    .alert(Strings.Browther.contactTitle, isPresented: $model.isAskingRecipient) {
      Button(Strings.Browther.contactBrother) { model.contact(.brother) }
      Button(Strings.Browther.contactSister) { model.contact(.sister) }
      Button(Strings.cancelButtonTitle, role: .cancel) { model.cancelRecipient() }
    } message: {
      Text(Strings.Browther.contactMessage)
    }
    .alert(Strings.Browther.contactTitle, isPresented: $model.isShowingNoMailApp) {
      Button(Strings.OKString, role: .cancel) {}
    } message: {
      Text(String(format: Strings.Browther.contactNoMailApp, model.copiedAddress))
    }
  }

  private var form: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text(Strings.Browther.feedbackTitle)
          .font(.title2.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)

        Text(
          model.source == .spontaneous
            ? Strings.Browther.feedbackIntroSpontaneous
            : Strings.Browther.feedbackIntroPermanent
        )
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        editor

        if model.canSend {
          Text(Strings.Browther.feedbackPrivacy)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          Label(Strings.Browther.feedbackAnalyticsOff, systemImage: "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }

        Button {
          model.send()
        } label: {
          Text(Strings.Browther.feedbackSend)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!model.isSubmittable)

        Button(Strings.Browther.feedbackEmailHint) {
          isEditorFocused = false
          model.askRecipient()
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)

        if model.source == .spontaneous {
          Button(Strings.Browther.feedbackOptOut) {
            model.optOut()
          }
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
        }
      }
      .padding(20)
    }
    .scrollDismissesKeyboard(.interactively)
  }

  private var editor: some View {
    ZStack(alignment: .topLeading) {
      TextEditor(text: $model.text)
        .focused($isEditorFocused)
        .frame(minHeight: 150)
        .scrollContentBackground(.hidden)
        .padding(8)
      if model.text.isEmpty {
        Text(Strings.Browther.feedbackPlaceholder)
          .foregroundStyle(.tertiary)
          .padding(.horizontal, 13)
          .padding(.vertical, 16)
          .allowsHitTesting(false)
      }
    }
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(.secondarySystemBackground))
    )
  }

  private var thanks: some View {
    VStack(spacing: 14) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 48))
        .foregroundStyle(.green)
        .accessibilityHidden(true)
      Text(Strings.Browther.feedbackThanksTitle)
        .font(.title2.weight(.semibold))
      Text(Strings.Browther.feedbackThanksBody)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button(Strings.close) {
        model.close()
      }
      .buttonStyle(.bordered)
      .padding(.top, 6)
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
