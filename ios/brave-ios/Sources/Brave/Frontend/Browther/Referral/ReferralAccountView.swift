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
/// ⛔ **Pas de QR ici** : sur le desktop, le QR fait du téléphone la CLÉ d'un
/// ordinateur. Sur l'iPhone on est déjà sur le téléphone : on se connecte
/// directement, comme dans les autres apps dev&din (Apple, Google, code
/// e-mail). ⛔ Jamais exigé : le parrainage marche sans.
struct ReferralAccountSection: View {
  @ObservedObject private var controller = BrowtherReferralController.shared
  @State private var showsSignIn = false
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
          ReferralSecondaryButton(label: Strings.BrowtherReferral.accountConnect) {
            showsSignIn = true
          }
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(ReferralPalette.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    .sheet(isPresented: $showsSignIn) {
      ReferralSignInSheet()
    }
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
