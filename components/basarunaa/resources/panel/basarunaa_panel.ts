// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

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
    refreshState()
  }
}

async function refreshState() {
  try {
    const { enabled } = await getPanelBrowserAPI().panelHandler.getEnabled()
    setUIEnabled(enabled)
  } catch (err) {
    console.error('[basarunaa-panel] getEnabled failed', err)
  }
}

function setUIEnabled(enabled: boolean) {
  const toggle = document.getElementById('enabled-toggle') as HTMLInputElement | null
  const status = document.getElementById('status')
  if (toggle) toggle.checked = enabled
  if (status) status.textContent = enabled ? 'Actif' : 'Désactivé'
}

document.addEventListener('DOMContentLoaded', () => {
  notifyShowUI()
  refreshState()
  document.addEventListener('visibilitychange', onVisibilityChange)

  const toggle = document.getElementById('enabled-toggle') as HTMLInputElement | null
  if (toggle) {
    toggle.addEventListener('change', () => {
      const enabled = toggle.checked
      setUIEnabled(enabled)
      try {
        getPanelBrowserAPI().panelHandler.setEnabled(enabled)
      } catch (err) {
        console.error('[basarunaa-panel] setEnabled failed', err)
      }
    })
  }
})
