// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import {
  addWebUiListener,
  removeWebUiListener
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

/** Un navigateur installé, avec ses profils. */
export interface ImportSource {
  name: string
  /** Clé des icônes Brave ; absente pour un navigateur Chromium inconnu. */
  browserType?: string
  profiles: SourceProfile[]
}

export type ImportStatus = 'idle' | 'running' | 'done' | 'failed'

export interface IntroImport {
  sources: ImportSource[]
  source: ImportSource | undefined
  profile: SourceProfile | undefined
  status: ImportStatus
  /** L'élément que le navigateur est en train d'importer. */
  current: ImportItem | null
  /** Les éléments terminés. */
  imported: ImportItem[]
  selectSource: (name: string) => void
  selectProfile: (index: number) => void
  start: () => void
}

export function offeredItems (profile: SourceProfile | undefined) {
  return profile ? IMPORT_ITEMS.filter(item => profile[item]) : []
}

function groupSources (profiles: SourceProfile[] | undefined): ImportSource[] {
  const sources: ImportSource[] = []
  for (const profile of profiles ?? []) {
    const name = profile.browserType ?? profile.name
    let source = sources.find(s => s.name === name)
    if (!source) {
      source = { name, browserType: profile.browserType, profiles: [] }
      sources.push(source)
    }
    source.profiles.push(profile)
  }
  return sources
}

export function useIntroImport (
  profiles: SourceProfile[] | undefined
): IntroImport {
  const sources = React.useMemo(() => groupSources(profiles), [profiles])
  const [sourceName, setSourceName] = React.useState<string>()
  const [profileIndex, setProfileIndex] = React.useState<number>()
  const [status, setStatus] = React.useState<ImportStatus>('idle')
  const [current, setCurrent] = React.useState<ImportItem | null>(null)
  const [imported, setImported] = React.useState<ImportItem[]>([])
  // Les écouteurs natifs sont posés une fois : ils lisent l'état par ref.
  const running = React.useRef(false)
  const importedCount = React.useRef(0)

  // Présélection : le navigateur par défaut du système, comme l'écran Brave.
  React.useEffect(() => {
    if (!sources.length || sourceName) return
    setSourceName(sources[0].name)
    WelcomeBrowserProxyImpl.getInstance().getDefaultBrowser().then(name => {
      if (sources.some(s => s.name === name)) setSourceName(name)
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

  const source = sources.find(s => s.name === sourceName)
  const profile = source?.profiles.find(p => p.index === profileIndex) ??
    source?.profiles[0]

  // Changer de navigateur ou de profil après un import repart d'une scène
  // vierge : les coches du précédent ne doivent pas passer pour les siennes.
  const reset = () => {
    setStatus('idle')
    setCurrent(null)
    setImported([])
  }

  const start = () => {
    if (!profile || running.current) return
    running.current = true
    importedCount.current = 0
    setImported([])
    setCurrent(null)
    setStatus('running')
    ImportDataBrowserProxyImpl.getInstance().importData(
      profile.index, defaultImportTypes)
  }

  return {
    sources,
    source,
    profile,
    status,
    current,
    imported,
    selectSource: (name: string) => {
      if (running.current || name === source?.name) return
      setSourceName(name)
      setProfileIndex(undefined)
      reset()
    },
    selectProfile: (index: number) => {
      if (running.current || index === profile?.index) return
      setProfileIndex(index)
      reset()
    },
    start
  }
}
