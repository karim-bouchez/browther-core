// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import { getLocale } from '$web-common/locale'

import './browther_intro.global.css'

import { media } from './assets'
import Confetti from './confetti'
import { Glyph } from './glyphs'
import { BlurTarget, IntroModel, IntroStep, useIntroModel, useIntroSteps } from './model'
import SoonSheet from './soon-sheet'
import AdsStep from './step-ads'
import BlurStep from './step-blur'
import ChannelsStep from './step-channels'
import DefaultBrowserStep from './step-default'
import MusicStep from './step-music'
import WelcomeStep from './step-welcome'

// L'introduction Browther, portage macOS de l'iOS (référence recettée).
// 🔴 Spécification : `private/docs/ONBOARDING-SPEC.md` — chaque ⛔ des
// commentaires de ce dossier y correspond à une version codée, vue à l'écran
// et refusée.
//
// Écarts desktop assumés, listés dans la spec : la scène passe à droite du
// texte (fenêtre paysage) ; pas de retour haptique (aucune API depuis une
// page) ; QR dans les boutons des chaînes ; le son de l'ordinateur remplace
// celui de l'iPhone.

const TRANSITION_MS = 420

/**
 * Police du verset : Amiri Quran (SIL OFL 1.1), embarquée. Les polices système
 * dessinent un arabe moderne, sans les signes du muṣḥaf.
 */
let fontRequested = false
function loadVerseFont () {
  if (fontRequested) return
  fontRequested = true
  const face = new FontFace('Browther Amiri Quran', `url("${media.amiriQuranUrl}")`)
  face.load().then(loaded => document.fonts.add(loaded)).catch(() => {})
}

/**
 * ⚠️ L'introduction est TOUJOURS sombre (ONBOARDING-SPEC.md § 3.1) : la
 * séquence est composée pour le sombre — photo étoilée, voile, tampons,
 * lecteur vert profond, confettis clairs. Le thème est imposé à la PAGE
 * (`color-scheme` + `data-theme` que lisent les jetons Leo et les commandes
 * natives), jamais en forçant des couleurs une par une ; il est rendu à la
 * page quand l'introduction s'en va (écrans d'import Brave).
 */
function useForcedDarkTheme () {
  React.useEffect(() => {
    const root = document.documentElement
    const previousTheme = root.getAttribute('data-theme')
    const previousScheme = root.style.colorScheme
    root.setAttribute('data-theme', 'dark')
    root.style.colorScheme = 'dark'
    return () => {
      if (previousTheme === null) root.removeAttribute('data-theme')
      else root.setAttribute('data-theme', previousTheme)
      root.style.colorScheme = previousScheme
    }
  }, [])
}

export default function BrowtherIntro (props: {
  onFinish: (blurTarget: BlurTarget) => void
}) {
  useForcedDarkTheme()
  React.useEffect(loadVerseFont, [])
  const steps = useIntroSteps()
  // Le fond reste noir pendant les quelques millisecondes où l'on demande au
  // navigateur s'il est déjà celui par défaut.
  return (
    <div className='browther-intro'>
      {steps && <Intro steps={steps} onFinish={props.onFinish} />}
    </div>
  )
}

function Intro (props: {
  steps: IntroStep[]
  onFinish: (blurTarget: BlurTarget) => void
}) {
  const model = useIntroModel(props.steps, props.onFinish)
  const leaving = useLeavingStep(model)

  return (
    <>
      <div className='bi-stage'>
        {/* Une liste à clés stables : l'écran qui sort garde SON instance (la
            vidéo ne repart pas de zéro pendant la sortie, l'extrait se tait). */}
        {[
          ...(leaving && leaving.step !== model.step ? [leaving.step] : []),
          model.step
        ].map(step => {
          const isActive = step === model.step
          const motion = isActive
            ? (model.direction > 0 ? 'from-right' : 'from-left')
            : (leaving && leaving.direction > 0 ? 'to-left' : 'to-right')
          return (
            <div
              key={step}
              className={`bi-screen ${motion}` +
                (isActive ? '' : ' is-leaving') +
                (step === 'welcome' ? ' is-welcome' : '')}
              aria-hidden={!isActive}
            >
              {renderStep(step, model, isActive)}
            </div>
          )
        })}
      </div>
      <Header model={model} />
      {model.celebratedAt !== null && <Confetti start={model.celebratedAt} />}
      {model.soonFeature && (
        <SoonSheet
          feature={model.soonFeature}
          onContinue={() => {
            model.dismissSoonSheet()
            model.advance()
          }}
          onDismiss={model.dismissSoonSheet}
        />
      )}
    </>
  )
}

function renderStep (step: IntroStep, model: IntroModel, isActive: boolean) {
  switch (step) {
    case 'welcome': return <WelcomeStep model={model} />
    case 'ads': return <AdsStep model={model} />
    case 'blur': return <BlurStep model={model} />
    case 'music': return <MusicStep model={model} isActive={isActive} />
    case 'default': return <DefaultBrowserStep model={model} />
    case 'channels': return <ChannelsStep model={model} />
  }
}

/**
 * L'écran qui s'en va reste affiché le temps de sa sortie : le parcours a un
 * sens — l'écran suivant entre par la droite et pousse le précédent vers la
 * gauche, le retour rembobine.
 */
function useLeavingStep (model: IntroModel) {
  const [state, setState] = React.useState<{
    step: IntroStep
    leaving: { step: IntroStep, direction: 1 | -1 } | null
  }>({ step: model.step, leaving: null })
  // ⚠️ Dérivé PENDANT le rendu, pas dans un effet : un effet arriverait après
  // le rendu qui a déjà retiré l'écran sortant, et il serait remonté à neuf.
  if (state.step !== model.step) {
    setState({
      step: model.step,
      leaving: { step: state.step, direction: model.direction }
    })
  }
  React.useEffect(() => {
    if (!state.leaving) return
    const timer = window.setTimeout(
      () => setState(current => ({ ...current, leaving: null })), TRANSITION_MS)
    return () => window.clearTimeout(timer)
  }, [state.leaving])
  return state.leaving
}

function Header (props: { model: IntroModel }) {
  const { model } = props
  return (
    <div className='bi-header'>
      <button
        type='button'
        className={'bi-back' + (model.index === 0 ? ' is-hidden' : '')}
        onClick={model.back}
        disabled={model.index === 0}
        aria-label={getLocale('braveWelcomeBackButtonLabel')}
      >
        <Glyph name='chevronLeft' />
      </button>
      <div className='bi-progress' aria-hidden='true'>
        {model.steps.map((step, i) => (
          <span key={step} className={i <= model.index ? 'is-done' : ''} />
        ))}
      </div>
    </div>
  )
}
