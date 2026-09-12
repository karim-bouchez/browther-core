// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Les images de l'introduction historique — logos WhatsApp/Telegram, visuel
/// dev&din — vivent dans ce module. L'introduction Browther (module `Brave`)
/// les réutilise telles quelles : dupliquer les fichiers ferait diverger deux
/// copies du même logo au premier changement de charte.
public enum BrowtherOnboardingAssets {
  public static let bundle = Bundle.module
}
