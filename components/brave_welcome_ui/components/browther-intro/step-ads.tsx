// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import { getLocale } from '$web-common/locale'

import { Glyph } from './glyphs'
import { IntroModel } from './model'
import { AdvanceButton, IntroLayout, Pill, StampPair, SwitchRow } from './shared'

/**
 * Le premier des trois écrans qui **demandent un geste** : l'interrupteur doit
 * passer sur ON pour que le bouton s'allume. ⚠️ Pas de « Plus tard » : c'est le
 * seul point dur du parcours, à surveiller dans l'entonnoir.
 */
export default function AdsStep (props: { model: IntroModel }) {
  const { model } = props
  return (
    <IntroLayout
      pill={<Pill label={getLocale('browtherIntroAdsPill')} />}
      title={getLocale('browtherIntroAdsTitle')}
      subtitle={getLocale('browtherIntroAdsSubtitle')}
      sceneClassName='bi-scene-ads'
      scene={
        <div className='bi-webpage-wrap'>
          <WebPageDemo blocked={model.adsDemoOn} />
          <StampPair isOn={model.adsDemoOn} />
        </div>
      }
      actions={
        <>
          <SwitchRow
            engine='shields'
            title={getLocale('browtherIntroShieldsName')}
            offLabel={getLocale('browtherIntroAdsSwitchOff')}
            onLabel={getLocale('browtherIntroAdsSwitchOn')}
            isOn={model.adsDemoOn}
            onToggle={() => model.toggleDemo('ads')}
          />
          <AdvanceButton enabled={model.adsDemoOn} onClick={model.advance} />
        </>
      }
    />
  )
}

const AD_DURATION = 5
const VIDEO_DURATION = 4
const CYCLE = AD_DURATION + VIDEO_DURATION

/**
 * Une page de recettes quelconque, avec sa pub avant la vidéo et sa bannière.
 * Éteint : la pub tient l'écran (« Annonce · 0:15 » et « Passer dans 5 s »
 * décomptent), la vidéo démarre enfin quelques secondes, puis la pub revient.
 * Allumé : plus de pub avant la vidéo, plus de bannière, la vidéo joue.
 *
 * ⛔ Aucun nom de service réel : ce qui fait reconnaître la scène, c'est la pub
 * avant la vidéo et son « Passer dans 5 s », pas une marque (règles stores).
 */
function WebPageDemo (props: { blocked: boolean }) {
  const [now, setNow] = React.useState(() => Date.now())
  React.useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 250)
    return () => window.clearInterval(timer)
  }, [])

  const phase = (now / 1000) % CYCLE
  const adElapsed = !props.blocked && phase < AD_DURATION ? phase : null
  // La barre de la vidéo avance vraiment pendant les quatre secondes où elle
  // joue ; allumé, elle part d'un point déjà entamé et continue.
  const videoProgress = props.blocked
    ? 0.42 + ((now / 1000) % 20) / 60
    : 0.12 + Math.max(0, phase - AD_DURATION) / 30

  return (
    <div className={'bi-webpage' + (props.blocked ? ' is-blocked' : '')}>
      <div className='bi-webpage-bar'>
        <Glyph name='lock' />
        <span className='bi-webpage-site'>{getLocale('browtherIntroDemoSiteName')}</span>
        <span className='bi-webpage-blocked'>
          <Glyph name='shield' />
          {getLocale('browtherIntroDemoBlockedCount')}
        </span>
      </div>
      <div className='bi-webpage-player'>
        <div className='bi-webpage-video'>
          <span className='bi-webpage-play'><Glyph name='play' /></span>
          <div className='bi-webpage-progress'>
            <span style={{ width: `${Math.min(1, videoProgress) * 100}%` }} />
          </div>
        </div>
        <Preroll elapsed={adElapsed} />
      </div>
      <div className='bi-webpage-article'>
        <h2>{getLocale('browtherIntroDemoArticleTitle')}</h2>
        <p>{getLocale('browtherIntroDemoArticleBody')}</p>
        <div className='bi-webpage-lines'><span /><span /><span /></div>
        <div className='bi-webpage-banner'>
          <span className='bi-webpage-banner-art'><Glyph name='photo' /></span>
          <span>
            <strong>{getLocale('browtherIntroDemoAdLabel')}</strong>
            <small>{getLocale('browtherIntroDemoAdSponsored')}</small>
          </span>
        </div>
      </div>
    </div>
  )
}

/** La pub avant la vidéo. `elapsed` nul = elle n'occupe pas l'écran. */
function Preroll (props: { elapsed: number | null }) {
  const elapsed = props.elapsed ?? 0
  // Le compte à rebours descend vraiment : 0:15 → 0:10 pour l'annonce, 5 → 0
  // pour le bouton « Passer ».
  const remainingAd = Math.max(0, 15 - Math.floor(elapsed))
  const remainingSkip = Math.max(0, Math.ceil(AD_DURATION - elapsed))
  return (
    <div className={'bi-preroll' + (props.elapsed === null ? ' is-hidden' : '')}>
      <Glyph name='photo' className='bi-preroll-art' />
      <div className='bi-preroll-top'>
        <span className='bi-preroll-label'>
          {getLocale('browtherIntroDemoAdLabel')} · 0:{String(remainingAd).padStart(2, '0')}
        </span>
        <span className='bi-preroll-sound'>
          <Glyph name='musicNote' />
          {getLocale('browtherIntroDemoAdSound')}
        </span>
      </div>
      <span className='bi-preroll-skip'>
        {remainingSkip > 0
          ? getLocale('browtherIntroDemoAdSkip').replace('$1', String(remainingSkip))
          : getLocale('browtherIntroDemoAdSkipNow')}
      </span>
    </div>
  )
}
