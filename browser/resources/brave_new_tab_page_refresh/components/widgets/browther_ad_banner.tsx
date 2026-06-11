/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

import * as React from 'react'

import { useNewTabState, useNewTabActions } from '../../context/new_tab_context'
import { SafeImage } from '../common/safe_image'

import { style } from './browther_ad_banner.style'

// Browther: bannière pub devndin-ads sous les favoris. Carousel ratio 3.2:1
// (cf. ads/docs/INTEGRATION.md). L'image distante passe par chrome://brave-image
// (sanitized image source, fetch côté navigateur — pas de CSP à assouplir).
// Impression trackée à visibilité réelle (≥ 50 %), une fois par pub servie.
// Click → handler ouvre l'URL de click (302 → destination) dans un nouvel onglet.
export function BrowtherAdBanner() {
  const ads = useNewTabState((s) => s.browtherAds)
  const actions = useNewTabActions()

  const containerRef = React.useRef<HTMLDivElement>(null)
  const reportedRef = React.useRef(new Set<string>())

  React.useEffect(() => {
    const root = containerRef.current
    if (!root || ads.length === 0) {
      return
    }

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) {
            continue
          }
          const id = (entry.target as HTMLElement).dataset.adId
          if (!id || reportedRef.current.has(id)) {
            continue
          }
          reportedRef.current.add(id)
          actions.markBrowtherAdVisible(id)
          observer.unobserve(entry.target)
        }
      },
      { threshold: 0.5 },
    )

    root.querySelectorAll('[data-ad-id]').forEach((el) => observer.observe(el))
    return () => observer.disconnect()
  }, [ads, actions])

  if (ads.length === 0) {
    return null
  }

  return (
    <div
      ref={containerRef}
      data-css-scope={style.scope}
    >
      <div className='carousel'>
        {ads.map((ad) => (
          <button
            key={ad.id}
            className='ad'
            data-ad-id={ad.id}
            onClick={() => actions.clickBrowtherAd(ad.id)}
          >
            <SafeImage
              src={ad.imageUrl}
              targetSize={{ width: 512, height: 160 }}
            />
          </button>
        ))}
      </div>
    </div>
  )
}
