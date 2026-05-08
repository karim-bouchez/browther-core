// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

import getPanelBrowserAPI from './api/panel_browser_api'

function api() {
  return getPanelBrowserAPI().panelHandler
}

function notifyShowUI() {
  try {
    api().showUI()
  } catch (err) {
    console.error('[basarunaa-panel] showUI failed', err)
  }
}

async function refreshState() {
  try {
    const [{ enabled }, { mode }] = await Promise.all([
      api().getEnabled(),
      api().getMode(),
    ])
    setUIEnabled(enabled)
    setUIMode(mode)
  } catch (err) {
    console.error('[basarunaa-panel] refreshState failed', err)
  }
}

function setUIEnabled(enabled: boolean) {
  const toggle = document.getElementById('enabled-toggle') as HTMLInputElement | null
  const status = document.getElementById('status')
  if (toggle) toggle.checked = enabled
  if (status) status.textContent = enabled ? 'Actif' : 'Désactivé'
  document.body.dataset.disabled = enabled ? 'false' : 'true'
}

function setUIMode(mode: string) {
  const radios = document.querySelectorAll<HTMLInputElement>('input[name="mode"]')
  radios.forEach(r => { r.checked = (r.value === mode) })
}

function onVisibilityChange() {
  if (document.visibilityState === 'visible') {
    notifyShowUI()
    refreshState()
  }
}

document.addEventListener('DOMContentLoaded', () => {
  notifyShowUI()
  refreshState()
  document.addEventListener('visibilitychange', onVisibilityChange)

  const toggle = document.getElementById('enabled-toggle') as HTMLInputElement | null
  toggle?.addEventListener('change', () => {
    const enabled = toggle.checked
    setUIEnabled(enabled)
    try {
      api().setEnabled(enabled)
    } catch (err) {
      console.error('[basarunaa-panel] setEnabled failed', err)
    }
  })

  document.querySelectorAll<HTMLInputElement>('input[name="mode"]').forEach(radio => {
    radio.addEventListener('change', () => {
      if (!radio.checked) return
      try {
        api().setMode(radio.value)
      } catch (err) {
        console.error('[basarunaa-panel] setMode failed', err)
      }
    })
  })
})
