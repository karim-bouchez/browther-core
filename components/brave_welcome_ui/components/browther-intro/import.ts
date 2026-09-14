// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import {
  addWebUiListener,
  removeWebUiListener,
  sendWithPromise
} from 'chrome://resources/js/cr.js'

import {
  BrowserProfile,
  ImportDataBrowserProxyImpl,
  WelcomeBrowserProxyImpl,
  defaultImportTypes
} from '../../api/welcome_browser_proxy'

// L'import de l'ancien navigateur, écran propre au desktop (Karim, 2026-09-13 :
// les écrans d'import Brave, violets, tombaient hors de l'introduction). Mêmes
// messages natifs que ces écrans (`BraveImportBulkDataHandler`), sans leur
// import groupé : il crée un PROFIL Browther par profil source, l'introduction
// importe dans le profil courant.

/** Ce que le navigateur source sait donner, dans l'ordre affiché. */
export type ImportItem =
  | 'favorites'
  | 'passwords'
  | 'history'
  | 'extensions'
  | 'payments'
  | 'autofillFormData'
  | 'search'

export const IMPORT_ITEMS: ImportItem[] = [
  'favorites',
  'passwords',
  'history',
  'extensions',
  'payments',
  'autofillFormData',
  'search'
]

/**
 * Bits de `user_data_importer::ImportItem`, plus `EXTENSIONS` et `PAYMENTS`
 * ajoutés par Brave (`chromium_src/…/importer_data_types.h`) : les événements
 * de progression nomment l'élément par son bit.
 */
const ITEM_BY_BIT: Record<number, ImportItem> = {
  1: 'history',
  2: 'favorites',
  8: 'passwords',
  16: 'search',
  64: 'autofillFormData',
  128: 'extensions',
  256: 'payments'
}

/** Les champs que Brave ajoute au profil source et au type TypeScript amont. */
export type SourceProfile = BrowserProfile & {
  browserType?: string
  extensions?: boolean
  payments?: boolean
}

/**
 * Ce qu'on peut importer : UN profil d'UN navigateur. Une seule liste, pas un
 * navigateur puis ses profils — deux niveaux de choix ne se lisaient pas
 * (recette Karim, 2026-09-13).
 */
export interface ImportSource {
  profile: SourceProfile
  browser: string
  /** Clé des icônes Brave ; absente pour un navigateur Chromium inconnu. */
  browserType?: string
  /** Nom du profil, seulement quand ce navigateur en a plusieurs. */
  profileLabel?: string
}

export type ImportStatus = 'idle' | 'running' | 'done' | 'failed'

export interface IntroImport {
  sources: ImportSource[]
  source: ImportSource | undefined
  status: ImportStatus
  /** L'élément que le navigateur est en train d'importer. */
  current: ImportItem | null
  /** Les éléments terminés. */
  imported: ImportItem[]
  selectSource: (index: number) => void
  start: () => void
}

/**
 * Les navigateurs dont l'application est installée (`GetInstalledBrowsers`,
 * macOS) : Brave propose tout dossier de données trouvé, même celui d'un
 * navigateur jamais installé. `null` : la plateforme ne sait pas le dire.
 * `undefined` tant que le natif n'a pas répondu.
 */
export function useInstalledBrowsers (): string[] | null | undefined {
  const [installed, setInstalled] = React.useState<string[] | null>()
  React.useEffect(() => {
    sendWithPromise('getInstalledBrowsers').then(setInstalled)
  }, [])
  return installed
}

export function installedOnly (
  profiles: SourceProfile[] | undefined,
  installed: string[] | null | undefined
): SourceProfile[] | undefined {
  if (!profiles || installed === undefined) return undefined
  if (installed === null) return profiles
  // Un navigateur Chromium que l'import ne sait pas nommer reste proposé : on
  // n'a rien pour dire qu'il est absent.
  return profiles.filter(p => !p.browserType || installed.includes(p.browserType))
}

export function offeredItems (profile: SourceProfile | undefined) {
  return profile ? IMPORT_ITEMS.filter(item => profile[item]) : []
}

/**
 * ⚠️ Pour les navigateurs Chromium, le natif colle le nom du profil à celui du
 * navigateur (« Google Chrome Your Chrome », `importer_list.cc`) et laisse
 * `profileName` vide : on l'en retire pour l'afficher à part.
 */
function listSources (profiles: SourceProfile[] | undefined): ImportSource[] {
  const all = profiles ?? []
  return all.map(profile => {
    const browser = profile.browserType ?? profile.name
    const siblings = all.filter(p => (p.browserType ?? p.name) === browser)
    const suffix = profile.name.startsWith(browser)
      ? profile.name.slice(browser.length).trim()
      : ''
    return {
      profile,
      browser,
      browserType: profile.browserType,
      profileLabel: siblings.length > 1
        ? (profile.profileName || suffix || undefined)
        : undefined
    }
  })
}

export function useIntroImport (
  profiles: SourceProfile[] | undefined
): IntroImport {
  const sources = React.useMemo(() => listSources(profiles), [profiles])
  const [sourceIndex, setSourceIndex] = React.useState<number>()
  const [status, setStatus] = React.useState<ImportStatus>('idle')
  const [current, setCurrent] = React.useState<ImportItem | null>(null)
  const [imported, setImported] = React.useState<ImportItem[]>([])
  // Les écouteurs natifs sont posés une fois : ils lisent l'état par ref.
  const running = React.useRef(false)
  const importedCount = React.useRef(0)

  // Présélection : le navigateur par défaut du système, comme l'écran Brave —
  // demandé au début de l'introduction, AVANT que l'écran précédent ne propose
  // de faire de Browther le navigateur par défaut.
  React.useEffect(() => {
    if (!sources.length || sourceIndex !== undefined) return
    setSourceIndex(sources[0].profile.index)
    WelcomeBrowserProxyImpl.getInstance().getDefaultBrowser().then(name => {
      const match = sources.find(s => s.browser === name)
      if (match) setSourceIndex(match.profile.index)
    })
  }, [sources])

  React.useEffect(() => {
    const finish = (next: ImportStatus) => {
      if (!running.current) return
      running.current = false
      setCurrent(null)
      setStatus(next)
    }
    const progress = addWebUiListener(
      'brave-import-data-status-changed',
      (info: { event: string, item?: number }) => {
        if (!running.current) return
        const item = info.item === undefined ? undefined : ITEM_BY_BIT[info.item]
        if (info.event === 'ImportItemStarted' && item) {
          setCurrent(item)
        } else if (info.event === 'ImportItemEnded' && item) {
          importedCount.current++
          setImported(list => list.includes(item) ? list : [...list, item])
          setCurrent(null)
        } else if (info.event === 'ImportEnded') {
          // ⚠️ Pas d'état « terminé » sans rien d'importé : un import qui ne
          // ramène rien a échoué (trousseau refusé, profil illisible).
          finish(importedCount.current > 0 ? 'done' : 'failed')
        }
      })
    // ⚠️ Ce message ne dit JAMAIS « succeeded » par ce handler : la surcharge
    // Brave de `NotifyImportProgress` court-circuite celle qui l'enverrait. Il
    // ne sert qu'à Safari sans accès complet au disque, refusé avant même de
    // commencer (le natif ouvre ensuite son guide des réglages macOS).
    const outcome = addWebUiListener('import-data-status-changed',
      (value: string) => {
        if (value === 'failed') finish('failed')
      })
    return () => {
      removeWebUiListener(progress)
      removeWebUiListener(outcome)
    }
  }, [])

  const source = sources.find(s => s.profile.index === sourceIndex) ?? sources[0]

  // Changer de navigateur ou de profil après un import repart d'une scène
  // vierge : les coches du précédent ne doivent pas passer pour les siennes.
  const reset = () => {
    setStatus('idle')
    setCurrent(null)
    setImported([])
  }

  const start = () => {
    if (!source || running.current) return
    running.current = true
    importedCount.current = 0
    setImported([])
    setCurrent(null)
    setStatus('running')
    ImportDataBrowserProxyImpl.getInstance().importData(
      source.profile.index, defaultImportTypes)
  }

  return {
    sources,
    source,
    status,
    current,
    imported,
    selectSource: (index: number) => {
      if (running.current || index === source?.profile.index) return
      setSourceIndex(index)
      reset()
    },
    start
  }
}
