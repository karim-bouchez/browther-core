// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import { getLocale } from '$web-common/locale'

// ⚠️ Le gros interrupteur DES PANNEAUX, importé tel quel — pas un
// interrupteur système, pas un dessin de plus. C'est le geste que la personne
// refera dans Browther : elle l'apprend ici (ONBOARDING-SPEC.md § 3.3).
import BrowtherBigToggle from '../../../brave_shields/resources/panel/components/browther-big-toggle'

import { icons } from './assets'
import { Glyph } from './glyphs'

export type Engine = 'shields' | 'basarunaa' | 'sawtunaa'

/**
 * L'icône du moteur, celle de la barre d'outils, teintée à la couleur du
 * texte (le SVG sert de masque).
 */
export function EngineIcon (props: { engine: Engine, className?: string }) {
  const url = `url("${icons[props.engine]}")`
  return (
    <span
      className={'bi-engine-icon ' + (props.className ?? '')}
      style={{ WebkitMaskImage: url, maskImage: url }}
      aria-hidden='true'
    />
  )
}

/**
 * L'icône du moteur avec **son badge**, à la géométrie macOS
 * (`browther_status_dot_image_source.cc`) : disque de 40 % de la largeur de
 * l'icône, posé entièrement dans son coin bas-droite, cerné de blanc, sans
 * halo. ⚠️ Vert dès que c'est allumé, jamais ambre : dans l'introduction rien
 * n'est réellement allumé, l'interrupteur montre un avant/après.
 */
export function BadgedIcon (props: { engine: Engine, isOn: boolean }) {
  return (
    <span className='bi-badged-icon'>
      <EngineIcon engine={props.engine} />
      <span className={'bi-badge' + (props.isOn ? ' is-on' : '')} />
    </span>
  )
}

/**
 * La rangée de commande des démonstrations : icône + badge, nom du moteur,
 * état en UNE ligne, puis le gros interrupteur. Hauteur fixe.
 */
export function SwitchRow (props: {
  engine: Engine
  title: string
  offLabel: string
  onLabel: string
  isOn: boolean
  onToggle: () => void
}) {
  return (
    <div className='bi-switch-row'>
      <BadgedIcon engine={props.engine} isOn={props.isOn} />
      <div className='bi-switch-text'>
        <span className='bi-switch-title'>{props.title}</span>
        {/* ⚠️ Une seule ligne, quoi qu'il arrive : un libellé qui se casse en
            deux fait sauter tout le bas de l'écran à chaque bascule. */}
        <span className={'bi-switch-state' + (props.isOn ? ' is-on' : '')}>
          {props.isOn ? props.onLabel : props.offLabel}
        </span>
      </div>
      <BrowtherBigToggle
        checked={props.isOn}
        onChange={props.onToggle}
        ariaLabel={props.title}
      />
    </div>
  )
}

/**
 * Le bouton de bas d'écran, **éteint tant que l'interrupteur n'est pas sur
 * ON**. ⚠️ La mention est AU-DESSUS et sa hauteur est réservée en
 * permanence : rien ne doit bouger entre ON et OFF.
 */
export function AdvanceButton (props: {
  enabled: boolean
  onClick: () => void
}) {
  return (
    <div className='bi-advance'>
      <span className={'bi-advance-hint' + (props.enabled ? ' is-hidden' : '')}>
        {getLocale('browtherIntroTurnOnToContinue')}
      </span>
      <button
        type='button'
        className='bi-button bi-button-primary'
        disabled={!props.enabled}
        onClick={props.onClick}
      >
        {getLocale('browtherIntroContinue')}
      </button>
    </div>
  )
}

export function Pill (props: { label: string }) {
  return (
    <span className='bi-pill'>
      <Glyph name='check' />
      {props.label}
    </span>
  )
}

/**
 * Le tampon « halal » ou « haram » du site (disque à 24 pointes, deux cercles,
 * deux étoiles, le mot arabe et le mot latin — cf.
 * `website/components/sections/before-after.tsx`). ⛔ Pas de texte en arc :
 * illisible à cette taille.
 */
function Stamp (props: { kind: 'halal' | 'haram' }) {
  const spikes = 24
  const points: string[] = []
  for (let i = 0; i < spikes * 2; i++) {
    const radius = i % 2 === 0 ? 50 : 50 * 0.89
    const angle = (i * Math.PI) / spikes - Math.PI / 2
    points.push(`${50 + Math.cos(angle) * radius},${50 + Math.sin(angle) * radius}`)
  }
  const halal = props.kind === 'halal'
  return (
    <svg className={'bi-stamp bi-stamp-' + props.kind} viewBox='0 0 100 100' aria-hidden='true'>
      <polygon points={points.join(' ')} className='bi-stamp-disc' />
      <circle cx='50' cy='50' r='40.2' className='bi-stamp-ring' strokeWidth='2.6' />
      <circle cx='50' cy='50' r='33.7' className='bi-stamp-ring' strokeWidth='1.4' />
      <text x='50' y='52' className='bi-stamp-arabic' textAnchor='middle'>
        {halal ? 'حلال' : 'حرام'}
      </text>
      <text x='50' y='69' className='bi-stamp-latin' textAnchor='middle'>
        {getLocale(halal ? 'browtherIntroStampHalal' : 'browtherIntroStampHaram')}
      </text>
      <text x='22' y='29' className='bi-stamp-star' textAnchor='middle'>★</text>
      <text x='78' y='29' className='bi-stamp-star' textAnchor='middle'>★</text>
    </svg>
  )
}

/**
 * Les deux tampons superposés : le haram se décolle, le halal claque. Des
 * transitions plutôt que des images clés — on peut basculer deux fois par
 * seconde sans que le tampon reparte de zéro.
 */
export function StampPair (props: { isOn: boolean, className?: string }) {
  return (
    <div className={'bi-stamps' + (props.isOn ? ' is-on' : '') + ' ' + (props.className ?? '')}>
      <Stamp kind='haram' />
      <Stamp kind='halal' />
    </div>
  )
}

/**
 * La signature de l'éditeur, en version **muette** : la pastille bordée, mais
 * ni flèche ni geste — ouvrir devndin.com ferait sortir de l'introduction
 * (`SURFACES-COMMUNES.md` § 6). ⛔ N'émet aucun évènement.
 */
export function Signature () {
  return (
    <div className='bi-signature'>
      <span>{getLocale('browtherIntroSignatureLabel')}</span>
      <img src={icons.devndinLogo} alt='dev&din' />
    </div>
  )
}

/**
 * Le point vert ou ambre des trois protections de l'accueil. Le halo n'est
 * pas décoratif : à 7 px sur une photo, un aplat mat se perd dans le fond.
 */
export function StatusDot (props: { soon: boolean }) {
  return <span className={'bi-status-dot' + (props.soon ? ' is-soon' : '')} />
}

/**
 * Titre, sous-titre, scène, commandes : le gabarit de cinq des six écrans
 * (l'accueil a le sien, pleine image). Sur desktop, la scène passe à droite ;
 * les commandes gardent l'ordre de l'iOS, en bas de la colonne de texte.
 */
export function IntroLayout (props: {
  pill?: React.ReactNode
  title: string
  subtitle: string
  footnote?: React.ReactNode
  scene: React.ReactNode
  actions: React.ReactNode
  sceneClassName?: string
}) {
  return (
    <div className='bi-layout'>
      <div className='bi-copy'>
        <div className='bi-copy-top'>
          {props.pill}
          <h1 className='bi-title'>{props.title}</h1>
          <p className='bi-subtitle'>{props.subtitle}</p>
          {props.footnote}
        </div>
        <div className='bi-actions'>{props.actions}</div>
      </div>
      <div className={'bi-scene ' + (props.sceneClassName ?? '')}>
        {props.scene}
      </div>
    </div>
  )
}
