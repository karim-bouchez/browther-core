// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import { getLocale } from '$web-common/locale'

import { Glyph, GlyphName } from './glyphs'
import { PhotoTile, VideoTile } from './media-tiles'
import { BlurTarget, IntroModel } from './model'
import { AdvanceButton, EngineIcon, IntroLayout, SwitchRow } from './shared'
import { VeilMode } from './veil'

const CHOICES: Array<{
  target: BlurTarget
  label: string
  glyph: GlyphName
  tone: string
}> = [
  { target: 'blur-female', label: 'browtherIntroBlurWomen', glyph: 'woman', tone: 'feminine' },
  { target: 'blur-male', label: 'browtherIntroBlurMen', glyph: 'man', tone: 'masculine' },
  { target: 'blur-all', label: 'browtherIntroBlurBoth', glyph: 'twoPeople', tone: 'sage' }
]

/**
 * Une vidéo ET une photo : elles ne prouvent pas la même chose. La photo montre
 * que le voile est propre, la vidéo qu'il suit.
 *
 * Trois états, pas deux :
 * - éteint, jamais allumé → rideau, les deux vignettes entièrement couvertes ;
 * - allumé → le voile ciblé ;
 * - éteint après avoir été allumé → les médias d'origine (la personne compare).
 */
export default function BlurStep (props: { model: IntroModel }) {
  const { model } = props
  const mode: VeilMode = model.blurDemoOn
    ? { kind: 'target', target: model.blurTarget }
    : (model.blurDemoEverOn ? { kind: 'nothing' } : { kind: 'everything' })
  const curtain = !model.blurDemoOn && !model.blurDemoEverOn

  return (
    <IntroLayout
      title={getLocale('browtherIntroBlurTitle')}
      subtitle={getLocale('browtherIntroBlurSubtitle')}
      sceneClassName='bi-scene-blur'
      scene={
        <div className='bi-tiles'>
          <VideoTile mode={mode} />
          <PhotoTile mode={mode} />
          <div className={'bi-curtain' + (curtain ? '' : ' is-hidden')}>
            <EngineIcon engine='basarunaa' />
            {getLocale('browtherIntroBlurCurtain')}
          </div>
        </div>
      }
      actions={
        <>
          {/* Ordre du bas : choix → interrupteur → bouton. */}
          <div className='bi-choices' role='radiogroup'>
            {CHOICES.map(choice => {
              const selected = model.blurTarget === choice.target
              return (
                <button
                  key={choice.target}
                  type='button'
                  role='radio'
                  aria-checked={selected}
                  // Chaque cible a SA teinte — rose, bleu, sauge — pour que le
                  // choix se lise avant d'être lu. ⛔ Pas un cadre vert de plus.
                  className={`bi-choice bi-tone-${choice.tone}` + (selected ? ' is-selected' : '')}
                  onClick={() => model.choose(choice.target)}
                >
                  <Glyph name={choice.glyph} className='bi-choice-glyph' />
                  <span>{getLocale(choice.label)}</span>
                  <span className='bi-choice-check'><Glyph name='check' /></span>
                </button>
              )
            })}
          </div>
          <SwitchRow
            engine='basarunaa'
            title='Basarunaa'
            offLabel={getLocale('browtherIntroBlurSwitchOff')}
            onLabel={getLocale('browtherIntroBlurSwitchOn')}
            isOn={model.blurDemoOn}
            onToggle={() => model.toggleDemo('blur')}
          />
          {/* ⛔ Pas de « Plus tard » ici : il mangeait la place des vignettes. */}
          <AdvanceButton
            enabled={model.blurDemoOn}
            onClick={() => model.activate('basarunaa')}
          />
        </>
      }
    />
  )
}
