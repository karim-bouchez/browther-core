// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import SwiftUI
import UIKit

/// Les toasts du parrainage — `docs/PARRAINAGE.md` § 12.14 : **ce qui n'attend
/// RIEN n'est pas une fenêtre mais un toast** (0 bis « C'est noté », 5 « +3 jours
/// offerts », la garde d'une fonctionnalité en pause).
///
/// ## Pourquoi une fenêtre à part
///
/// Un toast naît souvent AU MOMENT où un écran se ferme (0 bis suit l'annonce,
/// 5 suit un partage) : posé dans la vue de l'écran, il partirait avec lui ;
/// posé dans le navigateur, il serait caché par une feuille encore ouverte.
/// Une fenêtre transparente au-dessus de tout, qui ne capte QUE les touchers
/// sur la carte : le reste de l'écran reste utilisable.
///
/// ⚠️ Pas le `ButtonToast` de Brave : hauteur fixe de 55 pt — une ligne, alors
/// que ces toasts disent une raison en deux ou trois lignes.
///
/// - **Un changement d'état reste jusqu'à ce qu'on le ferme** (§ 12.26 : « c'est
///   mieux qu'elle le ferme consciemment ») — 0 bis, 5.
/// - Un retour de geste (« Message copié ») s'efface seul.
/// - La garde a son bouton « Soutenir dev&din » bien visible (§ 12.20), et
///   s'efface après ~10 s (§ 12.9 : le temps de se lire).
/// - Un seul toast à la fois (§ 12.16).
@MainActor
enum BrowtherReferralToast {
  private static var window: PassthroughWindow?
  private static var dismissWork: DispatchWorkItem?

  static func show(
    title: String,
    body: String? = nil,
    action: (label: String, run: @MainActor () -> Void)? = nil,
    persistent: Bool,
    duration: TimeInterval = 10
  ) {
    guard
      let scene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive })
    else { return }
    hide(animated: false)

    let model = ToastModel(title: title, body: body, actionLabel: action?.label)
    model.onAction = {
      hide(animated: true)
      action?.run()
    }
    model.onClose = { hide(animated: true) }

    let window = PassthroughWindow(windowScene: scene)
    window.model = model
    window.windowLevel = .alert + 1
    window.backgroundColor = .clear
    let host = UIHostingController(rootView: ReferralToastView(model: model))
    host.view.backgroundColor = .clear
    window.rootViewController = host
    window.isHidden = false
    self.window = window
    model.visible = true

    UIAccessibility.post(notification: .announcement, argument: [title, body].compactMap { $0 }.joined(separator: " "))

    guard !persistent else { return }
    let work = DispatchWorkItem { hide(animated: true) }
    dismissWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
  }

  static func hide(animated: Bool) {
    dismissWork?.cancel()
    dismissWork = nil
    guard let window else { return }
    self.window = nil
    guard animated, let host = window.rootViewController as? UIHostingController<ReferralToastView> else {
      window.isHidden = true
      return
    }
    host.rootView.model.visible = false
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      window.isHidden = true
    }
  }
}

/// Ne capte que les touchers sur ce qui est dessiné (la carte) : partout
/// ailleurs, l'écran d'en dessous reste utilisable.
///
/// 🔴 **Le tri se fait sur le RECTANGLE de la carte, ⛔ pas sur l'identité de la
/// vue touchée** : SwiftUI dessine tout son contenu dans la vue de l'hôte
/// (`_UIHostingView`) sans sous-vue par bouton. Comparer `hit ===
/// rootViewController?.view` renvoyait donc TOUJOURS `nil` — la croix et le
/// bouton « Soutenir dev&din » d'un toast ne recevaient jamais le toucher
/// (constaté par Karim en recette le 2026-09-22 : la croix ne fermait rien).
/// La carte publie son cadre (`ToastModel.cardFrame`), et lui seul capte.
final class PassthroughWindow: UIWindow {
  weak var model: ToastModel?

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard let frame = model?.cardFrame, frame.contains(point) else { return nil }
    return super.hitTest(point, with: event)
  }
}

@MainActor
final class ToastModel: ObservableObject {
  let title: String
  let body: String?
  let actionLabel: String?
  @Published var visible = false
  /// Le cadre de la carte, en coordonnées d'écran — c'est LUI qui capte les
  /// touchers (`PassthroughWindow`), pas la vue SwiftUI.
  var cardFrame: CGRect = .zero
  var onAction: (() -> Void)?
  var onClose: (() -> Void)?

  init(title: String, body: String?, actionLabel: String?) {
    self.title = title
    self.body = body
    self.actionLabel = actionLabel
  }
}

struct ReferralToastView: View {
  @ObservedObject var model: ToastModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack {
      Spacer()
      if model.visible {
        card
          .transition(
            reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
          )
      }
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 64)
    .animation(.spring(duration: 0.35, bounce: 0.15), value: model.visible)
  }

  private var card: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(model.title)
          .font(.subheadline.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
        if let body = model.body {
          Text(body)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let label = model.actionLabel {
          Button(label) { model.onAction?() }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(UIColor.systemBackground))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(UIColor.label), in: Capsule())
            .padding(.top, 6)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        model.onClose?()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .semibold))
          // ⚠️ `.secondary` DANS un bouton = la teinte (bleu) atténuée, pas du
          // gris : la croix ressortait en bleu (recette Karim, 2026-09-22).
          .foregroundStyle(Color.secondary)
          .frame(width: 30, height: 30)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Strings.BrowtherReferral.close)
    }
    .padding(14)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.08))
    }
    .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    .frame(maxWidth: 520)
    .background(
      GeometryReader { geometry in
        Color.clear
          .onAppear { model.cardFrame = geometry.frame(in: .global) }
          .onChange(of: geometry.frame(in: .global)) { model.cardFrame = $1 }
      }
    )
  }
}
