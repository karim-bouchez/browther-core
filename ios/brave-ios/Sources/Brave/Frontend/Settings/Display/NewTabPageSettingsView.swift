// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BraveUI
import Foundation
import Preferences
import SwiftUI

struct NewTabPageSettingsView: View {
  @ObservedObject private var backgroundImages = Preferences.NewTabPage.backgroundImages
  @ObservedObject private var showNewTabPrivacyHub = Preferences.NewTabPage.showNewTabPrivacyHub
  @ObservedObject private var showNewTabFavourites = Preferences.NewTabPage.showNewTabFavourites

  var body: some View {
    Form {
      Section {
        Toggle(Strings.NTP.settingsBackgroundImages, isOn: $backgroundImages.value)
          .listRowBackground(Color(.secondaryBraveGroupedBackground))
      } header: {
        Text(Strings.NTP.settingsBackgroundImages)
      }
      Section {
        Toggle(Strings.PrivacyHub.privacyReportsTitle, isOn: $showNewTabPrivacyHub.value)
          .listRowBackground(Color(.secondaryBraveGroupedBackground))
        Toggle(Strings.Widgets.favoritesWidgetTitle, isOn: $showNewTabFavourites.value)
          .listRowBackground(Color(.secondaryBraveGroupedBackground))
      } header: {
        Text(Strings.Widgets.widgetTitle)
      }
    }
    .tint(Color(braveSystemName: .primary40))
    .navigationTitle(Strings.NTP.settingsTitle)
    .navigationBarTitleDisplayMode(.inline)
    .scrollContentBackground(.hidden)
    .background(Color(.braveGroupedBackground))
  }
}

class NTPTableViewController: UIHostingController<NewTabPageSettingsView> {
  init(rewards: BraveRewards?, linkTapped: ((URLRequest) -> Void)?) {
    super.init(rootView: .init())
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError()
  }
}
