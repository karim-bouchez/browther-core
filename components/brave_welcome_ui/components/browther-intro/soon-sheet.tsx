// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import { getLocale } from '$web-common/locale'

import { IntroFeature } from './model'
import { EngineIcon } from './shared'

const CLOSE_DURATION = 240

/**
 * Ce que répond « Continuer » sur Basarunaa et Sawtunaa pendant l'accès
 * anticipé.
 *
 * ⚠️ Une vraie feuille : elle monte au ressort, se TIRE vers le bas pour la
 * refermer (poignée comme corps de la feuille), et le fond s'assombrit
 * progressivement. ⛔ Pas d'apparition en fondu avec une poignée décorative
 * qui ne répond pas — on promettrait un geste qui n'existe pas.
 */
export default function SoonSheet (props: {
  feature: IntroFeature
  onContinue: () => void
  onDismiss: () => void
}) {
  const [appeared, setAppeared] = React.useState(false)
  const [drag, setDrag] = React.useState<number | null>(null)
  const gesture =
    React.useRef<{ y: number, t: number, captured: boolean } | null>(null)
  const closing = React.useRef(false)

  React.useEffect(() => {
    const frame = requestAnimationFrame(() => setAppeared(true))
    return () => cancelAnimationFrame(frame)
  }, [])

  // La feuille redescend avant de rendre la main : sans ça, elle disparaît
  // d'un coup et l'écran suivant arrive par-dessus.
  const close = (then: () => void) => {
    if (closing.current) return
    closing.current = true
    setDrag(null)
    setAppeared(false)
    window.setTimeout(then, CLOSE_DURATION)
  }

  React.useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') close(props.onDismiss)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  // La capture du pointeur ne démarre qu'au premier vrai mouvement : un simple
  // clic sur la poignée doit rester un clic (et refermer), un glissé doit
  // suivre le pointeur même s'il sort de la feuille.
  const onPointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
    if ((event.target as HTMLElement).closest('button:not(.bi-sheet-handle)')) return
    gesture.current = { y: event.clientY, t: performance.now(), captured: false }
  }
  const onPointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
    const current = gesture.current
    if (!current) return
    const distance = event.clientY - current.y
    if (!current.captured && Math.abs(distance) > 3) {
      event.currentTarget.setPointerCapture(event.pointerId)
      current.captured = true
    }
    if (current.captured) setDrag(Math.max(0, distance))
  }
  const onPointerUp = (event: React.PointerEvent<HTMLDivElement>) => {
    const start = gesture.current
    gesture.current = null
    if (!start?.captured) return
    const distance = event.clientY - start.y
    const velocity = distance / Math.max(1, performance.now() - start.t)
    // Un tiers de la feuille, ou un geste franc : on referme.
    if (distance > 110 || (distance > 30 && velocity > 0.9)) {
      close(props.onDismiss)
    } else {
      setDrag(null)
    }
  }

  const isBlur = props.feature === 'basarunaa'
  const style = drag !== null
    ? { transform: `translate(-50%, ${drag}px)`, transition: 'none' }
    : undefined

  return (
    <div className={'bi-sheet-layer' + (appeared ? ' is-open' : '')}>
      <div className='bi-sheet-backdrop' onClick={() => close(props.onDismiss)} />
      <div
        className='bi-sheet'
        role='dialog'
        aria-modal='true'
        aria-labelledby='bi-sheet-title'
        style={style}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={() => { gesture.current = null; setDrag(null) }}
      >
        <button
          type='button'
          className='bi-sheet-handle'
          aria-label={getLocale('browtherIntroSoonClose')}
          onClick={() => close(props.onDismiss)}
        />
        <div className='bi-sheet-head'>
          <span className='bi-sheet-icon'>
            <EngineIcon engine={props.feature} />
          </span>
          <div>
            <div className='bi-sheet-name' id='bi-sheet-title'>
              {isBlur ? 'Basarunaa' : 'Sawtunaa'}
            </div>
            <div className='bi-sheet-soon'>{getLocale('browtherIntroSoonTitle')}</div>
          </div>
        </div>
        <p className='bi-sheet-body'>
          {getLocale(isBlur ? 'browtherIntroSoonBlurBody' : 'browtherIntroSoonMusicBody')}
        </p>
        <p className='bi-sheet-note'>{getLocale('browtherIntroSoonNote')}</p>
        <button
          type='button'
          className='bi-button bi-button-primary'
          onClick={() => close(props.onContinue)}
        >
          {getLocale('browtherIntroSoonPrimaryButton')}
        </button>
      </div>
    </div>
  )
}
