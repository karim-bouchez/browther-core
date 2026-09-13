// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import { getLocale } from '$web-common/locale'

import './browther_intro.global.css'

import { media, welcomeBackgroundUrl } from './assets'
import Confetti from './confetti'
import { Glyph } from './glyphs'
import DataContext from '../../state/context'
import { SourceProfile } from './import'
import { BlurTarget, IntroModel, IntroStep, useIntroModel, useIntroSteps } from './model'
import SoonDialog from './soon-dialog'
import AdsStep from './step-ads'
import BlurStep from './step-blur'
import ChannelsStep from './step-channels'
import DefaultBrowserStep from './step-default'
import ImportStep from './step-import'
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
  // Les navigateurs installés : lus par le parcours Brave au chargement de la
  // page (`initializeImportDialog`).
  const importSources: SourceProfile[] | undefined =
    React.useContext(DataContext).browserProfiles
  const steps = useIntroSteps(importSources)
  // Le fond reste noir pendant les quelques millisecondes où l'on demande au
  // navigateur s'il est déjà celui par défaut et quels navigateurs sont là.
  return (
    <div className='browther-intro'>
      {steps && (
        <Intro
          steps={steps}
          importSources={importSources}
          onFinish={props.onFinish}
        />
      )}
    </div>
  )
}

function Intro (props: {
  steps: IntroStep[]
  importSources: SourceProfile[] | undefined
  onFinish: (blurTarget: BlurTarget) => void
}) {
  const model = useIntroModel(props.steps, props.onFinish, props.importSources)
  const leaving = useLeavingStep(model)

  return (
    <>
      <div className='bi-stage'>
        <Backdrop step={model.index} />
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
        <SoonDialog
          feature={model.soonFeature}
          onContinue={() => {
            model.dismissSoonDialog()
            model.advance()
          }}
          onDismiss={model.dismissSoonDialog}
        />
      )}
    </>
  )
}

/**
 * « Nuit étoilée » (Karim, 2026-09-13) : la photo de l'accueil continue
 * derrière les écrans suivants, floutée et noyée dans le noir — sur un
 * écran de bureau, un fond noir uni laissait trop de vide.
 *
 * Deux mouvements, lents : une dérive continue (le ciel respire), et un
 * travelling qui avance d'un cran à chaque écran — le décor suit le parcours,
 * comme le demandait déjà la recette de l'ancienne étape « chaînes »
 * (2026-08-07). L'accueil la couvre de sa propre photo, nette.
 */
function Backdrop (props: { step: number }) {
  const [failed, setFailed] = React.useState(false)
  return (
    <div className='bi-backdrop' aria-hidden='true'>
      {!failed && (
        <div className='bi-backdrop-drift'>
          <img
            className='bi-backdrop-image'
            src={welcomeBackgroundUrl}
            alt=''
            style={{ '--bi-step': props.step } as React.CSSProperties}
            onError={() => setFailed(true)}
          />
        </div>
      )}
      <div className='bi-backdrop-shade' />
    </div>
  )
}

function renderStep (step: IntroStep, model: IntroModel, isActive: boolean) {
  switch (step) {
    case 'welcome': return <WelcomeStep model={model} />
    case 'ads': return <AdsStep model={model} />
    case 'blur': return <BlurStep model={model} />
    case 'music': return <MusicStep model={model} isActive={isActive} />
    case 'default': return <DefaultBrowserStep model={model} />
    case 'import': return <ImportStep model={model} />
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
