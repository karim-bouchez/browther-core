// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BrowtherReferral
import SwiftUI
import UIKit

/// Écran 6 — **Parrainage** — `docs/PARRAINAGE.md` § 3, § 12.2, § 12.24 et
/// § 12.26. Une vraie PAGE : Paramètres › « Parrainage », et tout « Inviter un
/// proche » du flow hors du circuit des trois façons (§ 12.15).
///
/// ## 🔴 En ONGLETS (§ 12.26)
///
/// Une page qui défile cache ce qui est en bas à qui ne défile pas ; des
/// onglets se VOIENT. Un **contrôle segmenté EN HAUT**, icône au-dessus du
/// libellé : Inviter · Invitations · Code reçu (· Soutenir, le jour où payer
/// existe dans ce binaire). ⛔ Pas de glissé entre onglets (la jauge se tire de
/// côté), ⛔ aucune animation de glissement ; un cran d'haptique au changement.
/// ⭐ **Le titre est celui de l'onglet** ; un onglet peu rempli se CENTRE ;
/// « aucune invitation » donne le geste qui la remplit.
///
/// ⚠️ Intitulés au genre neutre (§ 6) : ⛔ jamais « parrain » / « filleul ».
/// ⚠️ Le bouton dit « Partager mon code », ⛔ pas « Inviter un proche » : c'est
/// le bouton qui MÈNE ici.
struct ReferralHomeView: View {
  enum Tab: Hashable {
    case invite, invitations, code, support
  }

  @ObservedObject private var controller = BrowtherReferralController.shared
  @State private var tab: Tab = .invite
  @State private var celebratedAt: Date?

  var body: some View {
    VStack(spacing: 0) {
      if let status = controller.known {
        tabs
          .padding(.horizontal, 16)
          .padding(.top, 8)
          .padding(.bottom, 12)
        Group {
          switch current {
          case .invite: ReferralInviteTab(status: status, onCelebrate: celebrate)
          case .invitations: ReferralInvitationsTab(status: status)
          case .code: ReferralCodeTab(status: status, onCelebrate: celebrate, onInvite: { choose(.invite) })
          case .support: ReferralSupportTab()
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ReferralPendingView()
      }
    }
    .background(ReferralPalette.screen.ignoresSafeArea())
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .overlay {
      if let celebratedAt {
        BrowtherIntroConfetti(start: celebratedAt)
          .id(celebratedAt)
          .ignoresSafeArea()
          .allowsHitTesting(false)
      }
    }
    .onAppear { BrowtherReferralController.shared.boot() }
  }

  /// Le paiement peut disparaître : on ne reste pas sur un onglet absent.
  private var current: Tab {
    tab == .support && !controller.billingAvailable ? .invite : tab
  }

  private var title: String {
    switch current {
    case .invite: return Strings.BrowtherReferral.homeTitle
    case .invitations: return Strings.BrowtherReferral.homeListHead
    case .code: return Strings.BrowtherReferral.homeAsReferee
    case .support: return Strings.BrowtherReferral.tabSupport
    }
  }

  private func choose(_ next: Tab) {
    guard next != current else { return }
    UISelectionFeedbackGenerator().selectionChanged()
    // ⭐ On vient ici EXPRÈS : c'est le pendant de « Choisir ma formule » (§ 12.26).
    if next == .support {
      controller.track("paywall_action", ["screen": "home", "action": "billing"])
    }
    tab = next
  }

  private func celebrate() {
    celebratedAt = Date()
  }

  private struct TabItem: Identifiable {
    let tab: Tab
    let label: String
    let symbol: String
    var id: Tab { tab }
  }

  private var tabs: some View {
    var items = [
      TabItem(tab: .invite, label: Strings.BrowtherReferral.tabInvite, symbol: "person.badge.plus"),
      TabItem(tab: .invitations, label: Strings.BrowtherReferral.tabInvitations, symbol: "checklist"),
      TabItem(tab: .code, label: Strings.BrowtherReferral.tabCode, symbol: "gift"),
    ]
    if controller.billingAvailable {
      items.append(TabItem(tab: .support, label: Strings.BrowtherReferral.tabSupport, symbol: "heart"))
    }
    return HStack(spacing: 4) {
      ForEach(items) { item in
        let on = item.tab == current
        Button {
          choose(item.tab)
        } label: {
          VStack(spacing: 3) {
            Image(systemName: item.symbol)
              .font(.system(size: 17, weight: .medium))
            Text(item.label)
              .font(.caption.weight(on ? .semibold : .medium))
              .lineLimit(1)
              .minimumScaleFactor(0.8)
          }
          .foregroundStyle(on ? Color.primary : Color.secondary)
          .frame(maxWidth: .infinity, minHeight: 52)
          .background {
            if on {
              RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(ReferralPalette.panel)
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
      }
    }
    .padding(4)
    .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

// MARK: - Onglet « Soutenir »

/// **Les formules, directement** (§ 12.26) : on vient ici exprès. Le même
/// contenu que l'écran 7, le bouton épinglé en bas. Un achat abouti ouvre
/// « Merci » (§ 12.17).
struct ReferralSupportTab: View {
  @ObservedObject private var controller = BrowtherReferralController.shared

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        ReferralBillingBody()
          .padding(.horizontal, 16)
          .padding(.bottom, 24)
          .frame(maxWidth: 560)
          .frame(maxWidth: .infinity)
      }
      .refreshable { await controller.refresh() }
      VStack(spacing: 0) {
        Divider()
        ReferralBillingCTA {
          guard let host = BrowtherReferralPresenter.topController() else { return }
          BrowtherReferralPresenter.present(.thanks, from: host)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 560)
      }
      .background(ReferralPalette.screen)
    }
  }
}

// MARK: - L'attente (trois états, jamais deux)

struct ReferralPendingView: View {
  @State private var slow = false

  var body: some View {
    VStack(spacing: 14) {
      ProgressView()
      if slow {
        Text(Strings.BrowtherReferral.homeUnreachable)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        Button(Strings.BrowtherReferral.retry) {
          Task { await BrowtherReferralController.shared.refresh() }
        }
        .buttonStyle(.bordered)
      }
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task {
      try? await Task.sleep(for: .seconds(6))
      slow = true
    }
  }
}

// MARK: - Partager (§ 12.1)

/// 🔴 Partager ne crée AUCUNE invitation : un partage abouti n'ouvre droit
/// qu'aux 3 jours (§ 4).
@MainActor
func referralShareMyCode(status: ReferralStatus, screen: String, onAchieved: (() -> Void)? = nil) {
  guard let host = BrowtherReferralPresenter.topController() else { return }
  ReferralSharing.share(status: status, from: host) { result in
    BrowtherReferralController.shared.track("referral_shared", ["screen": screen, "result": result.rawValue])
    guard result.achieved else { return }
    onAchieved?()
    BrowtherReferralController.shared.shareDone(from: screen)
  }
}

struct ReferralShareButton: View {
  let status: ReferralStatus
  var screen = "6"
  var onAchieved: (() -> Void)?

  var body: some View {
    ReferralPrimaryButton(label: Strings.BrowtherReferral.shareMyCode, systemImage: "square.and.arrow.up") {
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      referralShareMyCode(status: status, screen: screen, onAchieved: onAchieved)
    }
  }
}

/// La grammaire d'un onglet peu rempli (§ 12.26) : une icône dans un rond, un
/// titre, une phrase — CENTRÉS.
struct ReferralCenteredState<Content: View>: View {
  let systemImage: String
  var tone: ReferralRoundIcon.Tone = .green
  let title: String
  var message: String?
  @ViewBuilder var content: () -> Content

  var body: some View {
    GeometryReader { proxy in
    ScrollView {
      VStack(spacing: 18) {
        ReferralRoundIcon(systemName: systemImage, tone: tone, size: 76)
        VStack(spacing: 8) {
          Text(title)
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
          if let message {
            Text(message)
              .font(.body)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        content()
      }
      .padding(24)
      .frame(maxWidth: 520)
      .frame(maxWidth: .infinity, minHeight: proxy.size.height)
    }
    }
  }
}

// MARK: - Onglet « Inviter »

/// L'état, la carte, le partage, la jauge — ⚠️ la couverture a un libellé pour
/// CHAQUE cas connu, « avant l'annonce » compris (§ 12.11). ⛔ On n'annonce
/// jamais une pause qui n'est pas là.
struct ReferralInviteTab: View {
  let status: ReferralStatus
  var onCelebrate: () -> Void

  @ObservedObject private var controller = BrowtherReferralController.shared
  @State private var showsInfo = false

  var body: some View {
    let access = AccessState(status: status)
    let scale = MilestoneScale(status: status)
    let validated = status.milestones.validated
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 6) {
            Text(Strings.BrowtherReferral.coverA.uppercased())
              .font(.caption.weight(.semibold))
              .tracking(0.6)
              .foregroundStyle(.secondary)
            Button {
              showsInfo = true
            } label: {
              Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Strings.BrowtherReferral.whatExtras)
          }
          Text(coverage(access))
            .font(.title3.weight(.semibold))
          if access.isPaused(), !access.lifetime {
            Text(Strings.BrowtherReferral.whyPaused)
              .font(.footnote)
              .foregroundStyle(ReferralPalette.gold)
              .fixedSize(horizontal: false, vertical: true)
          }
          // ⛔ Rien à zéro (§ 12.26) : le compte n'apparaît que s'il y a quelque chose à compter.
          if validated > 0 {
            ReferralRichText(text: progressText(validated: validated, scale: scale, lifetime: access.lifetime))
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        ReferralCodeCard(status: status) {
          // ⭐ Copier EST un partage abouti (§ 12.20) : 3 jours offerts compris.
          controller.track("referral_shared", ["screen": "6", "result": "copied"])
          controller.shareDone(from: "6")
        }

        VStack(spacing: 8) {
          ReferralShareButton(status: status)
          Text(Strings.BrowtherReferral.inviteFoot(ReferralProduct.validationTargetDays))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }

        ReferralGaugeView(validated: validated, scale: scale, mode: .spring, onCelebrate: onCelebrate)
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 32)
      .frame(maxWidth: 560)
      .frame(maxWidth: .infinity)
    }
    .refreshable { await controller.refresh() }
    .sheet(isPresented: $showsInfo) {
      VStack(alignment: .leading, spacing: 16) {
        Text(Strings.BrowtherReferral.whatExtras)
          .font(.headline)
        ReferralFeatureList(extras: ExtrasState(status: status, access: access))
      }
      .padding(20)
      .presentationDetents([.medium])
      .presentationDragIndicator(.visible)
    }
  }

  private func coverage(_ access: AccessState) -> String {
    switch CoverageLabel(status: status, access: access) {
    case .lifetime: return Strings.BrowtherReferral.coverLifetime
    case .paid: return Strings.BrowtherReferral.coverPaid
    case .paused: return Strings.BrowtherReferral.coverPaused
    case .until(let date):
      return Strings.BrowtherReferral.coverUntil(BrowtherReferralController.formatDate(date, withYear: true))
    case .offered: return Strings.BrowtherReferral.coverOpen
    }
  }

  private func progressText(validated: Int, scale: MilestoneScale, lifetime: Bool) -> String {
    let months = status.milestones.monthsEarned
    guard !lifetime, let next = scale.next(after: validated) else {
      return Strings.BrowtherReferral.homeProgressLife(count: validated)
    }
    if next.lifetime {
      return Strings.BrowtherReferral.homeProgressToLife(count: validated, months: months, left: next.remaining)
    }
    return Strings.BrowtherReferral.homeProgress(
      count: validated,
      months: months,
      left: next.remaining,
      bonus: next.bonusMonths
    )
  }
}

// MARK: - Onglet « Invitations »

struct ReferralInvitationsTab: View {
  let status: ReferralStatus
  @ObservedObject private var controller = BrowtherReferralController.shared

  var body: some View {
    let invitations = ReferralInvitations.known(status.invitations.items)
    // ⭐ Le seul signal d'« ouverture » qu'on connaisse : les clics sur LE
    // lien, tous proches confondus — ⛔ jamais par invitation (§ 12.1).
    let opens = status.referral.clicks ?? 0
    if invitations.isEmpty {
      ReferralCenteredState(
        systemImage: "paperplane",
        title: Strings.BrowtherReferral.homeEmpty,
        message: Strings.BrowtherReferral.homeEmptyHint
      ) {
        ReferralShareButton(status: status)
          .padding(.top, 6)
        if opens > 0 {
          Text(Strings.BrowtherReferral.homeLinkOpens(opens))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .refreshable { await controller.refresh() }
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if opens > 0 {
            Text(Strings.BrowtherReferral.homeLinkOpens(opens))
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          ReferralInvitationList(items: invitations, scale: MilestoneScale(status: status))
          Text(Strings.BrowtherReferral.homeLegend)
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
      }
      .refreshable { await controller.refresh() }
    }
  }
}

// MARK: - Onglet « Code reçu »

/// **Quand on t'invite** (§ 5.3) : saisir le code d'un proche, puis suivre sa
/// propre validation. ⭐ Sans parrain, c'est **l'écran O lui-même**. ⛔ Rien du
/// parrain n'y figure.
struct ReferralCodeTab: View {
  let status: ReferralStatus
  var onCelebrate: () -> Void
  var onInvite: () -> Void

  @State private var justRedeemed = false

  var body: some View {
    if let referred = status.referredBy, !justRedeemed {
      refereeCard(referred)
    } else {
      ScrollView {
        ReferralWelcomeContent(source: "manual") {
          justRedeemed = true
          onCelebrate()
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively)
    }
  }

  private func refereeCard(_ referred: ReferralStatus.ReferredBy) -> some View {
    let done = referred.status == .validated
    let target = ReferralProduct.validationTargetDays
    let left = ReferralInvitations.daysLeft(referred.progress)
    return ReferralCenteredState(
      systemImage: done ? "checkmark" : "gift.fill",
      tone: .gold,
      title: Strings.BrowtherReferral.refereeTitle,
      message: done
        ? Strings.BrowtherReferral.refereeDone
        : left.map(Strings.BrowtherReferral.refereeProgress) ?? Strings.BrowtherReferral.refereeHint(target)
    ) {
      if !done, let progress = referred.progress {
        VStack(spacing: 6) {
          ReferralMeter(ratio: ReferralInvitations.ratio(progress))
          Text(Strings.BrowtherReferral.refereeMeter(current: Int(progress.current), target: Int(progress.target)))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 280)
      }
      if !done {
        // ⭐ Ce qui valide l'invitation du proche, c'est Browther PAR DÉFAUT (§ 9).
        ReferralSecondaryButton(label: Strings.BrowtherReferral.refereeSetDefault) {
          guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
          UIApplication.shared.open(url)
        }
        .padding(.top, 4)
      } else {
        ReferralPrimaryButton(label: Strings.BrowtherReferral.refereeInviteToo, action: onInvite)
          .padding(.top, 4)
      }
    }
  }
}
