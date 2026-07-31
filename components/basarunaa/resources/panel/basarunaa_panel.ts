// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

import { loadTimeData } from '../../../common/loadTimeData'

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
    const [{ enabled }, { mode }, censorEyes, nsfw, sliders, dev, protectedContent] = await Promise.all([
      api().getEnabled(),
      api().getMode(),
      api().getCensorEyes(),
      api().getNsfwEnabled(),
      api().getSliders(),
      api().getDevSettings(),
      api().getProtectedContent(),
    ])
    setUIEnabled(enabled)
    setUIProtectedHint(protectedContent.visible)
    setUIMode(mode)
    setUICensorEyes(censorEyes.enabled)
    setUINsfw(nsfw.enabled)
    setUISlider('conf-body', sliders.confBody)
    setUISlider('gender-certainty', sliders.genderCertainty)
    setUIHandFilter(sliders.minSkeleton > 0)
    setUISlider('nsfw-conf', sliders.nsfwConf)
    setUISlider('nudenet-conf', sliders.nudenetConf)
    setUIDebugMode(dev.debugMode)
    setUICapture(dev.captureMode)
    setUIBlurEnabled(dev.blurEnabled)
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

function setUIBlurEnabled(enabled: boolean) {
  const toggle = document.getElementById('blur-toggle') as HTMLInputElement | null
  if (toggle) toggle.checked = enabled
}

function setUIEnabled(enabled: boolean) {
  const toggle = document.getElementById('enabled-toggle') as HTMLButtonElement | null
  const status = document.getElementById('status')
  if (toggle) {
    toggle.classList.toggle('on', enabled)
    toggle.setAttribute('aria-pressed', String(enabled))
  }
  if (status) {
    status.textContent = loadTimeData.getString(enabled ? 'statusOn' : 'statusOff')
  }
  document.body.dataset.disabled = enabled ? 'false' : 'true'
}

// Encadré « contenu protégé (DRM) » : explique le badge ambre de la toolbar.
// La condition (feature ON + verdict DRM sur l'onglet actif) est appliquée
// côté browser — ici on ne fait qu'afficher.
function setUIProtectedHint(visible: boolean) {
  const box = document.getElementById('protected-hint')
  if (box) box.hidden = !visible
  // Le gros toggle passe à l'ambre quand la feature est ON
  // mais sans effet ici — un toggle vert au-dessus de cet encadré se contredit.
  document.getElementById('enabled-toggle')?.classList.toggle('protected', visible)
}

function setUIMode(mode: string) {
  const radios = document.querySelectorAll<HTMLInputElement>('input[name="mode"]')
  radios.forEach(r => { r.checked = (r.value === mode) })
}

function setUICensorEyes(enabled: boolean) {
  const toggle = document.getElementById('censor-eyes-toggle') as HTMLInputElement | null
  if (toggle) toggle.checked = enabled
}

function setUINsfw(enabled: boolean) {
  const toggle = document.getElementById('nsfw-toggle') as HTMLInputElement | null
  if (toggle) toggle.checked = enabled
}

function setUISlider(id: string, value: number) {
  const slider = document.getElementById(id) as HTMLInputElement | null
  const label = document.getElementById(`${id}-value`)
  const pct = Math.round(value * 100)
  if (slider) slider.value = String(pct)
  if (label) label.textContent = `${pct}%`
}

// Le filtre « main seule » est un booléen côté UI ; la pref native min_skeleton
// reste un double (0 = off, > 0 = on — pas de nouvelle pref à migrer).
function setUIHandFilter(on: boolean) {
  const toggle = document.getElementById('hand-filter-toggle') as HTMLInputElement | null
  if (toggle) toggle.checked = on
}

function bindHandFilterToggle(setter: (v: number) => void) {
  const toggle = document.getElementById('hand-filter-toggle') as HTMLInputElement | null
  if (!toggle) return
  toggle.addEventListener('change', () => {
    try {
      setter(toggle.checked ? 1 : 0)
    } catch (err) {
      console.error('[basarunaa-panel] set min-skeleton failed', err)
    }
  })
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

  // Section Debug visible seulement si le debug-UI est débloqué (Component dev,
  // ou build prod lancé avec --basarunaa-debug-ui). Sinon cachée + le rendu
  // ignore les prefs debug (forcés none/off côté browser).
  if (loadTimeData.getBoolean('debugUi')) {
    document.getElementById('dev-section')?.removeAttribute('hidden')
  }

  const toggle = document.getElementById('enabled-toggle') as HTMLButtonElement | null
  toggle?.addEventListener('click', () => {
    const enabled = !toggle.classList.contains('on')
    setUIEnabled(enabled)
    try {
      api().setEnabled(enabled)
      // L'encadré « contenu protégé » est gaté sur la pref : on le relit après
      // l'écriture. Mojo garantit l'ordre sur le même pipe, donc la réponse
      // reflète bien la nouvelle valeur malgré le fire-and-forget de setEnabled.
      api().getProtectedContent().then(r => setUIProtectedHint(r.visible))
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

  const censorEyesToggle = document.getElementById('censor-eyes-toggle') as HTMLInputElement | null
  censorEyesToggle?.addEventListener('change', () => {
    try {
      api().setCensorEyes(censorEyesToggle.checked)
    } catch (err) {
      console.error('[basarunaa-panel] setCensorEyes failed', err)
    }
  })

  const nsfwToggle = document.getElementById('nsfw-toggle') as HTMLInputElement | null
  nsfwToggle?.addEventListener('change', () => {
    try {
      api().setNsfwEnabled(nsfwToggle.checked)
    } catch (err) {
      console.error('[basarunaa-panel] setNsfwEnabled failed', err)
    }
  })

  bindSlider('conf-body', v => api().setConfBody(v))
  bindSlider('gender-certainty', v => api().setGenderCertainty(v))
  bindHandFilterToggle(v => api().setMinSkeleton(v))
  bindSlider('nsfw-conf', v => api().setNsfwConf(v))
  bindSlider('nudenet-conf', v => api().setNudenetConf(v))

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

  const blurToggle = document.getElementById('blur-toggle') as HTMLInputElement | null
  blurToggle?.addEventListener('change', () => {
    try {
      api().setBlurEnabled(blurToggle.checked)
    } catch (err) {
      console.error('[basarunaa-panel] setBlurEnabled failed', err)
    }
  })
})
