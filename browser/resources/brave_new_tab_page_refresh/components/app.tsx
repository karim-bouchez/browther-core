/* Copyright (c) 2025 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

import * as React from 'react'
import Icon from '@brave/leo/react/icon'

import { SearchBox } from './search/search_box'
import { Background } from './background/background'
import { BackgroundClickRegion } from './background/background_click_region'
import { BackgroundCaption } from './background/background_caption'
import { SettingsModal, SettingsView } from './settings/settings_modal'
import { TopSites } from './top_sites/top_sites'
import { Clock } from './common/clock'
// Browther: News disabled — LazyNewsFeed not imported.
import { WidgetStack } from './widgets/widget_stack'
import { BrowtherAdBanner } from './widgets/browther_ad_banner'
import { BrowtherBetaNotice } from './widgets/browther_beta_notice'
import { useSearchLayoutReady, useWidgetLayoutReady } from './app_layout_ready'

import { style } from './app.style'

// Browther: AI Chat (Brave Leo) disabled — query_box not imported.
// Browther: useMediaQuery / threeColumnBreakpoint plus utilisés (un seul widget Stats).

export function App() {
  const searchLayoutReady = useSearchLayoutReady()
  const widgetLayoutReady = useWidgetLayoutReady()

  const [settingsView, setSettingsView] = React.useState<SettingsView | null>(
    null,
  )

  React.useEffect(() => {
    const params = new URLSearchParams(location.search)
    const settingsArg = params.get('openSettings')
    if (settingsArg === null) {
      return
    }
    setSettingsView(settingsArg === 'BraveNews' ? 'news' : 'background')
    history.pushState(null, '', '/')
  }, [])

  return (
    <div data-css-scope={style.scope}>
      <Background />
      <div className='background-filter allow-background-pointer-events' />
      <main className='allow-background-pointer-events'>
        <button
          className='clock'
          onClick={() => setSettingsView('clock')}
        >
          <Clock />
        </button>
        <button
          className='settings'
          onClick={() => setSettingsView('background')}
        >
          <Icon name='settings' />
        </button>
        {/* Browther : bandeau « accès anticipé », en tête pour être lu avant
            que l'attention parte sur la barre de recherche. `:empty` (bandeau
            fermé → BrowtherBetaNotice rend null) le retire du flux, sinon le
            gap 16px de main laisserait un trou en haut de page. */}
        <div className='beta-notice-container'>
          <BrowtherBetaNotice />
        </div>
        <div className='topsites-container'>
          <TopSites />
        </div>
        {/* Browther: bannière pub devndin-ads sous les favoris. Wrapper en
            scope app (pas le scope propre de la bannière) pour hériter du fade
            `main > *` quand la search box s'agrandit ; `:empty` (aucune pub
            servie → BrowtherAdBanner rend null) le retire du flux, pas de gap. */}
        <div className='ad-banner-container'>
          <BrowtherAdBanner />
        </div>
        <div className='searchbox-container'>
          {searchLayoutReady && (
            <Search showSearchSettings={() => setSettingsView('search')} />
          )}
        </div>
        <div
          className='
          spacer
          sponsored-background-safe-area
          allow-background-pointer-events'
        >
          <BackgroundClickRegion />
        </div>
        <div className='caption-container'>
          <BackgroundCaption />
        </div>
        <div className='widget-container'>
          {widgetLayoutReady && (
            // Browther: only Stats widget — news/vpn/rewards/talk widgets removed.
            // The right WidgetStack will be repurposed for Browther ads later.
            <WidgetStack
              name='left'
              tabs={['stats']}
            />
          )}
        </div>
      </main>
      {/* Browther: Brave News feed removed entirely. */}
      <SettingsModal
        isOpen={settingsView !== null}
        initialView={settingsView}
        onClose={() => setSettingsView(null)}
      />
    </div>
  )
}

function Search(props: { showSearchSettings: () => void }) {
  // Browther: AI Chat input ("Ask anything…" Brave Leo) disabled — always show
  // the standard SearchBox (URL bar / Google by default).
  return <SearchBox showSearchSettings={props.showSearchSettings} />
}
