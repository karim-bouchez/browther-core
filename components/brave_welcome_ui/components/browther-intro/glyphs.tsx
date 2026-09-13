// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'

// Les pictogrammes système de l'introduction — l'équivalent desktop des SF
// Symbols de l'iOS (`chevron.left`, `lock.fill`, `figure.stand.dress`…).
// Dessinés en ligne plutôt que chargés : ils doivent s'afficher dès la
// première image, sans aller-retour réseau.
//
// ⛔ Les icônes des MOTEURS (bouclier, Basarunaa, Sawtunaa) ne sont pas ici :
// ce sont celles de la barre d'outils, cf. `EngineIcon`.

const stroke = {
  fill: 'none',
  stroke: 'currentColor',
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const
}

const GLYPHS = {
  chevronLeft: <path d='M15 5l-7 7 7 7' {...stroke} strokeWidth={2.4} />,
  chevronRight: <path d='M9 5l7 7-7 7' {...stroke} strokeWidth={2.4} />,
  check: <path d='M5 12.5l4.5 4.5L19 7.5' {...stroke} strokeWidth={2.8} />,
  xmark: <path d='M6.5 6.5l11 11M17.5 6.5l-11 11' {...stroke} strokeWidth={2.6} />,
  lock: (
    <>
      <rect x='5' y='10.5' width='14' height='10' rx='2.2' fill='currentColor' />
      <path d='M8 10.5V8a4 4 0 018 0v2.5' {...stroke} strokeWidth={2.2} />
    </>
  ),
  play: (
    <path
      d='M8 5.2v13.6a1 1 0 001.5.86l11-6.8a1 1 0 000-1.72l-11-6.8A1 1 0 008 5.2z'
      fill='currentColor'
    />
  ),
  pause: (
    <>
      <rect x='6' y='4.5' width='4.5' height='15' rx='1.3' fill='currentColor' />
      <rect x='13.5' y='4.5' width='4.5' height='15' rx='1.3' fill='currentColor' />
    </>
  ),
  photo: (
    <>
      <rect x='3' y='5' width='18' height='14' rx='2.5' {...stroke} strokeWidth={2} />
      <circle cx='8.5' cy='10' r='1.8' fill='currentColor' />
      <path d='M4 18l5.5-5.5 3.5 3.5 2.5-2.5L20 18' {...stroke} strokeWidth={2} />
    </>
  ),
  musicNote: (
    <>
      <path d='M9 17.5V6.2l10-2.2v11.3' {...stroke} strokeWidth={2} />
      <circle cx='6.5' cy='17.5' r='2.6' fill='currentColor' />
      <circle cx='16.5' cy='15.3' r='2.6' fill='currentColor' />
    </>
  ),
  shield: (
    <path
      d='M12 2.5l8 3v6.2c0 4.9-3.4 8.6-8 9.8-4.6-1.2-8-4.9-8-9.8V5.5z'
      fill='currentColor'
    />
  ),
  speaker: (
    <>
      <path d='M4 9.5h3.5L12 5.5v13l-4.5-4H4z' fill='currentColor' />
      <path d='M15.5 9a4.2 4.2 0 010 6M18.2 6.5a8 8 0 010 11' {...stroke} strokeWidth={2} />
    </>
  ),
  speakerSlash: (
    <>
      <path d='M4 9.5h3.5L12 5.5v13l-4.5-4H4z' fill='currentColor' />
      <path d='M15.5 9.5l5 5M20.5 9.5l-5 5' {...stroke} strokeWidth={2.2} />
    </>
  ),
  video: (
    <>
      <rect x='3' y='6.5' width='12.5' height='11' rx='2.5' fill='currentColor' />
      <path d='M16.5 10.5l4.5-2.8v8.6l-4.5-2.8z' fill='currentColor' />
    </>
  ),
  phone: (
    <path
      d='M6.6 3.5h2.6l1.4 4.1-1.9 1.4a11.5 11.5 0 006.3 6.3l1.4-1.9 4.1 1.4v2.6a2 2 0 01-2.2 2A16.6 16.6 0 014.6 5.7a2 2 0 012-2.2z'
      fill='currentColor'
    />
  ),
  people: (
    <>
      <circle cx='9' cy='8' r='3.2' fill='currentColor' />
      <path d='M2.8 19.5c.4-3.6 2.9-5.8 6.2-5.8s5.8 2.2 6.2 5.8z' fill='currentColor' />
      <circle cx='16.6' cy='8.6' r='2.6' fill='currentColor' opacity='.75' />
      <path d='M16.3 13.6c2.7.1 4.6 2 4.9 5.2h-4.1c-.2-2-1-3.8-2.4-4.8.5-.3 1-.4 1.6-.4z' fill='currentColor' opacity='.75' />
    </>
  ),
  // `figure.stand.dress`, `figure.stand`, `figure.2` : le sujet se lit avant
  // le mot, comme sur l'iOS.
  woman: (
    <>
      <circle cx='12' cy='4.3' r='2.3' fill='currentColor' />
      <path d='M9.7 7.6h4.6c.6 0 1.1.4 1.3.9l2.6 7.6h-3v5.6h-2v-5.6h-.4v5.6h-2v-5.6h-3l2.6-7.6c.2-.5.7-.9 1.3-.9z' fill='currentColor' />
    </>
  ),
  man: (
    <>
      <circle cx='12' cy='4.3' r='2.3' fill='currentColor' />
      <path d='M9.4 7.6h5.2c.9 0 1.6.7 1.6 1.6v6.2h-2v6.2h-1.9v-5.5h-.6v5.5H9.8v-6.2h-2V9.2c0-.9.7-1.6 1.6-1.6z' fill='currentColor' />
    </>
  ),
  twoPeople: (
    <>
      <g transform='translate(-4.2 1.2) scale(.9)'>
        <circle cx='12' cy='4.3' r='2.3' fill='currentColor' />
        <path d='M9.4 7.6h5.2c.9 0 1.6.7 1.6 1.6v6.2h-2v6.2h-1.9v-5.5h-.6v5.5H9.8v-6.2h-2V9.2c0-.9.7-1.6 1.6-1.6z' fill='currentColor' />
      </g>
      <g transform='translate(6.6 1.2) scale(.9)'>
        <circle cx='12' cy='4.3' r='2.3' fill='currentColor' />
        <path d='M9.7 7.6h4.6c.6 0 1.1.4 1.3.9l2.6 7.6h-3v5.6h-2v-5.6h-.4v5.6h-2v-5.6h-3l2.6-7.6c.2-.5.7-.9 1.3-.9z' fill='currentColor' />
      </g>
    </>
  )
}

export type GlyphName = keyof typeof GLYPHS

export function Glyph (props: { name: GlyphName, className?: string }) {
  return (
    <svg
      className={'bi-glyph ' + (props.className ?? '')}
      viewBox='0 0 24 24'
      aria-hidden='true'
    >
      {GLYPHS[props.name]}
    </svg>
  )
}
