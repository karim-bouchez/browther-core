// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

import { mangle } from 'lit_mangler'

// Inject a Browther product-logo into the cr-toolbar slot. Without this,
// cr-toolbar falls back to its default <picture>, which uses Chromium's
// chrome_logo_dark.svg (upstream file restored each `pnpm build` init).
// Using chrome://theme/current-channel-logo resolves to IDR_PRODUCT_LOGO_32
// (= Browther shield) for both light AND dark mode. Same pattern as the
// Polymer override in brave/browser/resources/settings/br/settings_ui.ts.
mangle((element) => {
  const toolbar = element.querySelector('cr-toolbar')
  if (!toolbar) {
    throw new Error(
      '[Browther Extensions Overrides] Could not find cr-toolbar. '
        + 'Has the structure changed?',
    )
  }
  toolbar.insertAdjacentHTML(
    'beforeend',
    '<img slot="product-logo"'
      + ' srcset="chrome://theme/current-channel-logo@1x 1x,'
      + ' chrome://theme/current-channel-logo@2x 2x"'
      + ' alt="" role="presentation">',
  )
}, (t) => t.text.includes('id="toolbar"'))
