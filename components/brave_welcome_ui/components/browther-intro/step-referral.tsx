// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import { getLocale } from '$web-common/locale'

import { IntroModel } from './model'
import { IntroLayout } from './shared'

// L'app du parrainage (`private/webui/referral/`), chargée par la page sous
// `browther-referral/app.js` — elle apporte les textes (le pool commun à
// l'iOS) et le champ du code, avec ses règles (forme du code, refus, service).
interface ReferralIntroTexts {
  title: string
  subtitle: string
}

interface ReferralIntroOptions {
  onTexts: (texts: ReferralIntroTexts) => void
  onRedeemed: () => void
}

interface ReferralApi {
  mountIntroStep: (
    element: HTMLElement,
    options: ReferralIntroOptions
  ) => { unmount: () => void }
}

declare global {
  interface Window {
    BrowtherReferral?: ReferralApi
  }
}

const READY_EVENT = 'browther-referral-ready'

/**
 * L'app du parrainage est-elle là ? Elle se charge en module, en parallèle de
 * l'introduction ; `false` si elle n'arrive pas (non déployée) — l'étape ne
 * s'affiche alors pas du tout, ⛔ plutôt qu'un écran vide.
 */
export function useReferralAppReady (enabled: boolean): boolean | undefined {
  const [ready, setReady] = React.useState<boolean | undefined>(
    enabled ? (window.BrowtherReferral ? true : undefined) : false)
  React.useEffect(() => {
    if (!enabled || ready !== undefined) return
    const onReady = () => setReady(true)
    window.addEventListener(READY_EVENT, onReady)
    const timer = window.setTimeout(
      () => setReady(Boolean(window.BrowtherReferral)), 4000)
    return () => {
      window.removeEventListener(READY_EVENT, onReady)
      window.clearTimeout(timer)
    }
  }, [enabled, ready])
  return ready
}

/**
 * « Un proche t'a parlé de Browther ? » — l'écran O du parrainage **dans une
 * introduction : le code SEUL** (`docs/PARRAINAGE.md` § 12.24) : ⛔ ni
 * l'accroche « Débloquer… », ni « Tu veux en parler autour de toi ? » — la
 * personne ne connaît pas encore Browther. Ce qui a sa place ici, c'est ce
 * qu'elle ne pourra plus faire aussi simplement plus tard : **saisir le code
 * du proche qui l'a amenée** — sur desktop, le seul chemin d'attribution.
 *
 * La grammaire des autres écrans : titre, une phrase, la scène à droite (le
 * cadeau et le champ, fournis par l'app du parrainage), « Continuer » /
 * « Plus tard ». ⭐ Une réussite se fête (confettis de l'introduction, une fois).
 */
export default function ReferralStep (props: { model: IntroModel }) {
  const { model } = props
  const host = React.useRef<HTMLDivElement>(null)
  const [texts, setTexts] = React.useState<ReferralIntroTexts | null>(null)
  const [redeemed, setRedeemed] = React.useState(false)
  const celebrate = React.useRef(model.celebrateReferralCode)
  celebrate.current = model.celebrateReferralCode

  React.useEffect(() => {
    const element = host.current
    const app = window.BrowtherReferral
    if (!element || !app) return
    const handle = app.mountIntroStep(element, {
      onTexts: setTexts,
      onRedeemed: () => {
        setRedeemed(true)
        celebrate.current()
      }
    })
    return () => handle.unmount()
  }, [])

  return (
    <IntroLayout
      title={texts?.title ?? ''}
      subtitle={texts?.subtitle ?? ''}
      sceneClassName='bi-scene-referral'
      scene={<div ref={host} className='bi-referral-host' />}
      actions={
        <>
          <button
            type='button'
            className='bi-button bi-button-primary'
            onClick={model.advance}
          >
            {getLocale('browtherIntroContinue')}
          </button>
          {!redeemed && (
            <button
              type='button'
              className='bi-button bi-button-ghost'
              onClick={model.skipReferralCode}
            >
              {getLocale('browtherIntroLaterButton')}
            </button>
          )}
        </>
      }
    />
  )
}
