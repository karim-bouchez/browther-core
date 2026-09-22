// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BrowtherReferral
import SwiftUI
import UIKit

// MARK: - Le champ du code d'un proche (§ 12.6, § 12.24)

/// - 🔴 **« J'ai un code de parrainage » est AMBIGU** : le titre dit « Un proche
///   t'a parlé de Browther ? ».
/// - Un vrai champ, et **le bouton unique vit DANS le champ** (Coller → Valider),
///   en pastille à son bout — ⛔ pas posé à côté : il mangeait la largeur.
/// - **La forme se vérifie avant le service** (`ReferralCode.readInput`) :
///   « TEST » dit « un code fait 6 caractères ». Un lien collé est accepté en
///   silence.
/// - Chasse fixe **seulement pour le code tapé** : le placeholder est une phrase.
/// - **Un refus secoue le champ** (haptique d'erreur) ; **une réussite se fête**
///   (l'appelant tire les confettis). Mouvement réduit : ni secousse, ni salve.
/// - ⚠️ « Coller » est le `PasteButton` du système : il colle SANS la demande
///   d'autorisation qu'iOS affiche à chaque lecture du presse-papier.
struct ReferralRedeemField: View {
  let source: String
  var onDone: (() -> Void)?

  @State private var text = ""
  @State private var error: String?
  @State private var busy = false
  @State private var shake: CGFloat = 0
  @FocusState private var focused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        TextField(Strings.BrowtherReferral.redeemPlaceholder, text: $text)
          .focused($focused)
          .textInputAutocapitalization(.characters)
          .autocorrectionDisabled()
          .keyboardType(.asciiCapable)
          .submitLabel(.done)
          .onSubmit(validate)
          .font(text.isEmpty ? .body : .system(.title3, design: .monospaced).weight(.semibold))
          .tracking(text.isEmpty ? 0 : 3)
          .onChange(of: text) { _, _ in error = nil }
        trailingButton
      }
      .padding(.leading, 16)
      .padding(.trailing, 6)
      .frame(height: 54)
      .background(ReferralPalette.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(error == nil ? Color.clear : Color.red.opacity(0.6), lineWidth: 1.5)
      }
      .modifier(ShakeEffect(travel: shake))
      if let error {
        Text(error)
          .font(.footnote)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private var trailingButton: some View {
    if busy {
      ProgressView()
        .frame(width: 44, height: 40)
    } else if text.isEmpty {
      PasteButton(payloadType: String.self) { strings in
        guard let first = strings.first else { return }
        Task { @MainActor in
          text = first.trimmingCharacters(in: .whitespacesAndNewlines)
          validate()
        }
      }
      .labelStyle(.titleOnly)
      .buttonBorderShape(.capsule)
      .tint(Color(UIColor.label))
      .controlSize(.regular)
    } else {
      Button(action: validate) {
        Text(Strings.BrowtherReferral.redeemValidate)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color(UIColor.systemBackground))
          .padding(.horizontal, 16)
          .frame(height: 40)
          .background(Color(UIColor.label), in: Capsule())
      }
      .buttonStyle(.plain)
    }
  }

  private func validate() {
    switch ReferralCode.readInput(text) {
    case .failure(.empty):
      return
    case .failure(.length):
      refuse(Strings.BrowtherReferral.redeemErrorLength)
    case .failure(.alphabet):
      refuse(Strings.BrowtherReferral.redeemErrorAlphabet)
    case .success(let code):
      busy = true
      Task { @MainActor in
        let outcome = await BrowtherReferralController.shared.redeem(code: code, source: source)
        busy = false
        switch outcome {
        case .accepted?:
          focused = false
          UINotificationFeedbackGenerator().notificationOccurred(.success)
          onDone?()
        case .refused(let reason)?:
          refuse(Self.message(reason))
        case nil:
          refuse(Strings.BrowtherReferral.refusalUnavailable)
        }
      }
    }
  }

  private func refuse(_ message: String) {
    error = message
    UINotificationFeedbackGenerator().notificationOccurred(.error)
    guard !reduceMotion else { return }
    withAnimation(.linear(duration: 0.4)) { shake += 1 }
  }

  static func message(_ reason: RedeemRefusal) -> String {
    switch reason {
    case .unknownCode: return Strings.BrowtherReferral.refusalUnknownCode
    case .`self`: return Strings.BrowtherReferral.refusalSelf
    case .sameDevice: return Strings.BrowtherReferral.refusalSameDevice
    case .alreadyRedeemed: return Strings.BrowtherReferral.refusalAlreadyRedeemed
    case .wrongProduct: return Strings.BrowtherReferral.refusalWrongProduct
    }
  }
}

/// La secousse d'un refus : trois allers-retours qui s'amortissent.
private struct ShakeEffect: GeometryEffect {
  var travel: CGFloat
  var animatableData: CGFloat {
    get { travel }
    set { travel = newValue }
  }

  func effectValue(size: CGSize) -> ProjectionTransform {
    let progress = travel - travel.rounded(.down)
    let offset = sin(progress * .pi * 6) * 8 * (1 - progress)
    return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
  }
}

// MARK: - L'écran O (et l'onglet « Code reçu » sans parrain)

/// **Le code d'un proche, et RIEN d'autre** (§ 12.24) : ⛔ pas de partie
/// « inviter » — la personne ne connaît pas encore l'app. ⭐ La même rédaction
/// sert l'introduction, l'onglet « Code reçu » de l'écran Parrainage (sans
/// parrain) et l'aperçu de recette — ⛔ jamais deux textes.
struct ReferralWelcomeContent: View {
  let source: String
  var compact = false
  var onRedeemed: (() -> Void)?

  @ObservedObject private var controller = BrowtherReferralController.shared
  @State private var redeemed = false

  var body: some View {
    let alreadyReferred = controller.known?.referredBy != nil && !redeemed
    VStack(spacing: 28) {
      VStack(spacing: 8) {
        Text(Strings.BrowtherReferral.redeemHead)
          .font(.title2.weight(.semibold))
          .multilineTextAlignment(.center)
        Text(Strings.BrowtherReferral.redeemBody)
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      if !compact {
        ReferralGiftBadge(done: redeemed || alreadyReferred)
      }
      if alreadyReferred || redeemed {
        Label(Strings.BrowtherReferral.redeemValidatedLine, systemImage: "checkmark.circle.fill")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(ReferralPalette.green)
          .multilineTextAlignment(.center)
      } else {
        ReferralRedeemField(source: source) {
          redeemed = true
          onRedeemed?()
        }
      }
    }
  }
}

/// Le disque qui « s'ouvre » : un léger dépassement, ⛔ jamais depuis zéro.
struct ReferralGiftBadge: View {
  let done: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      if done {
        Circle()
          .fill(ReferralPalette.greenFill)
          .overlay {
            Image(systemName: "checkmark")
              .font(.system(size: 40, weight: .bold))
              .foregroundStyle(.white)
          }
          .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
      } else {
        Circle()
          .fill(ReferralPalette.goldSurface)
          .overlay {
            Image(systemName: "gift.fill")
              .font(.system(size: 38))
              .foregroundStyle(ReferralPalette.gold)
          }
      }
    }
    .frame(width: 96, height: 96)
    .animation(.spring(duration: 0.42, bounce: 0.35), value: done)
  }
}

// MARK: - Mes invitations (§ 12.1)

/// Deux états, deux couleurs : or = en cours (un proche a utilisé le code),
/// vert = validée (+1 mois, et la ligne ★ quand elle a fait franchir un
/// palier). ⛔ Jamais « envoyée », ⛔ jamais un nom.
struct ReferralInvitationList: View {
  let items: [InvitationItem]
  let scale: MilestoneScale

  var body: some View {
    VStack(spacing: 10) {
      ForEach(items) { item in
        row(item)
      }
    }
  }

  private func row(_ item: InvitationItem) -> some View {
    let validated = item.status == .validated
    let tone = validated ? ReferralPalette.green : ReferralPalette.gold
    let target = ReferralProduct.validationTargetDays
    return VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(validated ? Strings.BrowtherReferral.invitationValidated : Strings.BrowtherReferral.invitationInProgress)
          .font(.caption.weight(.semibold))
          .foregroundStyle(tone)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(tone.opacity(0.12), in: Capsule())
        if let date = ReferralDate.parse(validated ? item.validatedAt : item.installedAt) {
          Text(BrowtherReferralController.formatDate(date))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if validated {
          Text(Strings.BrowtherReferral.invitationMonths(1))
            .font(.headline)
            .foregroundStyle(ReferralPalette.green)
        }
      }
      if validated {
        Text(Strings.BrowtherReferral.invitationRowValidated(target))
          .font(.footnote)
          .foregroundStyle(.secondary)
        if item.milestone, let bonus = scale.milestone(forCredit: item.creditedMonths) {
          Label(
            Strings.BrowtherReferral.invitationMilestone(bonus: bonus.months, at: bonus.at),
            systemImage: "star.fill"
          )
          .font(.footnote.weight(.medium))
          .foregroundStyle(ReferralPalette.gold)
        }
      } else if let left = ReferralInvitations.daysLeft(item) {
        Text(Strings.BrowtherReferral.invitationRowInProgress(left))
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        ReferralMeter(ratio: ReferralInvitations.ratio(item.progress))
      } else {
        Text(Strings.BrowtherReferral.invitationRowInProgressUnknown(target))
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(12)
    .background(ReferralPalette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

struct ReferralMeter: View {
  let ratio: Double

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule().fill(ReferralPalette.track)
        Capsule()
          .fill(ReferralPalette.goldFill)
          .frame(width: geometry.size.width * ratio)
      }
    }
    .frame(height: 6)
    .environment(\.layoutDirection, .leftToRight)
  }
}
