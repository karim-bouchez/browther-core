// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import { sendWithPromise } from 'chrome://resources/js/cr.js'
import { loadTimeData } from '$web-common/loadTimeData'

import {
  DefaultBrowserBrowserProxyImpl,
  WelcomeBrowserProxyImpl
} from '../../api/welcome_browser_proxy'

// Portage desktop de `BrowtherIntroModel.swift` (iOS, référence recettée).
// La spécification fait foi : `private/docs/ONBOARDING-SPEC.md`.

/**
 * Les écrans, dans l'ordre du parcours.
 *
 * ⚠️ Les valeurs partent à l'analytique : ce sont des clés de série, jamais
 * des textes affichés. Les renommer casse l'entonnoir du dashboard.
 */
export type IntroStep =
  | 'welcome'
  | 'ads'
  | 'blur'
  | 'music'
  | 'default'
  | 'channels'

export type IntroFeature = 'basarunaa' | 'sawtunaa'

/** Les valeurs de `brave.basarunaa.mode` : l'écran écrit le réglage du moteur. */
export type BlurTarget = 'blur-female' | 'blur-male' | 'blur-all'

export type Channel = 'whatsapp' | 'telegram'

/**
 * Mêmes URL que le bandeau du Nouvel Onglet et les panneaux —
 * `grep 0029Vb8ydkv5vKABH78PVX32`.
 */
export const CHANNEL_URLS: Record<Channel, string> = {
  whatsapp: 'https://whatsapp.com/channel/0029Vb8ydkv5vKABH78PVX32',
  telegram: 'https://t.me/devndin_nouveautes'
}

const CHANNEL_EVENTS: Record<Channel, string> = {
  whatsapp: 'marketing_whatsapp_channel_clicked',
  telegram: 'marketing_telegram_channel_clicked'
}

/**
 * Reprend l'interrupteur unique `kBrowtherEarlyAccess`
 * (`brave/components/constants/browther_early_access.h`). Faux = les moteurs
 * s'allument pour de bon depuis l'introduction.
 */
export const isEarlyAccess = loadTimeData.getBoolean('browtherEarlyAccess')

export function track (event: string, properties: Record<string, unknown>) {
  WelcomeBrowserProxyImpl.getInstance().trackOnboardingEvent(event, properties)
}

export interface IntroModel {
  steps: IntroStep[]
  index: number
  step: IntroStep
  adsDemoOn: boolean
  blurDemoOn: boolean
  /**
   * Vrai dès que le floutage a été allumé une fois. Il change ce que montre
   * l'état « éteint » : **rideau** tant qu'on n'a rien vu, **médias d'origine**
   * ensuite — la personne a vu le résultat et demande à comparer.
   */
  blurDemoEverOn: boolean
  musicDemoOn: boolean
  blurTarget: BlurTarget
  /** Non nul quand la modale « Ça arrive bientôt » est ouverte. */
  soonFeature: IntroFeature | null
  /** Instant du dernier tir de confettis (rendus par-dessus tout l'écran). */
  celebratedAt: number | null
  /** Sens de la dernière navigation, pour la transition latérale. */
  direction: 1 | -1
  advance: () => void
  back: () => void
  toggleDemo: (step: 'ads' | 'blur' | 'music') => void
  choose: (target: BlurTarget) => void
  activate: (feature: IntroFeature) => void
  dismissSoonDialog: () => void
  setAsDefaultBrowser: () => void
  later: () => void
  openChannel: (channel: Channel) => void
  finish: () => void
}

/**
 * L'état du parcours. Une seule source de vérité pour les six écrans : c'est
 * lui qui décide ce que fait « Continuer » selon l'accès anticipé, qui écrit
 * les préférences, et qui émet l'analytique.
 */
export function useIntroModel (
  steps: IntroStep[],
  onFinish: (blurTarget: BlurTarget) => void
): IntroModel {
  const [index, setIndex] = React.useState(0)
  const [direction, setDirection] = React.useState<1 | -1>(1)
  const [adsDemoOn, setAdsDemoOn] = React.useState(false)
  const [blurDemoOn, setBlurDemoOn] = React.useState(false)
  const [blurDemoEverOn, setBlurDemoEverOn] = React.useState(false)
  const [musicDemoOn, setMusicDemoOn] = React.useState(false)
  // Le floutage part sur « les femmes » : le cas d'usage majoritaire, et le
  // défaut du moteur — l'introduction n'invente pas un réglage que l'app n'a
  // pas.
  const [blurTarget, setBlurTarget] = React.useState<BlurTarget>('blur-female')
  const [soonFeature, setSoonFeature] = React.useState<IntroFeature | null>(null)
  const [celebratedAt, setCelebratedAt] = React.useState<number | null>(null)
  // Une seule gerbe par écran : sinon l'effet devient une récompense qu'on
  // farme.
  const celebrated = React.useRef(new Set<IntroStep>())

  const step = steps[index]

  React.useEffect(() => {
    track('onboarding_step_viewed', {
      step,
      index,
      early_access: isEarlyAccess
    })
  }, [index])

  const advance = React.useCallback(() => {
    setDirection(1)
    setIndex(i => Math.min(i + 1, steps.length - 1))
  }, [steps.length])

  const back = React.useCallback(() => {
    setDirection(-1)
    setIndex(i => Math.max(0, i - 1))
  }, [])

  const toggleDemo = (demo: 'ads' | 'blur' | 'music') => {
    let on = false
    if (demo === 'ads') {
      on = !adsDemoOn
      setAdsDemoOn(on)
    } else if (demo === 'blur') {
      on = !blurDemoOn
      setBlurDemoOn(on)
      if (on) setBlurDemoEverOn(true)
    } else {
      on = !musicDemoOn
      setMusicDemoOn(on)
    }
    track('onboarding_demo_toggled', { step: demo, on })
    if (on && !celebrated.current.has(demo)) {
      celebrated.current.add(demo)
      setCelebratedAt(Date.now())
    }
  }

  const choose = (target: BlurTarget) => {
    if (target === blurTarget) return
    setBlurTarget(target)
    // Écrit tout de suite, même si le floutage est encore désactivé : la
    // personne retrouvera son choix le jour où il s'allume.
    chrome.send('setBasarunaaMode', [target])
    track('onboarding_blur_target_chosen', { value: target })
  }

  /**
   * Pendant l'accès anticipé, « Continuer » explique que la fonctionnalité
   * arrive ; à la sortie, il l'allume vraiment, puis avance. Le même bouton,
   * deux réponses — c'est le seul écart entre les deux états de l'introduction.
   */
  const activate = (feature: IntroFeature) => {
    track('onboarding_activate_tapped', {
      feature,
      available: !isEarlyAccess
    })
    // ⚠️ Le choix « qui flouter » est écrit MÊME en accès anticipé, et même si
    // la personne n'a touché à aucune case : sinon le choix affiché ne serait
    // pas celui qui s'applique.
    if (feature === 'basarunaa') {
      chrome.send('setBasarunaaMode', [blurTarget])
    }
    if (isEarlyAccess) {
      setSoonFeature(feature)
      return
    }
    chrome.send('enableBrowtherFeature', [feature])
    track('feature_toggled', {
      feature,
      enabled: true,
      source: 'onboarding'
    })
    advance()
  }

  const setAsDefaultBrowser = () => {
    DefaultBrowserBrowserProxyImpl.getInstance().setAsDefaultBrowser()
    track('default_browser_set', { source: 'onboarding' })
    advance()
  }

  const later = () => {
    track('onboarding_later_tapped', { feature: 'default_browser' })
    advance()
  }

  const openChannel = (channel: Channel) => {
    track(CHANNEL_EVENTS[channel], { source: 'onboarding' })
    window.open(CHANNEL_URLS[channel], '_blank', 'noopener')
  }

  const finish = () => {
    track('onboarding_completed', {
      blur_target: blurTarget,
      early_access: isEarlyAccess
    })
    onFinish(blurTarget)
  }

  return {
    steps,
    index,
    step,
    adsDemoOn,
    blurDemoOn,
    blurDemoEverOn,
    musicDemoOn,
    blurTarget,
    soonFeature,
    celebratedAt,
    direction,
    advance,
    back,
    toggleDemo,
    choose,
    activate,
    dismissSoonDialog: () => setSoonFeature(null),
    setAsDefaultBrowser,
    later,
    openChannel,
    finish
  }
}

/**
 * Les écrans réellement présentés. `default` saute si Browther est déjà le
 * navigateur par défaut — ou s'il ne peut pas l'être (règle d'entreprise) :
 * inutile de proposer ce qui est fait ou impossible.
 */
export function useIntroSteps (): IntroStep[] | undefined {
  const [steps, setSteps] = React.useState<IntroStep[]>()
  React.useEffect(() => {
    const withDefault: IntroStep[] =
      ['welcome', 'ads', 'blur', 'music', 'default', 'channels']
    const withoutDefault = withDefault.filter(s => s !== 'default')
    let settled = false
    const settle = (value: IntroStep[]) => {
      if (settled) return
      settled = true
      setSteps(value)
    }
    DefaultBrowserBrowserProxyImpl.getInstance()
      .requestDefaultBrowserState()
      .then(info => {
        const skip = info.isDefault || !info.canBeDefault ||
          info.isDisabledByPolicy
        settle(skip ? withoutDefault : withDefault)
      })
      .catch(() => settle(withDefault))
    // Le navigateur répond en quelques millisecondes ; s'il ne répond pas, on
    // n'attend pas plus pour montrer l'accueil.
    const timer = window.setTimeout(() => settle(withDefault), 1500)
    // Sentry : cf. `WelcomeDOMHandler::HandleBrowtherIntroStarted`.
    chrome.send('browtherIntroStarted')
    return () => window.clearTimeout(timer)
  }, [])
  return steps
}

export interface SystemVolume {
  available: boolean
  level?: number
  muted?: boolean
}

export function getSystemVolume (): Promise<SystemVolume> {
  return sendWithPromise('getSystemVolume')
}

export function setSystemVolume (level: number) {
  chrome.send('setSystemVolume', [level])
}
