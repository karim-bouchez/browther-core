// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AuthenticationServices
import BraveStrings
import BrowtherReferral
import SwiftUI
import UIKit

/// Le **compte dev&din FACULTATIF** sur iPhone — le contrat commun à toutes les
/// apps (`docs/PARRAINAGE.md` § 7.1, tableau « Le contrat »), repris de
/// l'implémentation de référence (`fajrunaa/components/referral/AccountEntry.tsx`
/// et `AccountScreen.tsx`) ; pendant de `private/webui/referral/src/ui/Account.tsx`
/// (desktop). Règles pures : `BrowtherReferral/ReferralAccountRules.swift`.
///
/// ## Où il se trouve — ⛔ jamais derrière un défilement
///
/// - **L'en-tête de l'écran Parrainage** : un bouclier en face du retour, sur
///   TOUS les onglets — gris, puis vert et coché une fois connecté
///   (`ReferralHomeHostingController`). C'est par là qu'on voit avec quel
///   compte on est connecté, qu'on se déconnecte, qu'on supprime, et qu'on
///   RETROUVE un compte sur un iPhone neuf, où l'on n'a rien en jeu par
///   définition.
/// - **Les Paramètres** : la ligne « Compte dev&din », avec son état en clair
///   (`ReferralAccountSettingsRow`) — c'est elle qui porte le libellé que le
///   bouclier n'a pas.
/// - ⛔ Plus de bloc « Sur tes autres appareils » en bas de l'onglet « Inviter »
///   (Karim, 2026-10-07, sur Fajrunaa : c'est l'onglet le plus chargé, il
///   fallait défiler pour y arriver — « de base, on ne le voit pas »).
///
/// ## Où il se propose — dans l'onglet de ce qui est en jeu, avec SES mots
///
/// Une seule rangée (`ReferralAccountHint`), quatre enjeux
/// (`ReferralAccountStakes`) : « Mets ton code à l'abri » (Inviter, dès qu'un
/// partage aboutit), « tes invitations » (Invitations), « ton mois offert »
/// (Code reçu, dès qu'un code est saisi), « ton abonnement » (Soutenir).
/// ⛔ Rien pour qui est déjà connecté.
///
/// ⭐ **Une PAGE, pas une feuille** : on y arrive de l'en-tête, d'une rangée,
/// des Paramètres, de l'écran de paiement et de « Merci » — et elle porte son
/// champ de saisie (le code de suppression) sans se battre avec le clavier.
///
/// ⚠️ **À l'écran on dit « parrainage », ⛔ pas « soutien »** : le mot se lisait
/// « soutien financier », et qui n'a rien payé ne s'y reconnaissait pas
/// (recette Fajrunaa, 2026-10-07). Le message de connexion NOMME ce qui suit.

/// D'où l'on ouvre la page du compte — la valeur de `screen` dans
/// `paywall_action {action: "account"}`.
enum ReferralAccountOrigin: String {
  case home, settings, billing, thanks, validated
}

extension BrowtherReferralPresenter {
  /// Ouvre la page du compte. ⚠️ Poussée dans la navigation en place (l'écran
  /// Parrainage, les Paramètres) ; depuis une fenêtre du flow, qui n'en a pas,
  /// elle s'ouvre dans la sienne, avec sa croix.
  @MainActor
  static func openAccount(from origin: ReferralAccountOrigin, note: ReferralNote) {
    note(.paywallAction, ["screen": origin.rawValue, "action": "account"])
    guard let top = topController() else { return }
    if let navigation = (top as? UINavigationController) ?? top.navigationController {
      navigation.pushViewController(ReferralAccountHostingController(showsClose: false), animated: true)
      return
    }
    let navigation = UINavigationController(rootViewController: ReferralAccountHostingController(showsClose: true))
    navigation.modalPresentationStyle = .pageSheet
    navigation.sheetPresentationController?.detents = [.large()]
    top.present(navigation, animated: true)
  }
}

final class ReferralAccountHostingController: UIHostingController<ReferralAccountPage> {
  @MainActor
  init(showsClose: Bool) {
    super.init(rootView: ReferralAccountPage())
    // Le fond de Brave sous SwiftUI : sinon un éclair noir au push.
    view.backgroundColor = .braveGroupedBackground
    title = Strings.BrowtherReferral.accountTitle
    if showsClose {
      navigationItem.leftBarButtonItem = UIBarButtonItem(
        systemItem: .close,
        primaryAction: UIAction { [weak self] _ in
          self?.dismiss(animated: true)
        }
      )
    }
  }

  @available(*, unavailable)
  required dynamic init?(coder aDecoder: NSCoder) {
    fatalError()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    BrowtherReferralController.shared.boot()
  }
}

/// La page du compte : se connecter (le QR d'abord, « autrement » ensuite), ou
/// — connecté — relier un ordinateur, se déconnecter, supprimer.
///
/// ⭐ **L'appareil connecté affiche un QR, l'autre le scanne** (recette Karim,
/// 2026-09-24 : se connecter sur chaque appareil était lent, et ouvrait le
/// piège des deux comptes). Le geste principal reste donc « Scanner le QR de
/// mon ordinateur » — il marche dans les deux sens (`ReferralLinkFlowSheet`) ;
/// se connecter « autrement » (Google, Apple, code e-mail) est là pour qui n'a
/// qu'un appareil sous la main. ⛔ Jamais exigé : le parrainage marche sans.
struct ReferralAccountPage: View {
  @ObservedObject private var controller = BrowtherReferralController.shared
  @State private var showsSignIn = false
  @State private var showsScanner = false
  @State private var signingOut = false
  /// Une suppression est en route : ⛔ on ne se déconnecte pas pendant.
  @State private var deleting = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if let account = controller.account {
          connected(account)
        } else {
          signedOut
        }
        // 🔴 Ce que le compte porte, et ce qu'il ne portera jamais — dit tel
        // quel, dans les deux états.
        Text(Strings.BrowtherReferral.accountOnly)
          .font(.footnote)
          .foregroundStyle(Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(20)
      .frame(maxWidth: 560, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
    .background(ReferralPalette.screen.ignoresSafeArea())
    .sheet(isPresented: $showsSignIn) {
      ReferralSignInSheet()
    }
    .sheet(isPresented: $showsScanner) {
      ReferralLinkFlowSheet(start: nil)
    }
  }

  @ViewBuilder private var signedOut: some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: "shield")
        .font(.system(size: 26, weight: .medium))
        .foregroundStyle(Color.primary)
      Text(Strings.BrowtherReferral.accountHead)
        .font(.title3.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
      // « Mettre à l'abri » ne se dit que s'il y a quelque chose à perdre ; qui
      // arrive sur un iPhone neuf RETROUVE un compte.
      Text(
        controller.accountStakes.hasSomethingToShelter
          ? Strings.BrowtherReferral.accountBodyShelter
          : Strings.BrowtherReferral.accountBodyRecover
      )
      .font(.body)
      .foregroundStyle(Color.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    VStack(spacing: 10) {
      ReferralPrimaryButton(label: Strings.BrowtherReferral.accountScan, systemImage: "qrcode.viewfinder") {
        showsScanner = true
      }
      Text(Strings.BrowtherReferral.accountScanHint)
        .font(.footnote)
        .foregroundStyle(Color.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      ReferralSecondaryButton(label: Strings.BrowtherReferral.accountOtherWay) {
        showsSignIn = true
      }
    }
    sameWay
  }

  @ViewBuilder private func connected(_ account: ReferralAccount) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: "checkmark.shield.fill")
        .font(.system(size: 26, weight: .medium))
        .foregroundStyle(ReferralPalette.green)
      Text(Self.connectedLine(account))
        .font(.title3.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
      Text(Strings.BrowtherReferral.accountConnectedBody)
        .font(.body)
        .foregroundStyle(Color.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    sameWay
    VStack(spacing: 10) {
      // Connecté ici : c'est CET iPhone qui autorise l'ordinateur.
      ReferralSecondaryButton(label: Strings.BrowtherReferral.accountScanComputer) {
        showsScanner = true
      }
      ReferralSecondaryButton(label: Strings.BrowtherReferral.accountSignOut) {
        signingOut = true
        Task {
          await controller.signOut()
          signingOut = false
        }
      }
      .disabled(signingOut || deleting)
      .opacity(signingOut || deleting ? 0.45 : 1)
    }
    ReferralAccountDeletion(busy: $deleting)
      .disabled(signingOut)
  }

  /// ⚠️ « De la même façon » : Apple « masquer mon adresse » d'un côté et Google
  /// de l'autre font DEUX comptes, et rien ne passe — le piège du § 7.1.
  private var sameWay: some View {
    Text(Strings.BrowtherReferral.accountSameWay)
      .font(.footnote)
      .foregroundStyle(Color.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// Un compte Apple à adresse masquée se nomme « avec Apple », pas par son
  /// relais illisible (`ReferralAccountLabel`).
  static func connectedLine(_ account: ReferralAccount) -> String {
    switch ReferralAccountLabel(account) {
    case .email(let email): return Strings.BrowtherReferral.accountConnectedAs(email)
    case .apple: return Strings.BrowtherReferral.accountConnectedApple
    case .unknown: return Strings.BrowtherReferral.accountConnected
    }
  }
}

// MARK: - Supprimer le compte

/// 🔴 **La suppression du compte vit ICI, dans l'app** (Apple 5.1.1(v)), en deux
/// temps : ce qui part, puis le code à six chiffres reçu par e-mail. Elle
/// supprime le compte pour TOUTES les apps dev&din, et l'écran le dit avant de
/// demander le code. ⛔ Ne jamais la cacher ni la renvoyer vers un site.
///
/// ⭐ **Un refus se dit AVANT le code** : en ouvrant « Supprimer mon compte », on
/// demande au serveur si ce compte peut l'être d'ici
/// (`checkAccountDeletable`) — un compte bloqué voit pourquoi, sans rouge ni
/// bouton, et ne reçoit aucun code. ⚠️ Sans réponse, on n'ouvre RIEN. Le
/// serveur garde le dernier mot (`.usedElsewhere`).
struct ReferralAccountDeletion: View {
  private enum Step: Equatable {
    case closed
    case warning
    case code(destination: String)
    /// Le compte ne se supprime pas d'ici — `apps` nomme celles qu'on connaît.
    case blocked(apps: [String])
  }

  /// ⚠️ Un état d'attente PAR bouton : sinon tous tournent quand on en touche un.
  private enum Busy {
    case check, send, delete
  }

  /// Dit à la page qu'une suppression est en route.
  @Binding var busy: Bool

  @ObservedObject private var controller = BrowtherReferralController.shared
  @State private var step: Step = .closed
  @State private var working: Busy?
  @State private var code = ""
  @State private var problem: String?
  @FocusState private var focused: Bool

  var body: some View {
    Group {
      switch step {
      case .closed: closed
      case .blocked(let apps): blocked(apps)
      case .warning: danger { warning }
      case .code(let destination): danger { codeStep(destination) }
      }
    }
    .onChange(of: working) { _, next in
      busy = next != nil
    }
  }

  private var closed: some View {
    VStack(spacing: 8) {
      Button {
        open()
      } label: {
        ZStack {
          Text(Strings.BrowtherReferral.accountDelete)
            .font(.subheadline.weight(.medium))
            .underline()
            .foregroundStyle(Color.red)
            .opacity(working == .check ? 0 : 1)
          if working == .check { ProgressView() }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(working != nil)
      problemLine
    }
    .frame(maxWidth: .infinity)
  }

  /// ⚠️ Ni rouge ni bouton de suppression : il n'y a rien à supprimer d'ici.
  private func blocked(_ apps: [String]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(Strings.BrowtherReferral.accountDelete)
        .font(.headline)
      Text(
        apps.isEmpty
          ? Strings.BrowtherReferral.accountDeleteElsewhereUnknown
          : Strings.BrowtherReferral.accountDeleteElsewhere(apps.joined(separator: ", "))
      )
      .font(.subheadline)
      .foregroundStyle(Color.secondary)
      .fixedSize(horizontal: false, vertical: true)
      textLink(Strings.BrowtherReferral.close) { close() }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(ReferralPalette.line, lineWidth: 1)
    }
  }

  private func danger<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(Strings.BrowtherReferral.accountDelete)
        .font(.headline)
      content()
      problemLine
      textLink(Strings.BrowtherReferral.accountCancel) { close() }
        .disabled(working != nil)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(Color.red.opacity(0.55), lineWidth: 1)
    }
  }

  @ViewBuilder private var warning: some View {
    Text(Strings.BrowtherReferral.accountDeleteBody)
      .font(.subheadline)
      .foregroundStyle(Color.secondary)
      .fixedSize(horizontal: false, vertical: true)
    // ⚠️ Un abonnement Apple en cours n'est PAS résilié par la suppression.
    Text(Strings.BrowtherReferral.accountDeleteSubscription)
      .font(.footnote)
      .foregroundStyle(Color.secondary)
      .fixedSize(horizontal: false, vertical: true)
    dangerButton(Strings.BrowtherReferral.accountDeleteSend, filled: false, spinning: working == .send) {
      askCode()
    }
    .disabled(working != nil)
  }

  @ViewBuilder private func codeStep(_ destination: String) -> some View {
    Text(Strings.BrowtherReferral.accountDeleteSent(destination))
      .font(.footnote)
      .foregroundStyle(Color.secondary)
      .fixedSize(horizontal: false, vertical: true)
    TextField("123456", text: $code)
      .textContentType(.oneTimeCode)
      .keyboardType(.numberPad)
      .font(.title2.monospacedDigit())
      .multilineTextAlignment(.center)
      .focused($focused)
      .padding(14)
      .background(ReferralPalette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .disabled(working != nil)
      .onChange(of: code) { _, next in
        let digits = String(next.filter { $0.isASCII && $0.isNumber }.prefix(ReferralDeletion.codeLength))
        if digits != next { code = digits }
        problem = nil
      }
      .onAppear { focused = true }
    // ⛔ Pas de validation automatique au sixième chiffre : supprimer un compte
    // se CONFIRME, d'un bouton rouge plein.
    dangerButton(Strings.BrowtherReferral.accountDeleteConfirm, filled: true, spinning: working == .delete) {
      confirm()
    }
    .disabled(working != nil || ReferralDeletion.normalizeCode(code) == nil)
    .opacity(ReferralDeletion.normalizeCode(code) == nil ? 0.45 : 1)
  }

  @ViewBuilder private var problemLine: some View {
    if let problem {
      Text(problem)
        .font(.footnote)
        .foregroundStyle(Color.red)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// Un geste qui supprime : cerclé pour demander le code, PLEIN pour supprimer.
  private func dangerButton(
    _ label: String,
    filled: Bool,
    spinning: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      ZStack {
        Text(label)
          .font(.body.weight(.semibold))
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .opacity(spinning ? 0 : 1)
        if spinning { ProgressView().tint(filled ? Color.white : Color.red) }
      }
      .foregroundStyle(filled ? Color.white : Color.red)
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity, minHeight: 50)
      .background {
        if filled {
          RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.red)
        } else {
          RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.red.opacity(0.6), lineWidth: 1.5)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func textLink(_ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(label)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.primary)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
  }

  // MARK: Les gestes

  private func open() {
    problem = nil
    working = .check
    Task { @MainActor in
      let verdict = await controller.checkAccountDeletable()
      working = nil
      switch verdict {
      case .deletable: step = .warning
      case .blocked(let apps): step = .blocked(apps: apps)
      // ⚠️ Sans réponse, on n'ouvre RIEN : pas de code envoyé sur un « on ne sait pas ».
      case .unreachable: fail(Strings.BrowtherReferral.accountUnreachable)
      case .failed: fail(Strings.BrowtherReferral.accountDeleteFailed)
      }
    }
  }

  private func askCode() {
    problem = nil
    working = .send
    Task { @MainActor in
      let sent = await controller.requestAccountDeletionCode()
      working = nil
      switch sent {
      case .sent(let destination):
        code = ""
        step = .code(destination: destination)
      case .unreachable: fail(Strings.BrowtherReferral.accountUnreachable)
      case .failed: fail(Strings.BrowtherReferral.accountDeleteSendFailed)
      }
    }
  }

  private func confirm() {
    guard let digits = ReferralDeletion.normalizeCode(code), working == nil else { return }
    problem = nil
    focused = false
    working = .delete
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
    Task { @MainActor in
      let outcome = await controller.deleteConnectedAccount(code: digits)
      working = nil
      switch outcome {
      case .deleted:
        // ⚠️ Rien après : le compte parti, cette vue n'existe plus.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        BrowtherReferralToast.show(title: Strings.BrowtherReferral.accountDeleted, persistent: false, duration: 6)
      // Le serveur garde le dernier mot : s'il refuse malgré la question posée
      // à l'ouverture, on le dit de la même façon.
      case .usedElsewhere(let apps):
        step = .blocked(apps: apps)
      case .badCode:
        code = ""
        fail(Strings.BrowtherReferral.accountBadCode)
      case .unreachable: fail(Strings.BrowtherReferral.accountUnreachable)
      case .failed: fail(Strings.BrowtherReferral.accountDeleteFailed)
      }
    }
  }

  private func fail(_ message: String) {
    UINotificationFeedbackGenerator().notificationOccurred(.error)
    problem = message
  }

  private func close() {
    focused = false
    problem = nil
    code = ""
    step = .closed
  }
}

// MARK: - La proposition, onglet par onglet

/// Ce que l'onglet contient est en jeu : la rangée le dit avec SES mots, et
/// mène à la page du compte. ⭐ Elle apparaît sur l'écran où l'on EST, au
/// moment où l'enjeu naît — juste après un partage, juste après la saisie d'un
/// code. ⛔ Rien pour qui est déjà connecté.
struct ReferralAccountHint: View {
  let stake: ReferralAccountStake

  @ObservedObject private var controller = BrowtherReferralController.shared
  @Environment(\.referralNote) private var note

  var body: some View {
    if controller.account == nil, controller.accountStakes[stake] {
      Button {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // « Soutenir » est aussi l'écran de paiement : sa provenance le dit.
        BrowtherReferralPresenter.openAccount(from: stake == .paid ? .billing : .home, note: note)
      } label: {
        HStack(spacing: 12) {
          Image(systemName: "checkmark.shield.fill")
            .font(.system(size: 20))
            .foregroundStyle(ReferralPalette.gold)
          VStack(alignment: .leading, spacing: 2) {
            Text(texts.title)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(Color.primary)
            Text(texts.sub)
              .font(.footnote)
              .foregroundStyle(Color.secondary)
          }
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          Image(systemName: "chevron.forward")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ReferralPalette.goldSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(ReferralPalette.gold.opacity(0.3), lineWidth: 1)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  private var texts: (title: String, sub: String) {
    switch stake {
    case .invite:
      return (Strings.BrowtherReferral.accountHintInviteTitle, Strings.BrowtherReferral.accountHintInviteSub)
    case .invitations:
      return (Strings.BrowtherReferral.accountHintInvitationsTitle, Strings.BrowtherReferral.accountHintInvitationsSub)
    case .referee:
      return (Strings.BrowtherReferral.accountHintRefereeTitle, Strings.BrowtherReferral.accountHintRefereeSub)
    case .paid:
      return (Strings.BrowtherReferral.accountHintPaidTitle, Strings.BrowtherReferral.accountHintPaidSub)
    }
  }
}

// MARK: - La ligne des Paramètres

/// « Compte dev&din », avec son état en clair : « Non connecté », ou l'adresse.
/// C'est là qu'on cherche un compte, et c'est elle qui porte le libellé que le
/// bouclier de l'écran Parrainage n'a pas.
struct ReferralAccountSettingsRow: View {
  @ObservedObject private var controller = BrowtherReferralController.shared

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: controller.account == nil ? "shield" : "checkmark.shield.fill")
        .font(.system(size: 20))
        .foregroundStyle(controller.account == nil ? Color.secondary : ReferralPalette.green)
        .frame(width: 32)
      VStack(alignment: .leading, spacing: 2) {
        Text(Strings.BrowtherReferral.accountTitle)
          .font(.body)
          .foregroundStyle(Color.primary)
        Text(state)
          .font(.footnote)
          .foregroundStyle(Color.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer(minLength: 8)
      Image(systemName: "chevron.forward")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color(UIColor.tertiaryLabel))
    }
    .padding(.vertical, 2)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private var state: String {
    guard let account = controller.account else { return Strings.BrowtherReferral.accountOff }
    if case .email(let email) = ReferralAccountLabel(account) { return email }
    return Strings.BrowtherReferral.accountOn
  }
}

/// **Relier par QR**, dans les deux sens — depuis le scanner de la section, ou
/// depuis un lien ouvert dans Browther (l'appareil photo, quand Browther est le
/// navigateur par défaut : `NavigationPath.handleURL`).
///
/// | QR scanné | Cet iPhone | Ce qui se passe |
/// |---|---|---|
/// | `/link?c=…` (ordinateur CONNECTÉ) | quel qu'il soit | « Connecter cet iPhone au compte … ? » → sa propre session |
/// | `/device?user_code=…` (ordinateur NON connecté) | connecté | « Autoriser Browther sur cet ordinateur ? » (code à vérifier) → l'ordinateur reçoit sa session |
/// | idem | non connecté | se connecter d'abord (une fois), puis l'autorisation enchaîne |
struct ReferralLinkFlowSheet: View {
  private enum Step: Equatable {
    case scanning
    case checking
    case confirmLink(code: String, email: String?)
    case confirmComputer(userCode: String)
    case needSignIn(userCode: String)
    case problem(String)
  }

  let start: ReferralLinkTarget?

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var controller = BrowtherReferralController.shared
  @State private var step: Step = .scanning
  @State private var busy = false
  @State private var showsSignIn = false
  @State private var rejected = false

  var body: some View {
    NavigationStack {
      Group {
        switch step {
        case .scanning: scanner
        case .checking: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .confirmLink(let code, let email):
          confirm(
            icon: "iphone",
            title: email.map(Strings.BrowtherReferral.accountLinkConfirm) ?? Strings.BrowtherReferral.accountLinkConfirmGeneric,
            body: Strings.BrowtherReferral.accountOnly,
            cta: Strings.BrowtherReferral.accountLinkCta
          ) { link(code) }
        case .confirmComputer(let userCode):
          confirm(
            icon: "laptopcomputer",
            title: Strings.BrowtherReferral.accountApproveTitle,
            body: Strings.BrowtherReferral.accountApproveBody(ReferralLinkTarget.display(userCode)),
            cta: Strings.BrowtherReferral.accountApproveCta
          ) { approve(userCode) }
        case .needSignIn:
          confirm(
            icon: "person.crop.circle.badge.checkmark",
            title: Strings.BrowtherReferral.accountApproveTitle,
            body: Strings.BrowtherReferral.accountSignInFirst,
            cta: Strings.BrowtherReferral.accountConnect
          ) { showsSignIn = true }
        case .problem(let message):
          confirm(
            icon: "exclamationmark.triangle",
            title: message,
            body: nil,
            cta: Strings.BrowtherReferral.accountRetry
          ) { step = .scanning }
        }
      }
      .background(ReferralPalette.screen.ignoresSafeArea())
      .navigationTitle(Strings.BrowtherReferral.accountTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(Strings.BrowtherReferral.accountCancel) { dismiss() }
        }
      }
    }
    .presentationDetents([.large])
    .interactiveDismissDisabled(busy)
    .onAppear {
      if let start, step == .scanning { handle(start) }
    }
    .sheet(isPresented: $showsSignIn, onDismiss: afterSignIn) {
      ReferralSignInSheet()
    }
  }

  private var scanner: some View {
    VStack(spacing: 16) {
      ReferralQRScanner { text in
        guard step == .scanning else { return }
        if let target = ReferralLinkTarget(scanned: text) {
          UINotificationFeedbackGenerator().notificationOccurred(.success)
          handle(target)
        } else {
          rejected = true
        }
      }
      .aspectRatio(1, contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      Text(rejected ? Strings.BrowtherReferral.accountScanUnknown : Strings.BrowtherReferral.accountScanHint)
        .font(.subheadline)
        .foregroundStyle(rejected ? Color.red : Color.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(20)
    .frame(maxWidth: 520)
    .frame(maxWidth: .infinity)
  }

  private func confirm(
    icon: String,
    title: String,
    body: String?,
    cta: String,
    action: @escaping () -> Void
  ) -> some View {
    ReferralCenteredState(systemImage: icon, title: title, message: body) {
      ZStack {
        ReferralPrimaryButton(label: cta, action: action)
          .opacity(busy ? 0 : 1)
        if busy { ProgressView() }
      }
      .disabled(busy)
      .padding(.top, 8)
    }
  }

  // MARK: - Les gestes

  private func handle(_ target: ReferralLinkTarget) {
    switch target {
    case .link(let code):
      step = .checking
      Task { @MainActor in
        switch await controller.peekLink(code: code) {
        case .success(let email): step = .confirmLink(code: code, email: email)
        case .failure(let failure): step = .problem(message(failure.outcome))
        }
      }
    case .computer(let userCode):
      step = controller.account == nil ? .needSignIn(userCode: userCode) : .confirmComputer(userCode: userCode)
    }
  }

  /// Revenu de la connexion : si elle a abouti, l'autorisation enchaîne.
  private func afterSignIn() {
    guard case .needSignIn(let userCode) = step, controller.account != nil else { return }
    step = .confirmComputer(userCode: userCode)
  }

  private func link(_ code: String) {
    run(done: nil) { await controller.linkWithCode(code) }
  }

  private func approve(_ userCode: String) {
    run(done: Strings.BrowtherReferral.accountApproved) { await controller.approveComputer(userCode: userCode) }
  }

  /// `done: nil` = une CONNEXION de cet iPhone : le message nomme ce qui suit.
  private func run(done: String?, _ attempt: @escaping @MainActor () async -> BrowtherReferralController.ConnectOutcome) {
    busy = true
    Task { @MainActor in
      let outcome = await attempt()
      busy = false
      if outcome == .connected {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
        BrowtherReferralToast.show(title: done ?? ReferralSignInSheet.linkedMessage(), persistent: false, duration: 6)
      } else if outcome != .cancelled {
        step = .problem(message(outcome))
      }
    }
  }

  private func message(_ outcome: BrowtherReferralController.ConnectOutcome) -> String {
    switch outcome {
    case .badCode: return Strings.BrowtherReferral.accountExpired
    case .unreachable: return Strings.BrowtherReferral.accountUnreachable
    default: return Strings.BrowtherReferral.accountError
    }
  }

  // MARK: - Ouvert par un lien

  /// Un lien `auth.devndin.com/link` ou `/device` ouvert DANS Browther (QR
  /// scanné par l'appareil photo, Browther navigateur par défaut) : la feuille
  /// s'ouvre directement sur la confirmation. `false` = ce n'est pas le nôtre.
  /// ⚠️ `nonisolated` : le routeur de Brave (`NavigationPath.handleURL`) n'est
  /// pas isolé, mais il est toujours appelé sur le fil principal.
  nonisolated static func present(for url: URL) -> Bool {
    guard let target = ReferralLinkTarget(url) else { return false }
    return MainActor.assumeIsolated {
      guard BrowtherReferralController.shared.enabled,
        let host = BrowtherReferralPresenter.topController()
      else { return false }
      BrowtherReferralController.shared.boot()
      let sheet = UIHostingController(rootView: ReferralLinkFlowSheet(start: target))
      host.present(sheet, animated: true)
      return true
    }
  }
}

/// La caméra de Sync de Brave (`SyncCameraView`), réutilisée : elle gère déjà
/// l'autorisation et le renvoi vers les Réglages quand elle est refusée.
struct ReferralQRScanner: UIViewRepresentable {
  let onScan: (String) -> Void

  func makeUIView(context: Context) -> SyncCameraView {
    let view = SyncCameraView(frame: .zero)
    view.scanCallback = { text in
      DispatchQueue.main.async { onScan(text) }
    }
    view.startRunning()
    return view
  }

  func updateUIView(_ view: SyncCameraView, context: Context) {}

  static func dismantleUIView(_ view: SyncCameraView, coordinator: ()) {
    view.stopRunning()
  }
}

/// La connexion elle-même : Apple, Google (la page dev&din dans une feuille
/// système), ou un code reçu par e-mail. Une connexion aboutie referme la
/// feuille et le DIT (toast) : le statut du compte a déjà remplacé celui de
/// l'appareil.
struct ReferralSignInSheet: View {
  private enum Step: Equatable {
    case choose
    case email
    case code(String)
  }

  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var controller = BrowtherReferralController.shared
  @State private var step: Step = .choose
  @State private var email = ""
  @State private var code = ""
  @State private var busy = false
  @State private var problem: String?
  @FocusState private var focused: Bool

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          switch step {
          case .choose: choose
          case .email: emailStep
          case .code(let address): codeStep(address)
          }
          if let problem {
            Text(problem)
              .font(.footnote)
              .foregroundStyle(.red)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(20)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
      }
      .background(ReferralPalette.screen.ignoresSafeArea())
      .navigationTitle(Strings.BrowtherReferral.accountConnect)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(Strings.BrowtherReferral.accountCancel) { dismiss() }
        }
      }
      .disabled(busy)
      .overlay {
        if busy { ProgressView() }
      }
    }
    .presentationDetents([.large])
  }

  /// ⭐ **Google en tête, avec « Recommandé »** (`docs/AUTH.md` § « Quel SSO
  /// mettre en avant ») : une adresse réelle et vérifiée, sur tous les
  /// systèmes. Apple ensuite, puis le code par e-mail.
  private var choose: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(
        controller.accountStakes.hasSomethingToShelter
          ? Strings.BrowtherReferral.accountBodyShelter
          : Strings.BrowtherReferral.accountBodyRecover
      )
      .font(.body)
      .fixedSize(horizontal: false, vertical: true)
      VStack(spacing: 10) {
        Button {
          web(.google)
        } label: {
          Label(Strings.BrowtherReferral.accountWithGoogle, systemImage: "globe")
            .font(.body.weight(.semibold))
            .foregroundStyle(Color(UIColor.systemBackground))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
          ReferralStamp(text: Strings.BrowtherReferral.accountRecommended)
        }
        .accessibilityLabel("\(Strings.BrowtherReferral.accountWithGoogle) · \(Strings.BrowtherReferral.accountRecommended)")
        // Le tampon dépasse du bouton par le haut : la place qu'il lui faut.
        .padding(.top, 6)
        Button {
          web(.apple)
        } label: {
          Label(Strings.BrowtherReferral.accountWithApple, systemImage: "apple.logo")
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(BrowtherIntroOutlineButtonStyle())
        Button {
          problem = nil
          step = .email
        } label: {
          Label(Strings.BrowtherReferral.accountWithEmail, systemImage: "envelope")
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(BrowtherIntroOutlineButtonStyle())
      }
      // ⚠️ Le piège des deux comptes, dit là où l'on choisit sa porte.
      Text(Strings.BrowtherReferral.accountSameWay)
        .font(.footnote)
        .foregroundStyle(Color.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Text(Strings.BrowtherReferral.accountOnly)
        .font(.footnote)
        .foregroundStyle(Color.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var emailStep: some View {
    VStack(alignment: .leading, spacing: 14) {
      TextField(Strings.BrowtherReferral.accountEmailPlaceholder, text: $email)
        .textContentType(.emailAddress)
        .keyboardType(.emailAddress)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.send)
        .focused($focused)
        .onSubmit(sendCode)
        .padding(14)
        .background(ReferralPalette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      ReferralPrimaryButton(label: Strings.BrowtherReferral.accountSendCode, action: sendCode)
        .disabled(!Self.looksLikeEmail(email))
        .opacity(Self.looksLikeEmail(email) ? 1 : 0.4)
      back
    }
    .onAppear { focused = true }
  }

  private func codeStep(_ address: String) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(Strings.BrowtherReferral.accountCodeSent(address))
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
      TextField("123456", text: $code)
        .textContentType(.oneTimeCode)
        .keyboardType(.numberPad)
        .font(.title2.monospacedDigit())
        .multilineTextAlignment(.center)
        .focused($focused)
        .padding(14)
        .background(ReferralPalette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onChange(of: code) { _, next in
          let digits = String(next.filter(\.isNumber).prefix(6))
          if digits != next { code = digits }
          if digits.count == 6 { verify(address) }
        }
      ReferralPrimaryButton(label: Strings.BrowtherReferral.accountVerify) { verify(address) }
        .disabled(code.count != 6)
        .opacity(code.count == 6 ? 1 : 0.4)
      back
    }
    .onAppear { focused = true }
  }

  private var back: some View {
    Button(Strings.BrowtherReferral.accountRetry) {
      problem = nil
      code = ""
      step = .choose
    }
    .font(.footnote.weight(.semibold))
    .frame(maxWidth: .infinity)
  }

  private static func looksLikeEmail(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespaces)
    guard let at = trimmed.firstIndex(of: "@") else { return false }
    return at != trimmed.startIndex && trimmed[at...].contains(".") && !trimmed.contains(" ")
  }

  // MARK: - Les gestes

  private func web(_ provider: ReferralAuthClient.Provider) {
    run { await controller.signIn(with: provider) }
  }

  private func sendCode() {
    let address = email.trimmingCharacters(in: .whitespaces).lowercased()
    guard Self.looksLikeEmail(address), !busy else { return }
    problem = nil
    busy = true
    Task { @MainActor in
      let failure = await controller.sendEmailCode(to: address)
      busy = false
      if let failure {
        problem = message(failure)
      } else {
        code = ""
        step = .code(address)
      }
    }
  }

  private func verify(_ address: String) {
    guard code.count == 6, !busy else { return }
    let entered = code
    run { await controller.verifyEmailCode(email: address, code: entered) }
  }

  private func run(_ attempt: @escaping @MainActor () async -> BrowtherReferralController.ConnectOutcome) {
    problem = nil
    busy = true
    Task { @MainActor in
      let outcome = await attempt()
      busy = false
      switch outcome {
      case .connected:
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
        BrowtherReferralToast.show(title: Self.linkedMessage(), persistent: false, duration: 6)
      case .cancelled:
        break
      case .badCode:
        code = ""
        problem = message(.badCode)
      case .unreachable, .failed:
        problem = message(outcome)
      }
    }
  }

  private func message(_ outcome: BrowtherReferralController.ConnectOutcome) -> String? {
    switch outcome {
    case .connected, .cancelled: return nil
    case .badCode: return Strings.BrowtherReferral.accountBadCode
    case .unreachable: return Strings.BrowtherReferral.accountUnreachable
    case .failed: return Strings.BrowtherReferral.accountError
    }
  }

  /// ⭐ Le message de connexion NOMME ce qui suit (code, invitations, mois
  /// gagnés) — ⛔ pas « ton soutien », qui se lisait « soutien financier ».
  /// L'abonnement n'est cité que s'il y en a un.
  @MainActor
  static func linkedMessage() -> String {
    BrowtherReferralController.shared.known?.subscription.active == true
      ? Strings.BrowtherReferral.accountLinkedPaid
      : Strings.BrowtherReferral.accountLinked
  }
}

/// ⭐ « Recommandé » est un TAMPON posé sur le coin du bouton, hors mise en page,
/// légèrement penché (le patron de Sawtunaa, `SsoButtons.tsx`) — ⛔ pas dans la
/// rangée, où il décale le libellé et fait un bouton différent des deux autres
/// (Karim, 2026-10-07). Fond de la page et or du parrainage : il se lit sur le
/// bouton plein comme sur la page. En arabe il passe sur l'autre coin et penche
/// de l'autre côté.
struct ReferralStamp: View {
  let text: String

  @Environment(\.layoutDirection) private var direction

  var body: some View {
    Text(text.uppercased())
      .font(.system(size: 10, weight: .bold))
      .tracking(0.6)
      .lineLimit(1)
      .foregroundStyle(ReferralPalette.gold)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(ReferralPalette.screen, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .strokeBorder(ReferralPalette.gold, lineWidth: 1)
      }
      .rotationEffect(.degrees(direction == .rightToLeft ? -8 : 8))
      // ⚠️ Hors du flux : il ne déplace ni l'icône ni le libellé. Il déborde
      // du coin vers l'EXTÉRIEUR — un décalage ne se retourne pas tout seul
      // en arabe.
      .offset(x: direction == .rightToLeft ? -6 : 6, y: -9)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

/// La page de connexion dev&din (Google, Apple) dans la feuille SYSTÈME
/// d'authentification — ⛔ pas un onglet de Browther : la page et ses cookies
/// restent hors de la navigation, et le retour `browther://auth/callback`
/// est rattrapé par la feuille elle-même, avant tout routage de schéma du
/// navigateur.
///
/// ⚠️ `prefersEphemeralWebBrowserSession = false` : on VEUT le compte Google
/// déjà connecté du téléphone (Safari) — en échange, iOS demande « Browther
/// souhaite utiliser devndin.com pour se connecter ».
@MainActor
final class ReferralWebSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
  static let shared = ReferralWebSignIn()

  private var session: ASWebAuthenticationSession?

  /// L'URL de retour, ou `nil` si la personne a fermé la feuille (ou si iOS
  /// n'a pas pu l'ouvrir).
  func run(_ url: URL) async -> URL? {
    session?.cancel()
    return await withCheckedContinuation { continuation in
      let session = ASWebAuthenticationSession(
        url: url,
        callbackURLScheme: ReferralAuthClient.callbackScheme
      ) { [weak self] callback, _ in
        Task { @MainActor in self?.session = nil }
        continuation.resume(returning: callback)
      }
      session.presentationContextProvider = self
      session.prefersEphemeralWebBrowserSession = false
      self.session = session
      if !session.start() {
        self.session = nil
        continuation.resume(returning: nil)
      }
    }
  }

  nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    MainActor.assumeIsolated {
      BrowtherReferralPresenter.topController()?.view.window
        ?? UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow } }
        .first
        ?? ASPresentationAnchor()
    }
  }
}
