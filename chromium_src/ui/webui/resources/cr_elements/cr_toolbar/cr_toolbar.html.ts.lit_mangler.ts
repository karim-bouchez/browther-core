// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

import { mangle } from 'lit_mangler'

// Browther: the default cr-toolbar `product-logo` slot renders a <picture>
// whose dark-mode <source> points at Chromium's chrome_logo_dark.svg — that
// upstream file is the Brave lion and is restored on every `pnpm build`. Any
// WebUI page that uses cr-toolbar without injecting its own product-logo slot
// (history, bookmarks, downloads, …) therefore shows the lion in dark mode,
// while light mode already resolves chrome://theme/current-channel-logo (the
// Browther shield, IDR_PRODUCT_LOGO_32).
//
// Removing the dark <source> makes the <picture> fall back to its <img
// srcset="chrome://theme/current-channel-logo"> in BOTH light and dark — i.e.
// the Browther shield everywhere, fixing every cr-toolbar surface at once.
// Pages that inject their own slot (settings via settings_ui.ts, extensions via
// toolbar.html.ts.lit_mangler.ts) are unaffected: slotted content always wins
// over this default fallback.
mangle(
  (element) => {
    const darkSource = element.querySelector('source')
    if (!darkSource) {
      throw new Error(
        '[Browther cr-toolbar] Could not find the dark-mode <source> in the '
          + 'product-logo <picture>. Has the cr-toolbar markup changed?',
      )
    }
    darkSource.remove()
  },
  (literal) => literal.text.includes('current-channel-logo'),
)
