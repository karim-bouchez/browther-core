// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

// Browther: minimal entry for the bisect rebuild. Mirrors the load-bearing
// VPN handshake: call panelHandler.showUI() on init AND on every
// `visibilitychange` -> visible. This is the trick that makes the bubble
// re-appear on the second open when the WebContents is cached by the
// WebUIBubbleManager.

import getPanelBrowserAPI from './api/panel_browser_api'

function notifyShowUI() {
  try {
    getPanelBrowserAPI().panelHandler.showUI()
  } catch (err) {
    console.error('[basarunaa-panel] showUI failed', err)
  }
}

function onVisibilityChange() {
  if (document.visibilityState === 'visible') {
    notifyShowUI()
  }
}

document.addEventListener('DOMContentLoaded', () => {
  notifyShowUI()
  document.addEventListener('visibilitychange', onVisibilityChange)
})
