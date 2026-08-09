// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

import { loadTimeData } from '../../../common/loadTimeData'

import getPanelBrowserAPI, { ProtectedContentState } from './api/panel_browser_api'

function api() {
  return getPanelBrowserAPI().panelHandler
}

// ⚠️ LOAD-BEARING — ne pas retirer, ne pas rendre conditionnel.
// Sans ce signal (et son jumeau sur `visibilitychange`), l'embedder ne révèle
// jamais le widget après la première ouverture : la bulle s'ouvre une fois puis
// plus jamais. C'est le bug qui avait motivé la bascule du panel Basarunaa en
// WebUI (2026-05-07, 3e710c0796b), et la raison d'être de ce handshake côté
// mojom (cf. sawtunaa_panel.mojom PanelHandler.ShowUI).
function notifyShowUI() {
  try {
    api().showUI()
  } catch (err) {
    console.error('[sawtunaa-panel] showUI failed', err)
  }
}

async function refreshState() {
  try {
    const state = await api().getState()
    setUIEnabled(state.enabled)
    setUIReloadHint(state.showReloadHint)
    setUIProtectedHint(state.protectedState)
    setUIReportSite(state.canReportSite, state.reportDomain, state.analyticsOff)
  } catch (err) {
    console.error('[sawtunaa-panel] refreshState failed', err)
  }
}

// Écrit « Seul <domaine> est envoyé… » avec le domaine en gras, sans passer
// par innerHTML : le domaine vient du browser, mais on ne construit jamais de
// HTML à partir d'une donnée — on assemble des nœuds de texte.
function fillPrivacyLine(el: HTMLElement, domain: string) {
  const text = loadTimeData.getStringF('reportSitePrivacy', domain)
  el.textContent = ''
  const at = text.indexOf(domain)
  if (at < 0) {
    el.textContent = text
    return
  }
  const strong = document.createElement('b')
  strong.textContent = domain
  el.append(text.slice(0, at), strong, text.slice(at + domain.length))
}

// Bloc « ça ne marche pas sur ce site ». Toutes les conditions sont calculées
// côté browser (le WebUI ne connaît aucune règle) :
//  - pas de domaine (page interne) → rien à signaler, bloc masqué ;
//  - statistiques d'usage coupées → l'envoi serait un no-op, donc on l'explique
//    au lieu d'afficher un bouton sans effet.
// Le domaine est montré AVANT le clic : ce qui part est visible, pas promis.
function setUIReportSite(
  canReport: boolean, domain: string, analyticsOff: boolean) {
  const box = document.getElementById('report-site')
  const btn = document.getElementById('report-site-btn') as HTMLButtonElement | null
  const privacy = document.getElementById('report-privacy')
  const done = document.getElementById('report-done')
  if (!box || !btn || !privacy || !done) return
  if (!canReport && !analyticsOff) {
    box.setAttribute('hidden', '')
    return
  }
  box.removeAttribute('hidden')
  done.setAttribute('hidden', '')
  btn.removeAttribute('hidden')
  if (analyticsOff) {
    btn.disabled = true
    privacy.textContent = loadTimeData.getString('reportSiteAnalyticsOff')
    return
  }
  btn.disabled = false
  fillPrivacyLine(privacy, domain)
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
}

// Sawtunaa V2 : le tap audio natif décide PAR PLAYER, à la création du
// WebMediaPlayer. Activer Sawtunaa pendant qu'un média joue ne change donc rien
// pour ce média-là tant que l'onglet n'est pas rechargé (OFF, lui, est
// quasi-live). Le browser a déjà appliqué toutes les conditions (tap natif
// actif, média ayant joué, pref ON) — ici on ne fait qu'afficher.
function setUIReloadHint(visible: boolean) {
  const box = document.getElementById('reload-hint')
  if (box) box.hidden = !visible
}

function setUIProtectedHint(state: number) {
  const box = document.getElementById('protected-hint')
  const text = document.getElementById('protected-hint-text')
  if (!box || !text) return
  const visible = state !== ProtectedContentState.kNone
  // Le gros toggle passe à l'ambre quand la feature est ON
  // mais sans effet ici — un toggle vert au-dessus de cet encadré se contredit.
  document.getElementById('enabled-toggle')?.classList.toggle('protected', visible)
  if (visible) {
    // Le texte DIFFÈRE selon le cas, et la nuance est cruciale (retour Karim) :
    // quand la lecture est BLOQUÉE, installer l'app ne suffit pas — la page
    // elle-même ne joue pas ici, il faut d'abord l'ouvrir ailleurs.
    text.textContent = loadTimeData.getString(
      state === ProtectedContentState.kBlocked
        ? 'protectedHintBlocked'
        : 'protectedHint')
  }
  box.hidden = !visible
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

  const toggle = document.getElementById('enabled-toggle') as HTMLButtonElement | null
  toggle?.addEventListener('click', () => {
    const enabled = !toggle.classList.contains('on')
    setUIEnabled(enabled)
    try {
      api().setEnabled(enabled)
    } catch (err) {
      console.error('[sawtunaa-panel] setEnabled failed', err)
      return
    }
    // Les deux encadrés dépendent de la pref : on relit après l'écriture.
    // Mojo garantit l'ordre sur le même pipe, donc `getState` voit bien la
    // nouvelle valeur malgré le fire-and-forget de `setEnabled`.
    refreshState()
  })

  const reportBtn = document.getElementById('report-site-btn') as HTMLButtonElement | null
  reportBtn?.addEventListener('click', async () => {
    reportBtn.disabled = true
    try {
      const { sent } = await api().reportSite()
      // Confirmation seulement si l'envoi a eu lieu — pas de « merci » par
      // optimisme.
      if (sent) {
        document.getElementById('report-done')?.removeAttribute('hidden')
        reportBtn.setAttribute('hidden', '')
      } else {
        reportBtn.disabled = false
      }
    } catch (err) {
      console.error('[sawtunaa-panel] reportSite failed', err)
      reportBtn.disabled = false
    }
  })

  document.getElementById('reload-hint')?.addEventListener('click', () => {
    try {
      api().reloadActiveTab()
    } catch (err) {
      console.error('[sawtunaa-panel] reloadActiveTab failed', err)
    }
  })

  document.getElementById('protected-action')?.addEventListener('click', () => {
    try {
      api().openSawtunaaAppPage()
    } catch (err) {
      console.error('[sawtunaa-panel] openSawtunaaAppPage failed', err)
    }
  })
})
