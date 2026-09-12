// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveCore
import BraveShields
import BraveUI
import BrowtherAnalytics
import Onboarding
import Preferences
import Shared
import StoreKit
import SwiftUI
import UIKit

// MARK: - Onboarding

extension BrowserViewController {

  func presentOnboardingIntro() {
    if Preferences.DebugFlag.skipOnboardingIntro == true { return }

    // Browther : c'est NOTRE introduction qui s'ouvre au premier lancement, pas
    // le parcours Focus de Brave — celui-ci ne présentait que ce que Browther
    // hérite (navigateur par défaut, argument anti-pub, canaux) et ne disait
    // rien de Basarunaa ni de Sawtunaa, les deux raisons d'exister du
    // navigateur. `presentFocusOnboarding()` reste en place pour le menu de
    // debug ; il n'est simplement plus le chemin du premier lancement.
    presentBrowtherIntro()
  }

  func showNTPOnboarding() {
    Preferences.AppState.shouldDeferPromotedPurchase.value = false

    if !topToolbar.inOverlayMode,
      topToolbar.currentURL == nil,
      Preferences.DebugFlag.skipNTPCallouts != true
    {

      if !Preferences.FullScreenCallout.omniboxCalloutCompleted.value,
        Preferences.Onboarding.isNewRetentionUser.value == true
      {
        presentOmniBoxOnboarding()
      }

      if !Preferences.FullScreenCallout.ntpCalloutCompleted.value {
        showPrivacyReportsOnboardingIfNeeded()
      }
    }

    // Browther : les sollicitations dev&din (avis, note) ne viennent que sur un
    // Nouvel Onglet — c'est leur seul point d'entrée spontané.
    BrowtherPromptCoordinator.shared.newTabPageDidAppear(in: self)
  }

  private func presentOmniBoxOnboarding() {
    // If a controller is already presented (such as menu), do not show onboarding
    guard presentedViewController == nil else {
      return
    }

    // Don't show onboarding if we're in overlay mode or no longer on an NTP
    guard !topToolbar.inOverlayMode,
      activeNewTabPageViewController != nil,
      topToolbar.currentURL == nil
    else { return }

    var controller: UIViewController & PopoverContentComponent

    // Browther: post-onboarding URL bar hint retiré (redondant avec l'onboarding lui-même)
    if false, Preferences.FocusOnboarding.urlBarIndicatorShowBeShown.value {
      Preferences.FocusOnboarding.urlBarIndicatorShowBeShown.reset()

      controller = FocusNTPOnboardingViewController().then {
        $0.setText(
          title: Strings.FocusOnboarding.urlBarIndicatorTitle,
          details: Strings.FocusOnboarding.urlBarIndicatorDescription
        )
      }

      presentFavouriteURLBarPopover(
        controller: controller,
        onDismiss: { [weak self] in
          guard let self = self else { return }
          self.triggerPromotedInAppPurchase(savedPayment: nil)
        }
      )
    }

    func presentFavouriteURLBarPopover(
      controller: UIViewController & PopoverContentComponent,
      onDismiss: @escaping () -> Void
    ) {
      // Double-check that we're still on the NTP and not in overlay mode before presenting
      guard !topToolbar.inOverlayMode,
        let info = activeNewTabPageViewController?.onboardingYouTubeFavoriteInfo,
        let cellSuperview = info.cell.superview
      else { return }
      let frame = view.convert(info.cell.frame, from: cellSuperview)
      presentPopoverContent(
        using: controller,
        with: frame,
        arrowDistance: -10,
        lineWidth: 0,
        cornerRadius: topToolbar.locationContainer.layer.cornerRadius,
        didDismiss: {
          Preferences.FullScreenCallout.omniboxCalloutCompleted.value = true
          Preferences.AppState.shouldDeferPromotedPurchase.value = false

          onDismiss()
        },
        didClickBorderedArea: { [unowned self] in
          Preferences.FullScreenCallout.omniboxCalloutCompleted.value = true
          Preferences.AppState.shouldDeferPromotedPurchase.value = false

          self.handleFavoriteAction(favorite: info.favorite, action: .opened())
        }
      )
    }

  }

  private func triggerPromotedInAppPurchase(savedPayment: SKPayment?) {
    // Browther: firewall removed — promoted in-app purchase no longer handled
  }

  private func showPrivacyReportsOnboardingIfNeeded() {
    if Preferences.PrivacyReports.ntpOnboardingCompleted.value
      || privateBrowsingManager.isPrivateBrowsing
    {
      return
    }

    let trackerCountThresholdForOnboarding = AppConstants.isOfficialBuild ? 250 : 20
    let trackerAdsTotal =
      BraveGlobalShieldStats.shared.adblock + BraveGlobalShieldStats.shared.trackingProtection

    if trackerAdsTotal < trackerCountThresholdForOnboarding {
      return
    }

    // If a controller is already presented (such as menu), do not show onboarding
    // It also includes the case for overlay mode and tabtray opened
    guard presentedViewController == nil, !topToolbar.inOverlayMode, !isTabTrayActive else {
      return
    }

    // We can only show this onboarding on the NTP
    guard let ntpController = tabManager.selectedTab?.newTabPageViewController,
      let statsFrame = ntpController.ntpStatsOnboardingFrame
    else {
      return
    }

    // Project the statsFrame to the current frame
    let frame = view.convert(statsFrame, from: ntpController.view)

    // Present the popover
    let controller = WelcomeNTPOnboardingController()
    controller.setText(details: Strings.Onboarding.ntpOnboardingPopOverTrackerDescription)

    controller.buttonText = Strings.PrivacyHub.onboardingButtonTitle

    topToolbar.isURLBarEnabled = false

    presentPopoverContent(
      using: controller,
      with: frame,
      cornerRadius: 12.0,
      didDismiss: { [weak self] in
        self?.topToolbar.isURLBarEnabled = true
        Preferences.PrivacyReports.ntpOnboardingCompleted.value = true
      },
      didClickBorderedArea: { [weak self] in
        self?.topToolbar.isURLBarEnabled = true
        Preferences.PrivacyReports.ntpOnboardingCompleted.value = true
      },
      didButtonClick: { [weak self] in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
          self?.topToolbar.isURLBarEnabled = true
          self?.openPrivacyReport()
        }
      }
    )
  }

  func completeOnboarding(_ controller: UIViewController) {
    Preferences.Onboarding.basicOnboardingCompleted.value = OnboardingState.completed.rawValue
    Preferences.AppState.shouldDeferPromotedPurchase.value = false
    controller.dismiss(animated: true)
  }

  private func presentPopoverContent(
    using contentController: UIViewController & PopoverContentComponent,
    with frame: CGRect,
    arrowDistance: CGFloat = 10,
    lineWidth: CGFloat = 2,
    cornerRadius: CGFloat,
    didDismiss: @escaping () -> Void,
    didClickBorderedArea: @escaping () -> Void,
    didButtonClick: (() -> Void)? = nil
  ) {
    let popover = PopoverController(
      contentController: contentController,
      contentSizeBehavior: .autoLayout(.phoneWidth)
    )
    popover.arrowDistance = arrowDistance

    // Create a border / placeholder view
    let borderView = NotificationBorderView(
      frame: frame,
      cornerRadius: cornerRadius,
      lineWidth: lineWidth,
      colouredBorder: true
    )
    let placeholderView = UIView(frame: frame).then {
      $0.alpha = 0.0
      $0.frame = frame
    }

    view.addSubview(placeholderView)
    popover.view.insertSubview(borderView, aboveSubview: popover.view)

    let maskShape = CAShapeLayer().then {
      $0.fillRule = .evenOdd
      $0.fillColor = UIColor.white.cgColor
      $0.strokeColor = UIColor.clear.cgColor
    }

    popover.present(from: placeholderView, on: self) { [weak popover, weak self] in
      guard let popover = popover, let self = self else { return }

      // Mask the shadow
      let maskFrame = self.view.convert(frame, to: popover.backgroundOverlayView)
      guard
        !maskFrame.isNull && !maskFrame.isInfinite && !maskFrame.isEmpty
          && !popover.backgroundOverlayView.bounds.isNull
          && !popover.backgroundOverlayView.bounds.isInfinite
          && !popover.backgroundOverlayView.bounds.isEmpty
      else {
        return
      }

      guard
        maskFrame.origin.x.isFinite && maskFrame.origin.y.isFinite && maskFrame.size.width.isFinite
          && maskFrame.size.height.isFinite && maskFrame.size.width > 0 && maskFrame.size.height > 0
      else {
        return
      }
    }

    popover.backgroundOverlayView.layer.mask = maskShape

    popover.popoverDidDismiss = { _ in
      maskShape.removeFromSuperlayer()
      borderView.removeFromSuperview()

      didDismiss()
    }

    borderView.didClickBorderedArea = { [weak popover] in
      maskShape.removeFromSuperlayer()
      borderView.removeFromSuperview()

      popover?.dismissPopover {
        didClickBorderedArea()
      }
    }

    if let controller = contentController as? WelcomeNTPOnboardingController {
      controller.buttonTapped = {
        maskShape.removeFromSuperlayer()
        borderView.removeFromSuperview()
        didButtonClick?()
      }
    }

    DispatchQueue.main.async {
      maskShape.path = {
        let path = CGMutablePath()
        path.addRect(popover.backgroundOverlayView.bounds)
        return path
      }()
    }
  }
}

extension BrowserViewController {

  // MARK: Day 0 Focus Onboarding

  func presentFocusOnboarding() {

    // Check user has never seen onboarding - new user
    guard Preferences.Onboarding.basicOnboardingCompleted.value == OnboardingState.unseen.rawValue
    else {
      Preferences.AppState.shouldDeferPromotedPurchase.value = false
      return
    }

    // Perform accurate check to get fresh default browser status
    defaultBrowserHelper.performAccurateDefaultCheckIfNeeded()

    // Check if user is already default before showing onboarding
    let isDefault = defaultBrowserHelper.status == .defaulted

    var steps: [any OnboardingStep] = [.blockInterruptions]
    if !isDefault {
      steps.insert(.defaultBrowsing, at: 0)
    }
    // Browther : proposer de suivre les canaux dev&din (parité avec l'étape
    // desktop `follow-channels`). En DERNIER parce qu'elle ne conditionne rien —
    // le navigateur est déjà utilisable quand elle s'affiche.
    //
    // ⚠️ C'est ICI qu'il faut l'ajouter, pas dans `allSteps` /
    // `alreadyDefaultBrowserSteps`. Ces deux propriétés ressemblent à la source
    // de vérité et n'en sont pas : ce point d'entrée construit sa liste à la
    // main, et elles ne servent plus qu'à un aperçu SwiftUI et au menu de debug.
    // L'ajout du 2026-08-08 s'était fait dans ces listes-là — il n'avait donc
    // strictement aucun effet, et personne ne pouvait le voir avant de
    // dérouler l'onboarding sur un appareil (fait le 2026-08-28 : l'étape
    // n'apparaissait pas). Du code livré trois semaines plus tôt, jamais
    // compilé, jamais exécuté.
    steps.append(.followChannels)
    // Browther: P3A disabled, no analytics consent screen
    // Will be replaced by Sentry/PostHog consent in Phase 3.5

    let controller = OnboardingController(
      environment: .init(
        p3aUtils: braveCore.p3aUtils,
        attributionManager: attributionManager
      ),
      steps: steps,
      showSplashScreen: false,  // Browther: skip Brave wordmark splash

      onCompletion: {
        BrowserViewController.finishOnboarding()
      }
    )

    present(controller, animated: false)

    Preferences.FocusOnboarding.urlBarIndicatorShowBeShown.value = true
  }
}

// MARK: - Browther : introduction maison

extension BrowserViewController {

  /// Ouvre l'introduction Browther (six écrans, cf.
  /// `private/docs/ONBOARDING.md`). Mêmes gardes que le parcours Brave : elle
  /// ne s'ouvre que pour qui ne l'a jamais vue.
  func presentBrowtherIntro() {
    guard Preferences.Onboarding.basicOnboardingCompleted.value == OnboardingState.unseen.rawValue
    else {
      Preferences.AppState.shouldDeferPromotedPurchase.value = false
      return
    }

    // Statut fraîchement mesuré : inutile de proposer ce qui est déjà fait.
    defaultBrowserHelper.performAccurateDefaultCheckIfNeeded()
    let isDefault = defaultBrowserHelper.status == .defaulted

    let model = BrowtherIntroModel(
      isDefaultBrowser: isDefault,
      onOpenURL: { url in
        UIApplication.shared.open(url)
      },
      onSetDefaultBrowser: {
        // ⚠️ Régression assumée pour l'instant : le parcours Brave lançait
        // AUSSI la vidéo en incrustation (`set-default-pip-*.mp4`, tournée sur
        // appareil) qui montre le chemin dans les Réglages. Son contrôleur est
        // `private` dans le module Onboarding — à exposer pour la remettre.
        if let settings = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(settings)
        }
      },
      onFinish: { [weak self] in
        BrowserViewController.finishOnboarding()
        self?.dismiss(animated: true)
      }
    )

    present(BrowtherIntroController(model: model), animated: false)
  }

  /// Ce que la fin d'une introduction doit poser, quelle qu'elle soit.
  ///
  /// ⚠️ Les deux lignes `BrowtherSurfaces` ne sont pas décoratives : un nouvel
  /// arrivant ne doit jamais voir « Ce qui a changé » (tout est nouveau pour
  /// lui), et la dernière étape vient de lui proposer les canaux — donc une
  /// sollicitation, qui arme le verrou de 3 jours.
  static func finishOnboarding() {
    Preferences.Onboarding.basicOnboardingCompleted.value = OnboardingState.completed.rawValue
    Preferences.AppState.shouldDeferPromotedPurchase.value = false
    Preferences.FocusOnboarding.focusOnboardingFinished.value = true
    BrowtherSurfaces.seedWhatsNewAfterOnboarding()
    BrowtherSurfaces.markSolicitationShown()
    BrowtherAnalyticsService.shared.track(
      event: "onboarding_completed",
      properties: [
        "sentry_enabled": Preferences.BrowtherAnalytics.sentryEnabled.value,
        "posthog_enabled": Preferences.BrowtherAnalytics.posthogEnabled.value,
      ]
    )
  }
}
