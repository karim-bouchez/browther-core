// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BrowtherReferral
import SwiftUI
import UIKit

// MARK: - Le gabarit d'une fenêtre du flow

/// **Une fenêtre plus haute que son contenu : contenu CENTRÉ, boutons EN BAS**
/// (§ 12.26 — la grammaire d'un écran d'onboarding). Un contenu qui déborde
/// défile, ⛔ jamais rogné. **Le retour se voit deux fois** (§ 12.16) : une
/// flèche en haut à gauche et « Retour » en toutes lettres en bas. La croix
/// n'existe que sur une fenêtre qui n'ATTEND pas d'action (§ 12.14).
struct ReferralFlowShell<Content: View, Footer: View>: View {
  var eyebrow: String?
  var onBack: (() -> Void)?
  var onClose: (() -> Void)?
  @ViewBuilder var content: () -> Content
  @ViewBuilder var footer: () -> Footer

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        if let eyebrow {
          Text(eyebrow)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        HStack {
          if let onBack {
            Button(action: onBack) {
              Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Strings.BrowtherReferral.back)
          }
          Spacer()
          if let onClose {
            Button(action: onClose) {
              Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Strings.BrowtherReferral.close)
          }
        }
        .foregroundStyle(.secondary)
      }
      .frame(height: 48)
      .padding(.horizontal, 8)

      // ⚠️ Au moins la hauteur disponible (contenu centré), jamais au plus :
      // un contenu plus haut défile au lieu d'être rogné.
      GeometryReader { proxy in
        ScrollView {
          VStack(spacing: 18) {
            content()
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 12)
          .frame(maxWidth: 560)
          .frame(maxWidth: .infinity, minHeight: proxy.size.height)
        }
        .scrollBounceBehavior(.basedOnSize)
      }

      VStack(spacing: 6) {
        footer()
      }
      .padding(.horizontal, 20)
      .padding(.top, 10)
      .padding(.bottom, 8)
      .frame(maxWidth: 560)
    }
    .background(ReferralPalette.screen.ignoresSafeArea())
  }
}

struct ReferralFlowTitle: View {
  let text: String
  var body: some View {
    Text(text)
      .font(.title2.weight(.semibold))
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// ⭐ L'accroche (§ 12.30) : le GAIN, sur sa propre ligne et dans l'or du
/// TEXTE — fondue dans le titre, elle se lisait comme la fin d'une mauvaise
/// nouvelle (Karim). Sur 8 et 8 bis, c'est elle qui porte les mois gagnés
/// (§ 12.32).
struct ReferralFlowHook: View {
  let text: String
  var body: some View {
    Text(text)
      .font(.headline.weight(.semibold))
      .foregroundStyle(ReferralPalette.gold)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// Le sujet, au-dessus du titre — ⛔ seulement sur ce que personne n'a demandé
/// (8, 8 bis) : il situe avant même qu'on lise (§ 12.32).
struct ReferralSheetEyebrow: View {
  let text: String
  var body: some View {
    Text(text)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(.secondary)
  }
}

struct ReferralFlowBody: View {
  let text: String
  var body: some View {
    ReferralRichText(text: text)
      .font(.body)
      .foregroundStyle(.secondary)
      // ⚠️ Centré seulement s'il est court (§ 12.26) : un paragraphe de plusieurs
      // lignes s'aligne à gauche.
      .multilineTextAlignment(text.count > 140 ? .leading : .center)
      .fixedSize(horizontal: false, vertical: true)
  }
}

// MARK: - La pile plein écran

struct ReferralFlowView: View {
  @ObservedObject var model: ReferralFlowModel
  @ObservedObject private var controller = BrowtherReferralController.shared
  @State private var celebratedAt: Date?

  var body: some View {
    ZStack {
      screen(model.top)
        .id(model.depth)
        // Un écran ouvert par-dessus entre par la droite, le retour par la
        // gauche — les transitions de l'app (§ 12.26).
        .transition(.asymmetric(insertion: .push(from: .trailing), removal: .push(from: .leading)))
    }
    .animation(.smooth(duration: 0.35), value: model.depth)
    .overlay {
      if let celebratedAt {
        BrowtherIntroConfetti(start: celebratedAt)
          .id(celebratedAt)
          .ignoresSafeArea()
          .allowsHitTesting(false)
      }
    }
  }

  private func celebrate() { celebratedAt = Date() }

  private func action(_ screen: String, _ action: String) {
    guard !model.preview else { return }
    controller.track("paywall_action", ["screen": screen, "action": action])
  }

  @ViewBuilder
  private func screen(_ screen: ReferralScreen) -> some View {
    switch screen {
    case .welcome: welcome
    case .announce: announce
    case .paused: paused
    case .support(let locked): support(locked: locked)
    case .invite(let shared): invite(shared: shared)
    case .billing: billing
    case .thanks: ReferralThanksView { model.dismiss?() }
    default: EmptyView()
    }
  }

  // MARK: 7 — soutenir financièrement

  private var billing: some View {
    let inCircuit = model.depth > 1
    return ReferralFlowShell(
      eyebrow: Strings.BrowtherReferral.billingEyebrow,
      onBack: inCircuit ? { model.back() } : nil,
      onClose: inCircuit ? nil : { model.dismiss?() }
    ) {
      ReferralBillingBody(preview: model.preview)
    } footer: {
      ReferralBillingCTA(preview: model.preview) {
        // ⭐ Payer est une des trois sorties : « Merci », ⛔ jamais la fenêtre
        // d'où l'on est parti (§ 12.17).
        model.replaceAll(.thanks)
      }
      ReferralTextExit(label: Strings.BrowtherReferral.back, back: true) {
        if inCircuit { model.back() } else { model.dismiss?() }
      }
    }
  }

  // MARK: O — en aperçu de recette

  private var welcome: some View {
    ReferralFlowShell {
      ReferralWelcomeContent(source: "manual", onRedeemed: celebrate)
    } footer: {
      ReferralTextExit(label: Strings.BrowtherReferral.later) { model.dismiss?() }
    }
  }

  // MARK: 0 — l'annonce

  private var announce: some View {
    ReferralFlowShell {
      ReferralRoundIcon(systemName: "heart.fill")
      ReferralFlowTitle(text: Strings.BrowtherReferral.announceTitle)
      ReferralFlowBody(text: Strings.BrowtherReferral.announceBody)
      ReferralFeatureList(extras: .offered)
    } footer: {
      ReferralPrimaryButton(
        label: Strings.BrowtherReferral.inviteSomeone,
        sub: Strings.BrowtherReferral.announceInviteSub
      ) {
        action("announce", "invite")
        model.openHome?()
      }
      ReferralTextExit(label: Strings.BrowtherReferral.announceLater) {
        action("announce", "later")
        model.dismiss?()
        // ⭐ Écran 0 bis : un TOAST, ⛔ pas une seconde fenêtre (§ 12.9).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
          controller.announceLaterToast()
        }
      }
    }
  }

  // MARK: 2 — J0

  private var paused: some View {
    ReferralFlowShell {
      ReferralRoundIcon(systemName: "heart.fill")
      ReferralFlowTitle(text: Strings.BrowtherReferral.pausedTitle)
      ReferralFlowBody(text: Strings.BrowtherReferral.pausedBody)
      ReferralFeatureList(extras: .paused)
    } footer: {
      ReferralPrimaryButton(
        label: Strings.BrowtherReferral.supportDevndin,
        sub: Strings.BrowtherReferral.supportSub
      ) {
        action("paused", "support")
        // 🔴 Depuis J0, les trois façons forment un circuit FERMÉ (§ 12.16).
        model.replaceTop(.support(locked: true))
      }
      // ⛔ Pas de « plus tard » : la sortie est sur les trois façons.
      Text(Strings.BrowtherReferral.pausedFoot)
        .font(.footnote)
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
        .padding(.top, 4)
    }
  }

  // MARK: 2b — les trois façons

  private func support(locked: Bool) -> some View {
    ReferralFlowShell(
      eyebrow: Strings.BrowtherReferral.supportDevndin,
      // Ouverte par la personne (toast, rappel) : elle se ferme normalement ;
      // depuis J0, circuit fermé (§ 12.16).
      onClose: locked ? nil : { model.dismiss?() }
    ) {
      ReferralFlowTitle(text: Strings.BrowtherReferral.supportTitle)
      ReferralGaugeView(
        validated: controller.known?.milestones.validated ?? 0,
        scale: controller.scale,
        mode: .toy,
        demo: controller.known != nil,
        intention: $controller.gaugeIntention,
        onCelebrate: celebrate
      )
    } footer: {
      // ⭐ Le bouton REPREND le nombre de la jauge (§ 12.30) : l'écran demande
      // « combien penses-tu pouvoir inviter ? », il répond avec le même nombre,
      // cran par cran. Au palier « à vie », il s'allume — mêmes cotes, donc le
      // pied de l'écran ne saute pas.
      let intention = controller.gaugeIntention ?? 0
      let inviteLabel = intention > 1
        ? Strings.BrowtherReferral.supportInviteCount(intention)
        : Strings.BrowtherReferral.inviteSomeone
      let inviteSub = Strings.BrowtherReferral.supportInviteSub(ReferralProduct.validationTargetDays)
      let openInvite = {
        action("support", "invite")
        model.push(.invite(shared: false))
      }
      if intention >= controller.scale.lifetimeAt {
        ReferralLifetimeButton(label: inviteLabel, sub: inviteSub, action: openInvite)
      } else {
        ReferralPrimaryButton(label: inviteLabel, sub: inviteSub, action: openInvite)
      }
      if controller.billingAvailable {
        ReferralOrSeparator()
        ReferralSecondaryButton(label: Strings.BrowtherReferral.supportMoney(controller.prices.monthly)) {
          action("support", "billing")
          model.push(.billing)
        }
      }
      // La sortie : une phrase que la personne dit d'elle-même — ⛔ elle n'accorde rien.
      ReferralTextExit(label: Strings.BrowtherReferral.supportDua, italic: true) {
        action("support", "dua")
        controller.closeCircuit(preview: model.preview)
        model.dismiss?()
      }
    }
  }

  // MARK: 4 — inviter (⚠️ seulement dans le circuit des trois façons)

  private func invite(shared: Bool) -> some View {
    let inCircuit = model.depth > 1 && !shared
    return ReferralFlowShell(
      eyebrow: Strings.BrowtherReferral.inviteEyebrow,
      onBack: inCircuit ? { model.back() } : nil,
      onClose: inCircuit ? nil : { model.dismiss?() }
    ) {
      ReferralGaugeView(
        validated: controller.known?.milestones.validated ?? 0,
        scale: controller.scale,
        mode: .toy,
        demo: controller.known != nil,
        intention: $controller.gaugeIntention,
        onCelebrate: celebrate
      )
      // ⚠️ La carte du code se place ENTRE la carte « À vie » et le bouton de
      // partage : on partage le code, les deux doivent se toucher (§ 12.20).
      if let status = controller.known {
        ReferralCodeCard(status: status) {
          // ⭐ Copier EST un partage abouti (§ 12.20) — 3 jours offerts compris.
          if !model.preview {
            controller.track("referral_shared", ["screen": "4", "result": "copied"])
          }
          model.replaceTop(.invite(shared: true))
          controller.shareDone(from: "4", preview: model.preview)
        }
      }
      Text(Strings.BrowtherReferral.inviteFoot(ReferralProduct.validationTargetDays))
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    } footer: {
      if let status = controller.known {
        ReferralShareButton(status: status, screen: "4") {
          // ⭐ Un partage abouti LIBÈRE l'écran 4 (§ 12.16).
          model.replaceTop(.invite(shared: true))
        }
      }
      ReferralTextExit(
        label: shared ? Strings.BrowtherReferral.backToApp : Strings.BrowtherReferral.back,
        back: !shared
      ) {
        if shared || !inCircuit { model.dismiss?() } else { model.back() }
      }
    }
  }
}

// MARK: - Les feuilles (1, 3, 8, 8 bis) — fermeture classique

struct ReferralSheetView: View {
  let screen: ReferralScreen
  let preview: Bool
  let actions: ReferralSheetActions

  @ObservedObject private var controller = BrowtherReferralController.shared

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        content
      }
      .padding(.horizontal, 22)
      .padding(.top, 28)
      .padding(.bottom, 20)
      .frame(maxWidth: 560)
      .frame(maxWidth: .infinity)
    }
    .overlay(alignment: .topTrailing) {
      Button {
        actions.dismiss?()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 15, weight: .semibold))
          // ⚠️ `.secondary` DANS un bouton prend la teinte : la croix sortait
          // en bleu (recette Karim, 2026-09-22).
          .foregroundStyle(Color.secondary)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Strings.BrowtherReferral.close)
      .padding(6)
    }
    .onAppear {
      switch screen {
      case .validated, .refereeDone:
        UINotificationFeedbackGenerator().notificationOccurred(.success)
      default:
        break
      }
    }
  }

  private func action(_ name: String) {
    guard !preview else { return }
    controller.track("paywall_action", ["screen": screen.analyticsName, "action": name])
  }

  @ViewBuilder
  private var content: some View {
    switch screen {
    case .ending(let days):
      ReferralRoundIcon(systemName: "hourglass", size: 56)
      ReferralFlowTitle(text: Strings.BrowtherReferral.endingTitle(days))
      ReferralFlowHook(text: Strings.BrowtherReferral.endingHook)
      ReferralFeatureList(extras: .soon(days: days))
      ReferralFlowBody(text: Strings.BrowtherReferral.endingBody)
      ReferralPrimaryButton(
        label: Strings.BrowtherReferral.supportDevndin,
        sub: Strings.BrowtherReferral.supportSub
      ) {
        action("support")
        actions.openSupport?()
      }
      ReferralTextExit(label: Strings.BrowtherReferral.later) {
        action("later")
        actions.dismiss?()
      }

    case .reminder(let days, let reminderCase):
      ReferralRoundIcon(systemName: "bell", size: 56)
      ReferralFlowTitle(text: reminderTitle(reminderCase, days: days))
      ReferralFlowBody(text: reminderBody(reminderCase))
      ReferralPrimaryButton(label: Strings.BrowtherReferral.inviteSomeone) {
        action("invite")
        actions.openHome?()
      }
      ReferralTextExit(label: Strings.BrowtherReferral.later) {
        action("later")
        actions.dismiss?()
      }

    case .validated(let months, let until, let lifetime):
      ReferralRoundIcon(systemName: lifetime ? "infinity" : "checkmark.seal.fill", tone: .green, size: 64)
      ReferralSheetEyebrow(text: Strings.BrowtherReferral.noticeEyebrow)
      ReferralFlowTitle(text: Strings.BrowtherReferral.noticeTitle)
      ReferralFlowHook(text: validatedBody(months: months, until: until, lifetime: lifetime))
      ReferralFlowBody(text: Strings.BrowtherReferral.noticeWhy(ReferralProduct.validationTargetDays))
      ReferralPrimaryButton(label: Strings.BrowtherReferral.noticeSee) {
        actions.openHome?()
      }

    case .refereeDone:
      ReferralRoundIcon(systemName: "heart.fill", tone: .green, size: 64)
      ReferralSheetEyebrow(text: Strings.BrowtherReferral.noticeEyebrow)
      ReferralFlowTitle(text: Strings.BrowtherReferral.refereeNoticeTitle)
      ReferralFlowHook(text: Strings.BrowtherReferral.refereeNoticeBody)
      ReferralFlowBody(text: Strings.BrowtherReferral.refereeNoticeWhy(ReferralProduct.validationTargetDays))
      ReferralPrimaryButton(label: Strings.BrowtherReferral.refereeInviteToo) {
        actions.openHome?()
      }

    default:
      EmptyView()
    }
  }

  private func reminderTitle(_ reminderCase: ReminderCase, days: Int) -> String {
    switch reminderCase {
    case .earnedMonthsEnding: return Strings.BrowtherReferral.reminderTitleMonths(days)
    case .subscriptionCancelled: return Strings.BrowtherReferral.reminderTitleSubscription(days)
    case .inProgress, .noneOpened: return Strings.BrowtherReferral.reminderTitleFeatures(days)
    }
  }

  private func reminderBody(_ reminderCase: ReminderCase) -> String {
    switch reminderCase {
    case .noneOpened:
      return Strings.BrowtherReferral.reminderNoneOpened
    case .inProgress:
      let closest = controller.known.flatMap { ReferralInvitations.closestDaysLeft($0.invitations.items) }
      return closest.map(Strings.BrowtherReferral.reminderInProgressCount) ?? Strings.BrowtherReferral.reminderInProgress
    case .earnedMonthsEnding:
      // Le slot `{left}` lu dans `milestones.next.remaining` (§ 11.3 #13) ;
      // sans palier à venir, la phrase s'arrête.
      if let left = controller.known?.milestones.next?.remaining {
        return Strings.BrowtherReferral.reminderMonthsNext(left)
      }
      return Strings.BrowtherReferral.reminderMonths
    case .subscriptionCancelled:
      return Strings.BrowtherReferral.reminderSubscription
    }
  }

  private func validatedBody(months: Int, until: String?, lifetime: Bool) -> String {
    if lifetime { return Strings.BrowtherReferral.noticeLifetime }
    guard let date = ReferralDate.parse(until) else {
      return Strings.BrowtherReferral.noticeBodyNoDate(months: months)
    }
    return Strings.BrowtherReferral.noticeBody(months: months, date: BrowtherReferralController.formatDate(date))
  }
}

// MARK: - 7 bis — « Merci » (§ 12.17)

/// La fête, au retour d'un achat accepté : confettis et haptique de succès —
/// ⛔ jamais la fenêtre d'où l'on est parti. Tant que l'abonnement n'est pas
/// confirmé : « Ton abonnement se met en place… ». Fermeture classique.
struct ReferralThanksView: View {
  var onClose: () -> Void

  @ObservedObject private var controller = BrowtherReferralController.shared
  @State private var celebratedAt: Date?

  var body: some View {
    ReferralFlowShell(onClose: onClose) {
      ReferralRoundIcon(systemName: "heart.fill", tone: .green)
      ReferralFlowTitle(text: Strings.BrowtherReferral.thanksTitle)
      ReferralFlowBody(
        text: controller.known?.subscription.active == true
          ? Strings.BrowtherReferral.thanksBodyActive
          : Strings.BrowtherReferral.thanksBodyPending
      )
      ReferralFeatureList(extras: .included, extrasOnly: true)
    } footer: {
      ReferralTextExit(label: Strings.BrowtherReferral.backToApp, action: onClose)
    }
    .overlay {
      if let celebratedAt {
        BrowtherIntroConfetti(start: celebratedAt)
          .id(celebratedAt)
          .ignoresSafeArea()
          .allowsHitTesting(false)
      }
    }
    .onAppear {
      celebratedAt = Date()
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
  }
}
