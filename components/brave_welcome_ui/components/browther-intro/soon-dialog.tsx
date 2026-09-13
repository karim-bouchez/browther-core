// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import { getLocale } from '$web-common/locale'

import { Glyph } from './glyphs'
import { IntroFeature } from './model'
import { EngineIcon } from './shared'

const CLOSE_DURATION = 200

/**
 * Ce que répond « Continuer » sur Basarunaa et Sawtunaa pendant l'accès
 * anticipé.
 *
 * Desktop (Karim, 2026-09-13) : une MODALE CENTRÉE, pas la feuille de l'iOS —
 * tirer une feuille à la souris est un geste de téléphone. Elle garde ce que
 * la spec exige de la feuille : elle monte (ressort léger), le fond s'assombrit
 * progressivement, liseré ambre, icône du moteur en tête, et elle se ferme par
 * de vrais gestes du bureau : la croix, Échap, un clic à côté.
 *
 * `<dialog>` natif : piège du focus, Échap et couche supérieure fournis par le
 * navigateur.
 */
export default function SoonDialog (props: {
  feature: IntroFeature
  onContinue: () => void
  onDismiss: () => void
}) {
  const ref = React.useRef<HTMLDialogElement>(null)
  const [open, setOpen] = React.useState(false)
  const closing = React.useRef(false)

  React.useEffect(() => {
    const dialog = ref.current
    if (!dialog) return
    dialog.showModal()
    const frame = requestAnimationFrame(() => setOpen(true))
    return () => cancelAnimationFrame(frame)
  }, [])

  // La modale redescend avant de rendre la main : sans ça, elle disparaît
  // d'un coup et l'écran suivant arrive par-dessus.
  const close = (then: () => void) => {
    if (closing.current) return
    closing.current = true
    setOpen(false)
    window.setTimeout(() => {
      ref.current?.close()
      then()
    }, CLOSE_DURATION)
  }

  const isBlur = props.feature === 'basarunaa'
  return (
    <dialog
      ref={ref}
      className={'bi-dialog' + (open ? ' is-open' : '')}
      aria-labelledby='bi-dialog-title'
      onCancel={event => {
        event.preventDefault()
        close(props.onDismiss)
      }}
      onClick={event => {
        // Un clic sur le fond assombri arrive sur le <dialog> lui-même.
        if (event.target === event.currentTarget) close(props.onDismiss)
      }}
    >
      <div className='bi-dialog-card'>
        <button
          type='button'
          className='bi-dialog-close'
          aria-label={getLocale('browtherIntroSoonClose')}
          onClick={() => close(props.onDismiss)}
        >
          <Glyph name='xmark' />
        </button>
        <div className='bi-dialog-head'>
          <span className='bi-dialog-icon'>
            <EngineIcon engine={props.feature} />
          </span>
          <div>
            <div className='bi-dialog-name' id='bi-dialog-title'>
              {isBlur ? 'Basarunaa' : 'Sawtunaa'}
            </div>
            <div className='bi-dialog-soon'>{getLocale('browtherIntroSoonTitle')}</div>
          </div>
        </div>
        <p className='bi-dialog-body'>
          {getLocale(isBlur ? 'browtherIntroSoonBlurBody' : 'browtherIntroSoonMusicBody')}
        </p>
        <p className='bi-dialog-note'>{getLocale('browtherIntroSoonNote')}</p>
        <button
          type='button'
          className='bi-button bi-button-primary'
          autoFocus
          onClick={() => close(props.onContinue)}
        >
          {getLocale('browtherIntroSoonPrimaryButton')}
        </button>
      </div>
    </dialog>
  )
}
