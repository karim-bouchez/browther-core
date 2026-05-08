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
    const [{ enabled }, { mode }, sliders, dev] = await Promise.all([
      api().getEnabled(),
      api().getMode(),
      api().getSliders(),
      api().getDevSettings(),
    ])
    setUIEnabled(enabled)
    setUIMode(mode)
    setUISlider('conf-body', sliders.confBody)
    setUISlider('conf-face', sliders.confFace)
    setUISlider('gender-certainty', sliders.genderCertainty)
    setUIDebugMode(dev.debugMode)
    setUICapture(dev.captureMode)
  } catch (err) {
    console.error('[basarunaa-panel] refreshState failed', err)
  }
}

function setUIDebugMode(mode: string) {
  const radios = document.querySelectorAll<HTMLInputElement>('input[name="debug-mode"]')
  radios.forEach(r => { r.checked = (r.value === mode) })
}

function setUICapture(enabled: boolean) {
  const toggle = document.getElementById('capture-toggle') as HTMLInputElement | null
  if (toggle) toggle.checked = enabled
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

function setUISlider(id: string, value: number) {
  const slider = document.getElementById(id) as HTMLInputElement | null
  const label = document.getElementById(`${id}-value`)
  const pct = Math.round(value * 100)
  if (slider) slider.value = String(pct)
  if (label) label.textContent = `${pct}%`
}

function bindSlider(id: string, setter: (v: number) => void) {
  const slider = document.getElementById(id) as HTMLInputElement | null
  const label = document.getElementById(`${id}-value`)
  if (!slider) return
  slider.addEventListener('input', () => {
    if (label) label.textContent = `${slider.value}%`
  })
  slider.addEventListener('change', () => {
    const value = Number(slider.value) / 100
    try {
      setter(value)
    } catch (err) {
      console.error(`[basarunaa-panel] set ${id} failed`, err)
    }
  })
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

  bindSlider('conf-body', v => api().setConfBody(v))
  bindSlider('conf-face', v => api().setConfFace(v))
  bindSlider('gender-certainty', v => api().setGenderCertainty(v))

  document.querySelectorAll<HTMLInputElement>('input[name="debug-mode"]').forEach(radio => {
    radio.addEventListener('change', () => {
      if (!radio.checked) return
      try {
        api().setDebugMode(radio.value)
      } catch (err) {
        console.error('[basarunaa-panel] setDebugMode failed', err)
      }
    })
  })

  const captureToggle = document.getElementById('capture-toggle') as HTMLInputElement | null
  captureToggle?.addEventListener('change', () => {
    try {
      api().setCaptureMode(captureToggle.checked)
    } catch (err) {
      console.error('[basarunaa-panel] setCaptureMode failed', err)
    }
  })
})
