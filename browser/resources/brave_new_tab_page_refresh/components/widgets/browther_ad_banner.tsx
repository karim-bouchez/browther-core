/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

import * as React from 'react'

import { useNewTabState, useNewTabActions } from '../../context/new_tab_context'
import { getString } from '../../lib/strings'
import { SafeImage } from '../common/safe_image'

import { style } from './browther_ad_banner.style'

// Ratio de secours si le serve ne renvoie pas de champ `ratio` exploitable
// (vieux cache serveur). Ne pas s'en servir comme valeur nominale : l'aspect
// ratio est piloté par le champ renvoyé (INTEGRATION.md § 3).
const kFallbackAspect = 3.2

/** "3.2:1" → 3.2 (aspect-ratio numérique largeur/hauteur). */
function aspectOf(ratio: string): number {
  const [w, h] = ratio.split(':').map(Number)
  if (!w || !h || !isFinite(w) || !isFinite(h)) {
    return kFallbackAspect
  }
  return w / h
}

// Browther: bannière pub devndin-ads sous les favoris (cf.
// ads/docs/INTEGRATION.md § 3 « UX carousel — principes communs »).
// - Slides pleine largeur (pas de peek), scroll-snap.
// - Dots overlay bas-centre, cliquables, masqués si une seule pub.
// - Flèches toujours visibles sur desktop (à cheval sur les bords, style
//   chrome de l'app), masquées aux extrémités et si une seule pub. Pas
//   d'auto-défilement : emplacement éphémère (NTP), optionnel selon la doc.
// - Label par slide (onglet à cheval sur le coin haut de la créa, il glisse
//   avec sa slide) : « Pub » si `showAdLabel` (annonceur externe), sinon le
//   tag cross-promo « Découvrez aussi chez dev&din » (house ad — cf.
//   INTEGRATION.md § 3 « Label de la créa »). Toujours affiché, jamais absent.
// - Aspect-ratio piloté par le champ `ratio` renvoyé par le serve.
// L'image distante passe par chrome://brave-image (sanitized image source).
// Impression trackée à visibilité réelle (≥ 50 %), une fois par pub servie.
// Click → handler ouvre l'URL de click (302 → destination) dans un nouvel onglet.
export function BrowtherAdBanner() {
  const ads = useNewTabState((s) => s.browtherAds)
  const actions = useNewTabActions()

  const containerRef = React.useRef<HTMLDivElement>(null)
  const carouselRef = React.useRef<HTMLDivElement>(null)
  const reportedRef = React.useRef(new Set<string>())
  const [currentIndex, setCurrentIndex] = React.useState(0)

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

  // Dots + flèches synchronisés sur la position réelle du scroll (trackpad et
  // molette compris), pas seulement sur les clics.
  const onScroll = React.useCallback(() => {
    const carousel = carouselRef.current
    if (!carousel || carousel.clientWidth === 0) {
      return
    }
    const index = Math.round(carousel.scrollLeft / carousel.clientWidth)
    setCurrentIndex(Math.min(Math.max(index, 0), ads.length - 1))
  }, [ads.length])

  const scrollToIndex = (index: number) => {
    const carousel = carouselRef.current
    if (!carousel) {
      return
    }
    carousel.scrollTo({
      left: index * carousel.clientWidth,
      behavior: 'smooth',
    })
  }

  if (ads.length === 0) {
    return null
  }

  return (
    <div
      ref={containerRef}
      data-css-scope={style.scope}
    >
      <div className='carousel-wrapper'>
        <div
          className='carousel'
          ref={carouselRef}
          onScroll={onScroll}
        >
          {ads.map((ad) => (
            <button
              key={ad.id}
              className='ad'
              data-ad-id={ad.id}
              // Sens de lecture + a11y pilotés par la langue de la créa
              // renvoyée par le serve : `ar` → dir="rtl" (le label logique
              // `inset-inline-start` glisse alors au coin haut-droit). On ne
              // met dir QUE sur la slide, pas sur `.carousel` : son scroll doit
              // rester LTR (la logique dots/flèches lit scrollLeft). `lang`
              // absent si créa neutre (aucun attribut).
              dir={ad.locale === 'ar' ? 'rtl' : undefined}
              lang={ad.locale || undefined}
              style={{ aspectRatio: String(aspectOf(ad.ratio)) }}
              onClick={() => actions.clickBrowtherAd(ad.id)}
            >
              <span className={ad.showAdLabel ? 'ad-label' : 'ad-label house'}>
                {getString(
                  ad.showAdLabel
                    ? S.NEW_TAB_BROWTHER_AD_LABEL
                    : S.NEW_TAB_BROWTHER_AD_HOUSE_LABEL,
                )}
              </span>
              <SafeImage
                src={ad.imageUrl}
                targetSize={{ width: 512, height: 160 }}
              />
            </button>
          ))}
        </div>
        {ads.length > 1 && currentIndex > 0 && (
          <button
            className='arrow arrow-prev'
            onClick={() => scrollToIndex(currentIndex - 1)}
          >
            <svg viewBox='0 0 16 16' aria-hidden='true'>
              <path
                d='M10 3 5 8l5 5'
                fill='none'
                stroke='currentColor'
                strokeWidth='2'
                strokeLinecap='round'
                strokeLinejoin='round'
              />
            </svg>
          </button>
        )}
        {ads.length > 1 && currentIndex < ads.length - 1 && (
          <button
            className='arrow arrow-next'
            onClick={() => scrollToIndex(currentIndex + 1)}
          >
            <svg viewBox='0 0 16 16' aria-hidden='true'>
              <path
                d='M6 3l5 5-5 5'
                fill='none'
                stroke='currentColor'
                strokeWidth='2'
                strokeLinecap='round'
                strokeLinejoin='round'
              />
            </svg>
          </button>
        )}
        {ads.length > 1 && (
          <div className='dots'>
            {ads.map((ad, i) => (
              <button
                key={ad.id}
                className={i === currentIndex ? 'dot active' : 'dot'}
                onClick={() => scrollToIndex(i)}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
