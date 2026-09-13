// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import { getLocale } from '$web-common/locale'

import { icons, welcomeBackgroundUrl } from './assets'
import { IntroModel, isEarlyAccess } from './model'
import { Engine, EngineIcon, Signature, StatusDot } from './shared'

/**
 * Coran 17:36, seconde moitié, en uthmani — ⛔ jamais ressaisi à la main :
 * copie exacte de `private/design/intro-iphone/verse.txt`, la même que l'iOS.
 * En séquences `\u` : un éditeur qui normalise l'Unicode réordonne les signes
 * (šadda et voyelle échangées) — c'est arrivé à l'écriture de ce fichier.
 *
 * ⚠️ Édition `quran-uthmani-quran-academy` (api.alquran.cloud), PAS
 * `quran-uthmani` (Tanzil) : cette dernière accole un U+06ED SMALL LOW MEEM à
 * chaque tanwīn fatḥ suivi d'alif, qu'une police de muṣḥaf dessine comme un
 * vrai mīm sous la ligne.
 */
const VERSE =
  '\u0625\u0650\u0646\u0651\u064e \u0671\u0644\u0633\u0651\u064e\u0645\u06e1\u0639\u064e \u0648\u064e\u0671\u0644\u06e1\u0628\u064e\u0635\u064e\u0631\u064e ' +
  '\u0648\u064e\u0671\u0644\u06e1\u0641\u064f\u0624\u064e\u0627\u062f\u064e \u0643\u064f\u0644\u0651\u064f \u0623\u064f\u0648\u06df\u0644\u064e\u0640\u0670\u06e4\u0649\u0655\u0650\u0643\u064e ' +
  '\u0643\u064e\u0627\u0646\u064e \u0639\u064e\u0646\u06e1\u0647\u064f \u0645\u064e\u0633\u06e1\u0640\u0654\u064f\u0648\u0644\u08f0\u0627'

/**
 * L'accueil s'ouvre sur un fond du Nouvel Onglet — celui qu'on retrouve en
 * arrivant — et sur le verset qui résume les deux moteurs : l'ouïe (Sawtunaa)
 * et la vue (Basarunaa).
 */
export default function WelcomeStep (props: { model: IntroModel }) {
  const [backgroundFailed, setBackgroundFailed] = React.useState(false)
  return (
    <div className='bi-welcome'>
      {/* ⚠️ Le fond est CONTRAINT et ROGNÉ par son conteneur, jamais posé en
          frère du contenu : une image « remplir » sans taille imposée fait
          déborder tout l'écran (défaut vu sur iOS). */}
      <div className='bi-welcome-backdrop' aria-hidden='true'>
        {!backgroundFailed && (
          <img src={welcomeBackgroundUrl} alt='' onError={() => setBackgroundFailed(true)} />
        )}
        <div className='bi-welcome-shade' />
      </div>
      <div className='bi-welcome-content'>
        {/* L'icône de l'app, pas le bouclier — le bouclier est l'icône des pubs.
            Elle commence SOUS la barre de progression. */}
        <img className='bi-app-icon' src={icons.app} alt='' />
        <div className='bi-verse'>
          <p className='bi-verse-arabic' dir='rtl' lang='ar'>{VERSE}</p>
          <p className='bi-verse-translation'>{getLocale('browtherIntroVerseTranslation')}</p>
          <p className='bi-verse-reference'>{getLocale('browtherIntroVerseReference')}</p>
        </div>
        <div className='bi-welcome-spacer' />
        <h1 className='bi-welcome-title'>{getLocale('browtherIntroWelcomeTitle')}</h1>
        <div className='bi-protections'>
          <Protection engine='shields' name={getLocale('browtherIntroProtectionAds')} soon={false} />
          <div className='bi-protections-divider' />
          <Protection engine='sawtunaa' name={getLocale('browtherIntroProtectionMusic')} soon={isEarlyAccess} />
          <div className='bi-protections-divider' />
          <Protection engine='basarunaa' name={getLocale('browtherIntroProtectionImages')} soon={isEarlyAccess} />
        </div>
        <button
          type='button'
          className='bi-button bi-button-light'
          onClick={props.model.advance}
        >
          {getLocale('browtherIntroStartButton')}
        </button>
        <Signature />
      </div>
    </div>
  )
}

/** Les icônes sont celles de la barre d'outils : la personne les reverra telles quelles. */
function Protection (props: { engine: Engine, name: string, soon: boolean }) {
  return (
    <div className='bi-protection'>
      <EngineIcon engine={props.engine} />
      <span className='bi-protection-name'>{props.name}</span>
      <span className='bi-protection-status'>
        <StatusDot soon={props.soon} />
        {getLocale(props.soon ? 'browtherIntroStatusSoon' : 'browtherIntroStatusActive')}
      </span>
      {/* Seconde ligne : l'invocation pour ce qui arrive, « dès maintenant »
          pour ce qui marche déjà — même poids pour les deux, sinon la colonne
          active paraît vide à côté des autres. */}
      <span className='bi-protection-detail' lang={props.soon ? 'ar' : undefined}>
        {props.soon ? 'إن شاء الله' : getLocale('browtherIntroStatusActiveDetail')}
      </span>
    </div>
  )
}
