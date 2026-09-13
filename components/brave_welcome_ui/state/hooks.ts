// Copyright (c) 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import {
  BrowserProfile,
  ImportDataBrowserProxyImpl,
  WelcomeBrowserProxyImpl
} from '../api/welcome_browser_proxy'
import { loadTimeData } from '$web-common/loadTimeData'
import { BrowserType, ViewType } from './component_types'
import DataContext from './context'

const browserList = Object.values(BrowserType)

export const getValidBrowserProfiles = (profiles: BrowserProfile[]) => {
  const getBrowserName = (toFind: string) => {
    // TODO(tali): Add exact matching for cases like "Chrome" vs "Chrome Canary"
    return browserList.find(browser => toFind.includes(browser))
  }

  let results = profiles
    .filter((profile) => profile.name !== 'Bookmarks HTML File')
    .map((profile) => {
      const browserType = getBrowserName(profile.name)
      // Introducing a new property here
      return { ...profile, browserType }
    })

  return results
}

export function useInitializeImportData () {
  const [browserProfiles, setProfiles] = React.useState<BrowserProfile[] | undefined>(undefined)

  React.useEffect(() => {
    const fetchAllBrowserProfiles = async () => {
      const res = await ImportDataBrowserProxyImpl.getInstance().initializeImportDialog()
      const validProfiles = getValidBrowserProfiles(res)
      setProfiles(validProfiles)
    }

    fetchAllBrowserProfiles()
  }, [])

  return {
    browserProfiles
  }
}

export function useProfileCount () {
  const profileCountRef = React.useRef(0)

  const incrementCount = () => {
    profileCountRef.current++
  }

  const decrementCount = () => {
    profileCountRef.current--
  }

  return {
    profileCountRef,
    incrementCount,
    decrementCount
  }
}

/**
 * Browther : l'ancien parcours Brave (par défaut → thème/import → consentement
 * → chaînes) n'est plus présenté au premier lancement — l'introduction le
 * remplace. Il reste joignable pour la recette : `browther://welcome/?legacy`.
 */
export const isLegacyWelcomeFlow =
  new URLSearchParams(window.location.search).has('legacy')

/** Quitte l'accueil vers la page de fin (Nouvel Onglet, ou page d'aide Brave). */
export function completeWelcome () {
  WelcomeBrowserProxyImpl.getInstance().getWelcomeCompleteURL().then(url => {
    window.open(url || 'chrome://newtab', '_self', 'noopener')
  })
}

export const shouldPlayAnimations = loadTimeData.getBoolean('hardwareAccelerationEnabledAtStartup') &&
    !window.matchMedia('(prefers-reduced-motion: reduce)').matches

// This hook is a kind of finite state machine that helps transition between view types.
// It's intended to put transition logic in one place, so that we can easily understand
// what's going on and add or remove a state from the graph.
// Returns three transition functions: forward(), back() and skip().
interface ViewTypeState {
  forward: ViewType;
  back?: ViewType;
  skip?: ViewType;
  fail?: ViewType;
}

export function useViewTypeTransition(currentViewType: ViewType | undefined) : ViewTypeState {
  const { browserProfiles, currentSelectedBrowserProfiles} = React.useContext(DataContext)

  const states = React.useMemo(() => {
    // Browther: HelpWDP (Web Discovery) supprimé du flow.
    // L'écran HelpImprove est rebrandé pour Sentry/PostHog (cf. Phase 3.5).
    // Browther : après l'introduction, l'import mène directement au Nouvel
    // Onglet — l'écran de consentement disparaît du premier lancement, comme
    // sur iOS et Android (Sentry et PostHog restent actifs par défaut et
    // désactivables dans les Réglages ; décision Karim, 2026-09-12).
    const nextAfterImport = isLegacyWelcomeFlow
      ? ViewType.HelpImprove
      : ViewType.WelcomeComplete

    return {
      [ViewType.DefaultBrowser]: {  // The initial state view
        forward: !browserProfiles || browserProfiles.length === 0 ?
            ViewType.ImportSelectTheme : ViewType.ImportSelectBrowser
      },
      [ViewType.ImportSelectTheme]: {
        forward: nextAfterImport
      },
      [ViewType.ImportSelectBrowser]: {
        forward: currentSelectedBrowserProfiles &&
            currentSelectedBrowserProfiles.length > 1 ?
            ViewType.ImportSelectProfile : ViewType.ImportInProgress,
        skip: nextAfterImport,
      },
      [ViewType.ImportSelectProfile]: {
        forward: ViewType.ImportInProgress,
        back: ViewType.ImportSelectBrowser
      },
      [ViewType.ImportInProgress]: {
        forward: ViewType.ImportSucceeded,
        fail: ViewType.ImportFailed,
      },
      [ViewType.ImportSucceeded]: {
        forward: nextAfterImport
      },
      [ViewType.ImportFailed]: {
        forward: nextAfterImport
      },
      // Browther : HelpImprove n'est plus la fin du parcours — il passe la main
      // à FollowChannels, qui porte désormais la redirection de sortie
      // (`getWelcomeCompleteURL`).
      [ViewType.HelpImprove]: {
        forward: ViewType.FollowChannels
      },
      [ViewType.FollowChannels]: {
        forward: ViewType.FollowChannels   // The end state view
      },
      // Browther : l'introduction puis la sortie ne transitent pas par cette
      // machine (cf. `MainContainer`) ; présentes pour que la table couvre
      // toutes les vues.
      [ViewType.BrowtherIntro]: {
        forward: ViewType.WelcomeComplete
      },
      [ViewType.WelcomeComplete]: {
        forward: ViewType.WelcomeComplete
      },
    }
  }, [browserProfiles, currentSelectedBrowserProfiles])

  return states[currentViewType?? ViewType.DefaultBrowser]
}
