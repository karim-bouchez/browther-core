// Copyright 2021 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveCore
import BraveShared
import BraveUI
import BraveWallet
import BrowserMenu
import Data
import Foundation
import PlaylistUI
import Preferences
import Shared
import SwiftUI
import Web
import os.log

extension BrowserViewController {
  private var settingsController: SettingsViewController {
    let isPrivateMode = privateBrowsingManager.isPrivateBrowsing
    let keyringService = BraveWallet.KeyringServiceFactory.get(privateMode: isPrivateMode)
    let walletService = BraveWallet.ServiceFactory.get(privateMode: isPrivateMode)
    let rpcService = BraveWallet.JsonRpcServiceFactory.get(privateMode: isPrivateMode)
    let walletP3A = profileController.braveWalletAPI.walletP3A()

    var keyringStore: KeyringStore? = walletStore?.keyringStore
    if keyringStore == nil {
      if let keyringService = keyringService,
        let walletService = walletService,
        let rpcService = rpcService,
        let walletP3A
      {
        keyringStore = KeyringStore(
          keyringService: keyringService,
          walletService: walletService,
          rpcService: rpcService,
          walletP3A: walletP3A
        )
      }
    }

    var cryptoStore: CryptoStore? = walletStore?.cryptoStore
    if cryptoStore == nil {
      cryptoStore = CryptoStore.from(
        ipfsApi: profileController.ipfsAPI,
        walletP3A: walletP3A,
        privateMode: isPrivateMode
      )
    }

    let vc = SettingsViewController(
      profile: self.profile,
      tabManager: self.tabManager,
      feedDataSource: self.feedDataSource,
      rewards: self.rewards,
      windowProtection: self.windowProtection,
      p3aUtils: self.braveCore.p3aUtils,
      braveCore: self.profileController,
      localState: self.braveCore.localState,
      attributionManager: attributionManager,
      keyringStore: keyringStore,
      cryptoStore: cryptoStore
    )
    vc.settingsDelegate = self
    return vc
  }

  /// Presents Wallet without an origin (ex. from menu)
  func presentWallet() {
    Task {
      guard let walletStore = self.walletStore ?? newWalletStore() else { return }
      if await walletStore.keyringStore.shouldUseWalletWebUI() == true {
        self.dismiss(animated: true) {
          self.tabManager.addTabAndSelect(
            URLRequest(url: .webUI.wallet.home),
            isPrivate: self.privateBrowsingManager.isPrivateBrowsing
          )
        }
      } else {
        presentNativeWallet()
      }
    }
  }

  /// Present Native Wallet from a Wallet WebUI Action
  func presentNativeWallet(webUIAction: WalletWebUIAction? = nil) {
    guard let walletStore = self.walletStore ?? newWalletStore() else { return }
    walletStore.origin = nil
    var presentingContext = PresentingContext.default(.portfolio)
    if let webUIAction {
      presentingContext = .webUI(action: webUIAction)
    }
    let vc = WalletHostingViewController(
      walletStore: walletStore,
      webImageDownloader: profileController.webImageDownloader,
      presentingContext: presentingContext
    )
    vc.delegate = self
    self.dismiss(animated: true) {
      self.present(vc, animated: true)
    }
  }

  public func presentPlaylistController() {
    if !profileController.profile.prefs.isPlaylistAvailable {
      return
    }
    if PlaylistCoordinator.shared.isPlaylistControllerPresented {
      let alert = UIAlertController(
        title: Strings.PlayList.playlistAlreadyShowingTitle,
        message: Strings.PlayList.playlistAlreadyShowingBody,
        preferredStyle: .alert
      )
      alert.addAction(UIAlertAction(title: Strings.OKString, style: .default))
      dismiss(animated: true) {
        self.present(alert, animated: true)
      }
      return
    }

    // Retrieve the item and offset-time from the current tab's webview.
    let tab = self.tabManager.selectedTab
    PlaylistCoordinator.shared.getPlaylistController(tab: tab, profile: profileController.profile) {
      [weak self] playlistController in
      guard let self = self else { return }

      PlaylistP3A.recordUsage()

      self.dismiss(animated: true) {
        PlaylistCoordinator.shared.isPlaylistControllerPresented = true
        self.present(playlistController, animated: true)
      }
    }
  }

  func presentBrowserMenu(
    from sourceView: UIView,
    activities: [UIActivity],
    tab: (any TabState)?,
    pageURL: URL?
  ) {
    var actions: [Action] = []
    // Browther: firewall/network feature removed from menu (App Store policy)
    actions.append(contentsOf: destinationMenuActions(for: pageURL))
    actions.append(contentsOf: pageActions(for: pageURL, tab: tab))
    var pageActivities: Set<Action> = Set(
      activities
        .compactMap { activity in
          guard let id = (activity as? MenuActivity)?.id,
            let actionID = Action.Identifier.allPageActivites.first(where: { $0.id == id })
          else {
            return nil
          }
          return (activity, actionID)
        }
        .map { (activity: UIActivity, actionID: Action.Identifier) in
          .init(id: actionID) { @MainActor [unowned self] _ in
            self.dismiss(animated: true) {
              activity.perform()
            }
            return .none
          }
        }
    )
    if let tab,
      let requestDesktopPageActivity = pageActivities.first(where: { $0.id == .requestDesktopSite })
    {
      // Remove the UIActivity version and replace it with a manual version.
      // The request desktop activity is special in the sense that it is dynamic based on the
      // current tab user agent, but we don't use rely on the UIActivity information to populate
      // actions in the new menu UI, so this replaces it with how we would compose it manually
      pageActivities.remove(requestDesktopPageActivity)
      pageActivities.insert(
        .init(
          id: .requestDesktopSite,
          title: tab.currentUserAgentType == .desktop
            ? Strings.appMenuViewMobileSiteTitleString : nil,
          image: tab.currentUserAgentType == .desktop ? "leo.smartphone" : nil,
          handler: { @MainActor [unowned self, weak tab] _ in
            tab?.switchUserAgent()
            self.dismiss(animated: true)
            return .none
          }
        )
      )
    }
    // Sets up empty actions for any page actions that weren't setup as UIActivity's excluding any
    // that should be hidden due to admin policies
    var pageActivitiesRemovedByAdminPolicies: Set<Action.Identifier> = []
    if !profileController.profile.prefs.isBraveNewsAvailable {
      pageActivitiesRemovedByAdminPolicies.insert(.addSourceNews)
    }
    let remainingPageActivities: [Action] = Action.ID.allPageActivites
      .subtracting(pageActivities.map(\.id))
      .subtracting(pageActivitiesRemovedByAdminPolicies)
      .map { .init(id: $0, attributes: .disabled) }
    actions.append(contentsOf: pageActivities)
    actions.append(contentsOf: remainingPageActivities)
    let browserMenu = BrowserMenuController(
      actions: actions,
      handlePresentation: { [unowned self] action in
        switch action {
        case .settings:
          let vc = self.settingsController
          self.dismiss(animated: true) {
            self.presentSettingsNavigation(with: vc)
          }
        }
      }
    )
    if UIDevice.current.userInterfaceIdiom == .pad {
      browserMenu.modalPresentationStyle = .popover
    }
    browserMenu.popoverPresentationController?.sourceView = sourceView
    browserMenu.popoverPresentationController?.sourceRect = sourceView.bounds
    browserMenu.popoverPresentationController?.popoverLayoutMargins = .init(equalInset: 4)
    browserMenu.popoverPresentationController?.permittedArrowDirections = [.up, .down]
    present(browserMenu, animated: true)
    return
  }

  private func pageActions(for pageURL: URL?, tab: (any TabState)?) -> [Action] {
    var actions: [Action] = [
      .init(id: .share) { @MainActor [unowned self] _ in
        self.dismiss(animated: true) {
          self.tabToolbarDidPressShare()
        }
        return .none
      },
      .init(id: .addBookmark) { @MainActor [unowned self] _ in
        self.dismiss(animated: true) {
          self.openAddBookmark()
        }
        return .none
      },
      .init(
        id: .toggleNightMode,
        state: Preferences.General.nightModeEnabled.value
      ) { @MainActor action in
        var actionCopy = action
        Preferences.General.nightModeEnabled.value.toggle()
        actionCopy.state = Preferences.General.nightModeEnabled.value
        return .updateAction(actionCopy)
      },
    ]
    // Browther: Playlist / Add to Playlist removed
    if BraveCore.FeatureList.kBraveShredFeature.enabled {
      let isShredAvailable = tabManager.selectedTab?.visibleURL?.isShredAvailable ?? false
      actions.append(
        .init(id: .shredData, attributes: isShredAvailable ? [] : [.disabled]) {
          @MainActor [unowned self] _ in
          self.dismiss(animated: true) {
            guard let tab = self.tabManager.selectedTab, let url = tab.visibleURL else { return }
            let alert = UIAlertController.shredDataAlert(url: url) { _ in
              self.shredData(for: url, in: tab)
            }
            self.present(alert, animated: true)
          }
          return .none
        }
      )
    }
    let printFormatter = tab?.view.viewPrintFormatter()
    actions.append(
      .init(id: .print) {
        @MainActor [unowned self] _ in
        self.dismiss(animated: true) {
          let printController = UIPrintInteractionController.shared
          printController.printFormatter = printFormatter
          printController.present(animated: true)
        }
        return .none
      }
    )
    if pageURL == nil {
      for index in actions.indices {
        actions[index].attributes.insert(.disabled)
      }
    }
    return actions
  }

  private func destinationMenuActions(for pageURL: URL?) -> [Action] {
    let isPrivateBrowsing = privateBrowsingManager.isPrivateBrowsing
    var actions: [Action] = [
      .init(id: .bookmarks) { @MainActor [unowned self] _ in
        let vc = BookmarksViewController(
          folder: bookmarkManager.lastVisitedFolder(),
          bookmarkManager: bookmarkManager,
          isPrivateBrowsing: privateBrowsingManager.isPrivateBrowsing
        )
        vc.toolbarUrlActionsDelegate = self
        let container = UINavigationController(rootViewController: vc)
        self.dismiss(animated: true) {
          self.present(container, animated: true)
        }
        return .none
      },
      .init(id: .history) { @MainActor [unowned self] _ in
        let vc = UIHostingController(
          rootView: HistoryView(
            model: HistoryModel(
              api: self.profileController.historyAPI,
              tabManager: self.tabManager,
              toolbarUrlActionsDelegate: self,
              dismiss: { [weak self] in self?.dismiss(animated: true) },
              askForAuthentication: self.askForLocalAuthentication
            )
          )
        )
        self.dismiss(animated: true) {
          self.present(vc, animated: true)
        }
        return .none
      },
      .init(id: .downloads) { @MainActor [unowned self] _ in
        UIApplication.shared.openBraveDownloadsFolder { success in
          if !success {
            self.dismiss(animated: true) {
              self.displayOpenDownloadsError()
            }
          }
        }
        return .none
      },
    ]
    // Browther: keep Playlist, remove Wallet, Leo, Brave Talk, Brave News
    if profileController.profile.prefs.isPlaylistAvailable {
      actions.append(
        .init(id: .playlist) { @MainActor [unowned self] _ in
          self.presentPlaylistController()
          return .none
        }
      )
    }
    return actions
  }

}
