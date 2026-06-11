/* Copyright (c) 2025 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

import { StateStore, createStateStore } from '$web-common/state_store'

import {
  ShieldsStats,
  ClockFormat,
  BrowtherAd,
} from 'gen/brave/browser/ui/webui/brave_new_tab_page_refresh/brave_new_tab_page.mojom.m.js'

export { ShieldsStats, ClockFormat, BrowtherAd }

export interface NewTabState {
  initialized: boolean
  showClock: boolean
  clockFormat: ClockFormat
  showShieldsStats: boolean
  shieldsStats: ShieldsStats | null
  showTalkWidget: boolean
  talkFeatureEnabled: boolean
  newsFeatureEnabled: boolean
  aiChatInputEnabled: boolean
  // Browther: bannières pub devndin-ads servies pour le placement NTP.
  browtherAds: BrowtherAd[]
  actions: NewTabActions
}

export type NewTabStore = StateStore<NewTabState>

export function defaultNewTabStore(): NewTabStore {
  return createStateStore<NewTabState>({
    initialized: false,
    showClock: false,
    clockFormat: ClockFormat.kAuto,
    showShieldsStats: false,
    shieldsStats: null,
    showTalkWidget: false,
    talkFeatureEnabled: false,
    newsFeatureEnabled: false,
    aiChatInputEnabled: false,
    browtherAds: [],
    actions: {
      setShowClock(showClock) {},
      setClockFormat(format) {},
      setShowShieldsStats(showShieldsStats) {},
      setShowTalkWidget(showTalkWidget) {},
      markBrowtherAdVisible(id) {},
      clickBrowtherAd(id) {},
    },
  })
}

export interface NewTabActions {
  setShowClock: (showClock: boolean) => void
  setClockFormat: (format: ClockFormat) => void
  setShowShieldsStats: (showShieldsStats: boolean) => void
  setShowTalkWidget: (showTalkWidget: boolean) => void
  // Browther: pub vue (intersection) → impression ; pub cliquée → ouvre click.
  markBrowtherAdVisible: (id: string) => void
  clickBrowtherAd: (id: string) => void
}
