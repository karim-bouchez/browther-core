// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BrowtherReferral
import Combine
import SwiftUI
import UIKit

/// Les écrans du flow — `docs/PARRAINAGE.md` § 3 (numérotation reprise dans
/// l'analytique).
enum ReferralScreen: Equatable {
  /// O — ⚠️ en APERÇU seulement : il vit dans l'introduction.
  case welcome
  /// 0 — ⭐ c'est son affichage qui démarre le mois.
  case announce
  /// 2 — J0. `chosen` = ouvert par la personne elle-même (le « Débloquer » du
  /// panneau de la fonctionnalité) : la fenêtre se ferme alors normalement —
  /// « une fenêtre qu'on pouvait fermer n'en ouvre pas une qu'on ne peut plus
  /// fermer » (§ 12.16, même règle que `ShowModal(..., chosen)` sur desktop).
  case paused(chosen: Bool)
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
    case .paused: self = .paused(chosen: false)
    case .ending(let daysLeft, _): self = .ending(daysLeft: daysLeft)
    case .reminder(let daysLeft, _, let reminderCase):
      self = .reminder(daysLeft: daysLeft, reminderCase: reminderCase)
    }
  }

  /// La clé d'analytique (`paywall_shown {screen}`) — ⛔ jamais un texte
  /// affiché, ⛔ jamais le numéro de la maquette (§ 13.2 : la numérotation
  /// bouge, les tuiles non). Les mêmes que sur desktop (`screenName`).
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

/// D'où vient l'affichage d'une fenêtre (`docs/PARRAINAGE.md` § 13.2) : une
/// sollicitation (`prompt`), le circuit rouvert tant qu'il n'a pas eu sa
/// réponse (`circuit`), une bonne nouvelle (`notice`), un geste dans le flow
/// (`flow`), la pause d'une fonctionnalité (`locked` : toast de la garde,
/// « Débloquer »), la personne elle-même (`user` : menu, Paramètres, panneau)
/// ou l'issue d'un paiement (`purchase`).
/// ⚠️ La pression mise sur les gens se lit sur `prompt` SEUL — additionner
/// toutes les provenances compte aussi les fenêtres ouvertes de soi-même.
enum ReferralShowSource: String {
  case prompt, circuit, notice, flow, locked, user, purchase
}

// MARK: - Ce qu'un écran écrit (§ 13.8)

/// 🔴 Les évènements du parrainage qu'un ÉCRAN a le droit d'écrire — les 12 de
/// `docs/PARRAINAGE.md` § 13.1, ⛔ SAUF `paywall_shown` (compté par ce qui POSE
/// la fenêtre, § 13.2) et `referral_state` (la photo du jour). La porte par
/// laquelle un écran se compterait lui-même est fermée PAR LE TYPE, ⛔ pas par
/// une consigne. Pendant desktop : `ScreenEvent` de `controller.ts`.
enum ReferralScreenEvent: String {
  case paywallAction = "paywall_action"
  case referralShared = "referral_shared"
  case referralRedeemed = "referral_redeemed"
  case referralValidated = "referral_validated"
  case referralGaugePulled = "referral_gauge_pulled"
  case referralGrace = "referral_grace"
  case billingCheckoutStarted = "billing_checkout_started"
  case billingCheckoutCompleted = "billing_checkout_completed"
  case billingCheckoutFailed = "billing_checkout_failed"
  case billingGift = "billing_gift"
}

/// D'où part un partage (`referral_shared`, `referral_grace`) — ⛔ jamais le
/// numéro de la maquette (§ 13.2 : Browther y écrivait `4` et `6`).
enum ReferralShareOrigin: String {
  case invite, home
}

/// ⭐⭐ **La SEULE porte par laquelle un écran écrit un évènement** (§ 13.8) —
/// ⛔ muette en aperçu de recette. Avant le 2026-09-24, la garde était posée
/// écran par écran : la jauge et le bouton « Partager » de l'écran 4 écrivaient
/// de vrais `referral_gauge_pulled` / `referral_shared` en aperçu, et la
/// première recette fabriquait le premier jeu de données… faux.
///
/// Un écran la lit dans son environnement (`@Environment(\.referralNote)`) ;
/// le flow et les feuilles l'y posent avec leur `preview`. Verrouillé par
/// `private/scripts/ios-referral-tests/analytics_check.py`.
struct ReferralNote {
  var preview = false

  @MainActor
  func callAsFunction(_ event: ReferralScreenEvent, _ properties: [String: Any]) {
    guard !preview else { return }
    BrowtherSurfaces.track(event.rawValue, properties)
  }
}

private struct ReferralNoteKey: EnvironmentKey {
  static let defaultValue = ReferralNote()
}

extension EnvironmentValues {
  var referralNote: ReferralNote {
    get { self[ReferralNoteKey.self] }
    set { self[ReferralNoteKey.self] = newValue }
  }
}

enum BrowtherReferralPresenter {

  /// Ouvre un écran du flow. `preview` = aperçu de recette : ⛔ n'écrit rien,
  /// ⛔ ne compte rien.
  @MainActor
  static func present(
    _ screen: ReferralScreen,
    from host: UIViewController,
    source: ReferralShowSource,
    preview: Bool = false
  ) {
    let controller: UIViewController
    if screen.isSheet {
      controller = ReferralSheetHostingController(screen: screen, preview: preview)
      countShown(screen.analyticsName, source: source, preview: preview)
    } else {
      // La pile compte sa première fenêtre elle-même (`ReferralFlowModel.show`).
      controller = ReferralFlowHostingController(root: screen, source: source, preview: preview)
    }
    host.present(controller, animated: true)
  }

  /// ⭐⭐ **L'UNIQUE émission de `paywall_shown`** (§ 13.2 de
  /// `docs/PARRAINAGE.md`). Avant le 2026-09-24, seule l'entrée d'une
  /// sollicitation (et le toast de la garde) l'était : les fenêtres posées
  /// par-dessus (inviter, payer, merci), les bonnes nouvelles, le circuit
  /// rouvert et l'écran Parrainage n'existaient dans aucune donnée — « combien
  /// de gens ont vu l'écran de paiement ? » n'avait pas de réponse.
  ///
  /// Appelée par ce qui POSE une fenêtre — `present` (feuilles),
  /// `ReferralFlowModel.show` (la pile), l'écran Parrainage à sa création et ses
  /// onglets (une fois par ouverture), le toast de la garde —, ⛔ jamais par
  /// un écran du flow. ⛔ Un retour ne compte pas, ni
  /// un aperçu. Verrouillé par `private/scripts/ios-referral-tests/analytics_check.py`.
  @MainActor
  static func countShown(
    _ screen: String,
    source: ReferralShowSource,
    preview: Bool,
    extra: [String: Any] = [:]
  ) {
    guard !preview else { return }
    var properties = extra
    properties["screen"] = screen
    properties["source"] = source.rawValue
    BrowtherSurfaces.track("paywall_shown", properties)
  }

  /// Écran 6 — Parrainage, depuis n'importe quel « Inviter un proche » hors du
  /// circuit des trois façons (§ 12.15) : la MÊME page que dans les Paramètres,
  /// dans sa propre navigation — ⛔ pas une modale qui la recopie.
  @MainActor
  static func presentHome(from host: UIViewController, source: ReferralShowSource) {
    let home = ReferralHomeHostingController(showsClose: true, source: source)
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

  /// Une feuille ou une fenêtre du parrainage est-elle posée par-dessus l'écran ?
  /// — ce qui fait passer un toast en haut (`ReferralToastPlacement`).
  ///
  /// ⚠️ Une feuille SwiftUI (« Partager mon code », la connexion, le scanner)
  /// n'a pas de type à elle : c'est celle qui est posée sur un écran du
  /// parrainage. On descend donc la pile des présentations jusqu'au premier
  /// écran à en-tête (une navigation) ; ⛔ ce qui est posé sur AUTRE chose que
  /// le parrainage ne déplace rien.
  @MainActor
  static func sheetOrFlowIsOpen() -> Bool {
    guard var current = topController() else { return false }
    // ⚠️ Un toast naît souvent AU MOMENT où une fenêtre se ferme (0 bis suit
    // l'annonce, « C'est fait » suit la connexion) : celle qui s'en va ne
    // compte pas — c'est l'écran qui RESTE qui décide.
    while current.isBeingDismissed, let below = current.presentingViewController {
      current = below
    }
    if isFlowOrSheet(current) { return true }
    if current is UINavigationController { return false }
    while let below = current.presentingViewController {
      if isReferralScreen(below) { return true }
      if below is UINavigationController { return false }
      current = below
    }
    return false
  }

  private static func isFlowOrSheet(_ controller: UIViewController) -> Bool {
    controller is ReferralFlowHostingController || controller is ReferralSheetHostingController
  }

  private static func isReferralScreen(_ controller: UIViewController) -> Bool {
    if isFlowOrSheet(controller) { return true }
    let shown = (controller as? UINavigationController)?.topViewController ?? controller
    return shown is ReferralHomeHostingController || shown is ReferralAccountHostingController
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

  init(root: ReferralScreen, source: ReferralShowSource, preview: Bool) {
    stack = []
    self.preview = preview
    show([root], source: source)
  }

  var top: ReferralScreen { stack.last ?? .announce }
  var depth: Int { stack.count }

  /// ⭐⭐ **Le seul endroit qui pose la pile — donc qui compte ses fenêtres**
  /// (§ 13.2). `source == nil` : rien de NEUF n'est montré (le même écran dans
  /// un autre état).
  private func show(_ next: [ReferralScreen], source: ReferralShowSource?) {
    stack = next
    guard let source, let top = next.last else { return }
    BrowtherReferralPresenter.countShown(top.analyticsName, source: source, preview: preview)
  }

  /// Pose une fenêtre PAR-DESSUS l'actuelle (« Retour » y ramène).
  func push(_ screen: ReferralScreen) {
    show(stack + [screen], source: .flow)
  }

  /// ⛔ Un RETOUR ne compte pas : la fenêtre du dessous a déjà été vue, et
  /// l'aller-retour la gonflerait.
  func back() {
    guard stack.count > 1 else {
      dismiss?()
      return
    }
    stack.removeLast()
  }

  /// Remplace la fenêtre du dessus : comptée si c'est un AUTRE écran (J0 → les
  /// trois façons), pas si c'est le même dans un autre état (4 partagé).
  func replaceTop(_ screen: ReferralScreen) {
    guard let current = stack.last else { return }
    let isNew = current.analyticsName != screen.analyticsName
    show(stack.dropLast() + [screen], source: isNew ? .flow : nil)
  }

  /// Remplace toute la pile par une fenêtre seule (« Merci » après un achat :
  /// ⛔ jamais la fenêtre d'où l'on est parti, § 12.17).
  func replaceAll(_ screen: ReferralScreen, source: ReferralShowSource) {
    show([screen], source: source)
  }

  /// La fenêtre du dessus ne se ferme-t-elle que par ses boutons ? (§ 12.14)
  var isTopLocked: Bool { Self.isLocked(stack) }

  static func isLocked(_ stack: [ReferralScreen]) -> Bool {
    guard let top = stack.last else { return false }
    switch top {
    case .welcome, .announce:
      return true
    case .paused(let chosen):
      return !chosen
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
  init(root: ReferralScreen, source: ReferralShowSource, preview: Bool) {
    model = ReferralFlowModel(root: root, source: source, preview: preview)
    super.init(rootView: ReferralFlowView(model: model))
    modalPresentationStyle = .fullScreen
    model.dismiss = { [weak self] in
      self?.dismiss(animated: true)
    }
    model.openHome = { [weak self] in
      guard let self, let presenter = self.presentingViewController else { return }
      self.dismiss(animated: true) {
        BrowtherReferralPresenter.presentHome(from: presenter, source: .flow)
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
        BrowtherReferralPresenter.presentHome(from: presenter, source: .flow)
      }
    }
    actions.openSupport = { [weak self] in
      guard let self, let presenter = self.presentingViewController else { return }
      self.dismiss(animated: true) {
        // Depuis une feuille qu'on pouvait fermer : une fenêtre ORDINAIRE
        // (§ 12.16, précisé le 2026-09-21).
        BrowtherReferralPresenter.present(
          .support(locked: false),
          from: presenter,
          source: .flow,
          preview: preview
        )
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
  private let source: ReferralShowSource
  private var accountObserver: AnyCancellable?

  @MainActor
  init(showsClose: Bool, source: ReferralShowSource) {
    self.source = source
    super.init(rootView: ReferralHomeView())
    // Le fond de Brave sous SwiftUI : sinon un éclair noir au push, et une
    // barre de navigation qui ne s'accorde pas (recette Karim, 2026-09-23).
    view.backgroundColor = .braveGroupedBackground
    title = Strings.BrowtherReferral.homeTitle
    // ⚠️ La croix passe à GAUCHE (2026-10-07) : la droite est au compte, « en
    // face du retour » — qu'on arrive par les Paramètres (retour) ou par une
    // fenêtre (croix), l'entrée du compte est au même endroit.
    if showsClose {
      navigationItem.leftBarButtonItem = UIBarButtonItem(
        systemItem: .close,
        primaryAction: UIAction { [weak self] _ in
          self?.dismiss(animated: true)
        }
      )
    }
    // ⭐ **L'accès PERMANENT au compte** (§ 7.1 du doc commun) : jamais
    // derrière un défilement — dans l'en-tête, donc sur TOUS les onglets. Une
    // personne, grise tant que personne n'est connecté, verte et cochée ensuite. C'est par là
    // qu'on voit avec quel compte on est connecté, qu'on se déconnecte, qu'on
    // supprime, et qu'on RETROUVE un compte sur un iPhone neuf.
    // ⚠️ `@Published` émet AVANT d'écrire : on lit la valeur reçue, ⛔ pas
    // `controller.account`.
    accountObserver = BrowtherReferralController.shared.$account
      .map { $0 != nil }
      .removeDuplicates()
      .sink { [weak self] connected in
        self?.showAccountButton(connected: connected)
      }
  }

  private func showAccountButton(connected: Bool) {
    let button = UIBarButtonItem(
      // ⭐ Une personne, ⛔ pas un bouclier (Karim, 2026-10-08) : seul dans un
      // en-tête, le bouclier ne se lisait pas comme « se connecter ». Il reste
      // là où les mots disent « à l'abri » (les rangées, le haut de la page).
      image: UIImage(systemName: connected ? "person.crop.circle.badge.checkmark" : "person.crop.circle"),
      primaryAction: UIAction { _ in
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        BrowtherReferralPresenter.openAccount(from: .home, note: ReferralNote())
      }
    )
    button.tintColor = connected ? UIColor(ReferralPalette.green) : .secondaryLabel
    button.accessibilityLabel =
      connected ? Strings.BrowtherReferral.accountManage : Strings.BrowtherReferral.accountConnect
    navigationItem.rightBarButtonItem = button
  }

  @available(*, unavailable)
  required dynamic init?(coder aDecoder: NSCoder) {
    fatalError()
  }

  /// ⭐ L'écran Parrainage compte son affichage comme une fenêtre (§ 13.2) : c'est
  /// la surface où l'on vient de soi-même, donc celle qui dit si le menu et les
  /// Paramètres y mènent vraiment. ⚠️ Une fois par OUVERTURE (`viewDidLoad`),
  /// ⛔ pas `viewWillAppear` : un retour d'une page poussée par-dessus le
  /// recompterait.
  override func viewDidLoad() {
    super.viewDidLoad()
    BrowtherReferralPresenter.countShown("home", source: source, preview: false)
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

  /// ⭐ **UN envoi : un fichier et un texte** (2026-10-08, `private/docs/PARRAINAGE.md`
  /// § 11) — la vidéo de présentation ou l'image du statut, avec le lien SEUL
  /// (statut WhatsApp : il devient la légende, juste sous l'étiquette « Clique
  /// sur le lien en dessous 👇 ») ou le message à un proche. ⛔ Jamais deux
  /// fichiers dans le même envoi : WhatsApp ne donne le texte qu'au premier.
  ///
  /// ⚠️ **Le texte d'abord, puis l'adresse du FICHIER** : c'est exactement ce
  /// que Fajrunaa envoie (`Share.share({ url, message })` de React Native), et
  /// ce que Karim a recetté sur iPhone le 2026-10-08. ⛔ Ne pas repasser à une
  /// `UIImage` : c'est un fichier que WhatsApp légende.
  /// ⛔ Pas de sujet (§ 12.10).
  @MainActor
  static func shareFile(
    _ file: URL,
    text: String,
    from host: UIViewController,
    sourceView: UIView? = nil,
    completion: @escaping (ReferralShareResult) -> Void
  ) {
    let sheet = UIActivityViewController(activityItems: [text, file], applicationActivities: nil)
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

  /// L'image du statut (`ReferralStatusImage`) écrite en JPEG, sous un nom qui
  /// porte le code — ~300 Ko au lieu de plusieurs Mo en PNG. `nil` si l'écriture
  /// échoue : le message texte d'avant part alors seul.
  static func statusImageFile(_ image: UIImage, code: String) -> URL? {
    guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("browther-referral", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("browther-\(code.lowercased()).jpg")
    do {
      try data.write(to: file, options: .atomic)
      return file
    } catch {
      return nil
    }
  }

  /// Les propriétés d'un `referral_shared` : `media` dit le fichier joint
  /// (`video` | `image`), ⛔ absent si le texte est parti seul. ⚠️ Un évènement
  /// par ENVOI : qui publie les deux statuts en émet deux — compter des
  /// personnes, pas des lignes.
  static func properties(_ base: [String: Any], media: ReferralStatusSegment?) -> [String: Any] {
    var properties = base
    if let media { properties["media"] = media.rawValue }
    return properties
  }
}
