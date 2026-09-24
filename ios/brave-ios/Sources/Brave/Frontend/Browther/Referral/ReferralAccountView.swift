// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AuthenticationServices
import BraveStrings
import BrowtherReferral
import SwiftUI
import UIKit

/// « Sur tes autres appareils » — le compte dev&din FACULTATIF sur iPhone
/// (`docs/PARRAINAGE.md` § 7.1), pendant de `AccountPanel` du desktop
/// (`private/webui/referral/src/ui/HomeSections.tsx`).
///
/// ⭐ **L'appareil connecté affiche un QR, l'autre le scanne** (recette Karim,
/// 2026-09-24 : se connecter sur chaque appareil était lent, et ouvrait le
/// piège des deux comptes). Le geste principal est donc « Scanner le QR de mon
/// ordinateur » — il marche dans les deux sens (`ReferralLinkFlowSheet`) ; se
/// connecter « autrement » (Apple, Google, code e-mail) reste là pour qui n'a
/// qu'un appareil sous la main. ⛔ Jamais exigé : le parrainage marche sans.
struct ReferralAccountSection: View {
  @ObservedObject private var controller = BrowtherReferralController.shared
  @State private var showsSignIn = false
  @State private var showsScanner = false
  @State private var signingOut = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(Strings.BrowtherReferral.accountHead.uppercased())
        .font(.caption.weight(.semibold))
        .tracking(0.6)
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 12) {
        if let account = controller.account {
          Label {
            Text(account.email.map(Strings.BrowtherReferral.accountConnectedAs) ?? Strings.BrowtherReferral.accountConnected)
              .font(.subheadline.weight(.medium))
              .fixedSize(horizontal: false, vertical: true)
          } icon: {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(ReferralPalette.green)
          }
          Text(Strings.BrowtherReferral.accountOnly)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          // Connecté ici : c'est CET iPhone qui autorise l'ordinateur.
          ReferralSecondaryButton(label: Strings.BrowtherReferral.accountScanComputer) {
            showsScanner = true
          }
          Button(role: .destructive) {
            signingOut = true
            Task {
              await controller.signOut()
              signingOut = false
            }
          } label: {
            Label(Strings.BrowtherReferral.accountSignOut, systemImage: "rectangle.portrait.and.arrow.right")
              .font(.subheadline.weight(.medium))
          }
          .disabled(signingOut)
        } else {
          Text(Strings.BrowtherReferral.accountBody)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
          Text(Strings.BrowtherReferral.accountOnly)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          ReferralPrimaryButton(label: Strings.BrowtherReferral.accountScan, systemImage: "qrcode.viewfinder") {
            showsScanner = true
          }
          Text(Strings.BrowtherReferral.accountScanHint)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Button(Strings.BrowtherReferral.accountOtherWay) {
            showsSignIn = true
          }
          .font(.subheadline.weight(.semibold))
          .frame(maxWidth: .infinity)
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(ReferralPalette.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    .sheet(isPresented: $showsSignIn) {
      ReferralSignInSheet()
    }
    .sheet(isPresented: $showsScanner) {
      ReferralLinkFlowSheet(start: nil)
    }
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
      .navigationTitle(Strings.BrowtherReferral.accountHead)
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
    run(done: Strings.BrowtherReferral.accountLinked) { await controller.linkWithCode(code) }
  }

  private func approve(_ userCode: String) {
    run(done: Strings.BrowtherReferral.accountApproved) { await controller.approveComputer(userCode: userCode) }
  }

  private func run(done: String, _ attempt: @escaping @MainActor () async -> BrowtherReferralController.ConnectOutcome) {
    busy = true
    Task { @MainActor in
      let outcome = await attempt()
      busy = false
      if outcome == .connected {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
        BrowtherReferralToast.show(title: done, persistent: false, duration: 5)
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

  private var choose: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(Strings.BrowtherReferral.accountBody)
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)
      VStack(spacing: 10) {
        Button {
          web(.apple)
        } label: {
          Label(Strings.BrowtherReferral.accountWithApple, systemImage: "apple.logo")
            .font(.body.weight(.semibold))
            .foregroundStyle(Color(UIColor.systemBackground))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        Button {
          web(.google)
        } label: {
          Label(Strings.BrowtherReferral.accountWithGoogle, systemImage: "globe")
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
      Text(Strings.BrowtherReferral.accountOnly)
        .font(.footnote)
        .foregroundStyle(.secondary)
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
        BrowtherReferralToast.show(title: Strings.BrowtherReferral.accountLinked, persistent: false, duration: 5)
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
