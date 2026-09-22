// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BrowtherReferral
import SwiftUI
import UIKit

/// Les écrans du flow — `docs/PARRAINAGE.md` § 3 (numérotation reprise dans
/// l'analytique).
enum ReferralScreen: Equatable {
  /// O — ⚠️ en APERÇU seulement : il vit dans l'introduction.
  case welcome
  /// 0 — ⭐ c'est son affichage qui démarre le mois.
  case announce
  /// 2 — J0.
  case paused
  /// 2b — les trois façons. `locked` = ouvert depuis J0 (circuit fermé, § 12.16).
  case support(locked: Bool)
  /// 4 — inviter, ⚠️ seulement par-dessus 2b (§ 12.15). `shared` = un partage a
  /// abouti : la fenêtre est libérée.
  case invite(shared: Bool)
  /// 7 — soutenir financièrement (par-dessus 2b, ou seul).
  case billing
  /// 7 bis — « Merci » (§ 12.17), au retour d'un achat confirmé.
  case thanks
  /// 1 — J−10 / J−3 de la première fin (feuille).
  case ending(daysLeft: Int)
  /// 3 — les rappels suivants (feuille).
  case reminder(daysLeft: Int, reminderCase: ReminderCase)
  /// 8 — la seule notification : une invitation validée (feuille).
  case validated(months: Int, until: String?, lifetime: Bool)
  /// 8 bis — côté filleul : sa validation est tombée (feuille).
  case refereeDone

  init(_ decision: ReferralPrompt.Solicitation) {
    switch decision {
    case .announce: self = .announce
    case .paused: self = .paused
    case .ending(let daysLeft, _): self = .ending(daysLeft: daysLeft)
    case .reminder(let daysLeft, _, let reminderCase):
      self = .reminder(daysLeft: daysLeft, reminderCase: reminderCase)
    }
  }

  /// La clé d'analytique (`paywall_shown {screen}`) — ⛔ jamais un texte affiché.
  var analyticsName: String {
    switch self {
    case .welcome: return "welcome"
    case .announce: return "announce"
    case .paused: return "paused"
    case .support: return "support"
    case .invite: return "invite"
    case .billing: return "billing"
    case .thanks: return "thanks"
    case .ending: return "ending"
    case .reminder: return "reminder"
    case .validated: return "validated"
    case .refereeDone: return "referee_done"
    }
  }

  /// 1, 3, 8, 8 bis : des FEUILLES à fermeture classique (§ 12.14, § 12.23) —
  /// ⛔ deux feuilles empilées font un bouton mort, d'où la pile plein écran
  /// pour le reste.
  var isSheet: Bool {
    switch self {
    case .ending, .reminder, .validated, .refereeDone: return true
    default: return false
    }
  }
}

// MARK: - Présenter

enum BrowtherReferralPresenter {

  /// Ouvre un écran du flow. `preview` = aperçu de recette : ⛔ n'écrit rien.
  @MainActor
  static func present(_ screen: ReferralScreen, from host: UIViewController, preview: Bool = false) {
    let controller: UIViewController
    if screen.isSheet {
      controller = ReferralSheetHostingController(screen: screen, preview: preview)
    } else {
      controller = ReferralFlowHostingController(root: screen, preview: preview)
    }
    host.present(controller, animated: true)
  }

  /// Écran 6 — Parrainage, depuis n'importe quel « Inviter un proche » hors du
  /// circuit des trois façons (§ 12.15) : la MÊME page que dans les Paramètres,
  /// dans sa propre navigation — ⛔ pas une modale qui la recopie.
  @MainActor
  static func presentHome(from host: UIViewController) {
    let home = ReferralHomeHostingController(showsClose: true)
    let navigation = UINavigationController(rootViewController: home)
    navigation.modalPresentationStyle = .pageSheet
    navigation.sheetPresentationController?.detents = [.large()]
    host.present(navigation, animated: true)
  }

  /// Le contrôleur au sommet de la fenêtre active — pour ce qui s'ouvre depuis
  /// un toast, quand l'écran d'origine est parti.
  @MainActor
  static func topController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}

// MARK: - La pile plein écran (O, 0, 2, 2b, et 4 par-dessus 2b)

/// ⚠️ Une PILE dans UN plein écran (§ 12.16, § 12.23) : 4 s'ouvre par-dessus 2b,
/// « Retour » y ramène. Une fenêtre posée sur une fenêtre verrouillée l'est
/// aussi.
@MainActor
final class ReferralFlowModel: ObservableObject {
  @Published private(set) var stack: [ReferralScreen]
  let preview: Bool
  var dismiss: (() -> Void)?
  /// Ferme le flow puis ouvre l'écran Parrainage (« Inviter un proche », § 12.15).
  var openHome: (() -> Void)?

  init(root: ReferralScreen, preview: Bool) {
    stack = [root]
    self.preview = preview
  }

  var top: ReferralScreen { stack.last ?? .announce }
  var depth: Int { stack.count }

  func push(_ screen: ReferralScreen) {
    stack.append(screen)
  }

  func back() {
    guard stack.count > 1 else {
      dismiss?()
      return
    }
    stack.removeLast()
  }

  func replaceTop(_ screen: ReferralScreen) {
    guard !stack.isEmpty else { return }
    stack[stack.count - 1] = screen
  }

  /// Remplace toute la pile par une fenêtre seule (« Merci » après un achat :
  /// ⛔ jamais la fenêtre d'où l'on est parti, § 12.17).
  func replaceAll(_ screen: ReferralScreen) {
    stack = [screen]
  }

  /// La fenêtre du dessus ne se ferme-t-elle que par ses boutons ? (§ 12.14)
  var isTopLocked: Bool { Self.isLocked(stack) }

  static func isLocked(_ stack: [ReferralScreen]) -> Bool {
    guard let top = stack.last else { return false }
    switch top {
    case .welcome, .announce, .paused:
      return true
    case .support(let locked):
      return locked
    case .invite(let shared):
      if shared { return false }
      return stack.count > 1 && isLocked(Array(stack.dropLast()))
    case .billing:
      // Ce qu'on ouvre par-dessus une fenêtre verrouillée l'est aussi (§ 12.16).
      return stack.count > 1 && isLocked(Array(stack.dropLast()))
    default:
      return false
    }
  }
}

final class ReferralFlowHostingController: UIHostingController<ReferralFlowView> {
  private let model: ReferralFlowModel

  @MainActor
  init(root: ReferralScreen, preview: Bool) {
    model = ReferralFlowModel(root: root, preview: preview)
    super.init(rootView: ReferralFlowView(model: model))
    modalPresentationStyle = .fullScreen
    model.dismiss = { [weak self] in
      self?.dismiss(animated: true)
    }
    model.openHome = { [weak self] in
      guard let self, let presenter = self.presentingViewController else { return }
      self.dismiss(animated: true) {
        BrowtherReferralPresenter.presentHome(from: presenter)
      }
    }
  }

  @available(*, unavailable)
  required dynamic init?(coder aDecoder: NSCoder) {
    fatalError()
  }

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    // ⚠️ L'intention de la jauge est celle du MOMENT (§ 12.20) : elle s'efface
    // avec le flow.
    if isBeingDismissed || presentingViewController == nil {
      BrowtherReferralController.shared.gaugeIntention = nil
    }
  }
}

// MARK: - Les feuilles (1, 3, 8, 8 bis)

final class ReferralSheetHostingController: UIHostingController<ReferralSheetView> {
  @MainActor
  init(screen: ReferralScreen, preview: Bool) {
    let actions = ReferralSheetActions()
    super.init(rootView: ReferralSheetView(screen: screen, preview: preview, actions: actions))
    modalPresentationStyle = .pageSheet
    if let sheet = sheetPresentationController {
      // ⚠️ Elle s'ouvre EN GRAND : à mi-hauteur, le J−3 demandait un geste pour
      // lire sa propre issue (« … mais tu peux les garder à vie »), c'est-à-dire
      // la moitié utile de l'écran (recette Karim, 2026-09-22). La demi-hauteur
      // reste disponible, pour la repousser sans la fermer.
      sheet.detents = [.medium(), .large()]
      sheet.selectedDetentIdentifier = .large
      sheet.prefersGrabberVisible = true
    }
    actions.dismiss = { [weak self] in
      self?.dismiss(animated: true)
    }
    actions.openHome = { [weak self] in
      guard let self, let presenter = self.presentingViewController else { return }
      self.dismiss(animated: true) {
        BrowtherReferralPresenter.presentHome(from: presenter)
      }
    }
    actions.openSupport = { [weak self] in
      guard let self, let presenter = self.presentingViewController else { return }
      self.dismiss(animated: true) {
        // Depuis une feuille qu'on pouvait fermer : une fenêtre ORDINAIRE
        // (§ 12.16, précisé le 2026-09-21).
        BrowtherReferralPresenter.present(.support(locked: false), from: presenter, preview: preview)
      }
    }
  }

  @available(*, unavailable)
  required dynamic init?(coder aDecoder: NSCoder) {
    fatalError()
  }
}

/// Les gestes d'une feuille, branchés par son contrôleur.
@MainActor
final class ReferralSheetActions {
  var dismiss: (() -> Void)?
  var openHome: (() -> Void)?
  var openSupport: (() -> Void)?
}

// MARK: - L'écran Parrainage (6)

final class ReferralHomeHostingController: UIHostingController<ReferralHomeView> {
  @MainActor
  init(showsClose: Bool) {
    super.init(rootView: ReferralHomeView())
    title = Strings.BrowtherReferral.homeTitle
    if showsClose {
      navigationItem.rightBarButtonItem = UIBarButtonItem(
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

// MARK: - Le partage (§ 12.1, § 12.10)

enum ReferralShareResult: String {
  case shared, cancelled, copied, unavailable

  /// Un destinataire choisi, ou le message copié — ⛔ pas une feuille refermée.
  var achieved: Bool { self == .shared || self == .copied }
}

enum ReferralSharing {
  /// Le message complet : le texte, puis le lien seul sur la dernière ligne.
  static func message(for status: ReferralStatus) -> String {
    ReferralShare.message(
      text: Strings.BrowtherReferral.shareMessage(code: status.referral.code.uppercased()),
      code: status.referral.code.uppercased(),
      url: status.referral.url
    )
  }

  /// La feuille de partage du système — ⚠️ le message SEUL, en texte : ⛔ pas
  /// d'URL à part ni de sujet (§ 12.10). « Copier » dans la feuille compte
  /// comme un partage abouti (§ 12.20).
  @MainActor
  static func share(
    status: ReferralStatus,
    from host: UIViewController,
    sourceView: UIView? = nil,
    completion: @escaping (ReferralShareResult) -> Void
  ) {
    let sheet = UIActivityViewController(activityItems: [message(for: status)], applicationActivities: nil)
    sheet.completionWithItemsHandler = { activity, completed, _, _ in
      if !completed {
        completion(.cancelled)
      } else if activity == .copyToPasteboard {
        completion(.copied)
      } else {
        completion(.shared)
      }
    }
    if let popover = sheet.popoverPresentationController {
      popover.sourceView = sourceView ?? host.view
      popover.sourceRect = (sourceView ?? host.view).bounds
    }
    host.present(sheet, animated: true)
  }
}
