/* Copyright (c) 2025 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

import * as React from 'react'

import { useNewTabState } from '../../context/new_tab_context'
import { getString } from '../../lib/strings'

import { style } from './stats_widget.style'

const countFormatter = new Intl.NumberFormat(undefined, {
  maximumFractionDigits: 0,
  useGrouping: true,
})

export function StatsWidget() {
  const stats = useNewTabState((s) => s.shieldsStats)

  function renderUnits(parts: Intl.NumberFormatPart[]) {
    return parts.map(({ type, value }, index) => {
      if (type === 'unit') {
        return (
          <span
            key={`unit-${index}`}
            className='units'
          >
            {value}
          </span>
        )
      }
      return value
    })
  }

  return (
    <div data-css-scope={style.scope}>
      <div className='title'>{getString(S.NEW_TAB_STATS_TITLE)}</div>
      <div className='data'>
        <div>
          <div className='music-removed'>
            <div className='value'>
              {stats
                && renderUnits(formatTimeFromSeconds(stats.musicSecondsRemoved))}
            </div>
            {getString(S.NEW_TAB_STATS_MUSIC_REMOVED_TEXT)}
          </div>
          <div className='persons-blurred'>
            <div className='value'>
              {stats && countFormatter.format(stats.personsBlurred)}
            </div>
            {getString(S.NEW_TAB_STATS_PERSONS_BLURRED_TEXT)}
          </div>
          <div className='ads-blocked'>
            <div className='value'>
              {stats && countFormatter.format(stats.adsBlocked)}
            </div>
            {getString(S.NEW_TAB_STATS_ADS_BLOCKED_TEXT)}
          </div>
        </div>
      </div>
    </div>
  )
}

function formatTimeInterval(
  value: number,
  unit: 'day' | 'hour' | 'minute' | 'second',
  maximumFractionDigits: number = 0,
) {
  return new Intl.NumberFormat(undefined, {
    style: 'unit',
    unit,
    unitDisplay: 'long',
    maximumFractionDigits,
    roundingMode: 'ceil',
  }).formatToParts(value)
}

// `seconds` est le compteur cumulatif kStatsMusicSecondsTotal (uint64 côté C++,
// passé en double via mojo). Affiche l'unité la plus pertinente (jours,
// heures, minutes, secondes) avec une fraction utile.
function formatTimeFromSeconds(seconds: number) {
  const minutes = seconds / 60
  const hours = minutes / 60
  const days = hours / 24

  if (days >= 1) {
    return formatTimeInterval(days, 'day', 2)
  }
  if (hours >= 1) {
    return formatTimeInterval(hours, 'hour', 1)
  }
  if (minutes >= 1) {
    return formatTimeInterval(minutes, 'minute')
  }
  if (seconds >= 1) {
    return formatTimeInterval(seconds, 'second')
  }
  return formatTimeInterval(0, 'second')
}
