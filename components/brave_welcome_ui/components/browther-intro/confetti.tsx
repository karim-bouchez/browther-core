// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'

// La récompense du geste : à la première mise sur ON d'un écran, une gerbe
// tombe du haut de la fenêtre et S'ÉTEINT EN CHEMIN. Patron « falling
// confetti », cinq points tous nécessaires (ONBOARDING-SPEC.md § 3.6) :
//
// 1. durée de vie propre (1,1 à 2,3 s) et retard au départ (0 à 0,7 s) ;
// 2. vitesse initiale et pesanteur propres — beaucoup s'éteignent avant le bas ;
// 3. dérive latérale oscillante — sans elle, ce sont des cailloux ;
// 4. bascule sur l'axe vertical (le rectangle s'aplatit puis se rouvre) ;
// 5. fondu à partir de mi-vie, jusqu'à zéro.
//
// ⛔ Une chute uniforme avec disparition au bord donne un champ qui glisse d'un
// bloc : c'est ce qui a été refusé.
//
// ⚠️ L'instant du tir est passé en paramètre, jamais retenu dans un cache : sur
// iOS, un cache indexé par numéro de gerbe ne montrait les confettis qu'au
// premier écran.

const COUNT = 160
const MAX_LIFETIME = 2.3
const MAX_DELAY = 0.7

/** Sauge, or, vert halal, blanc cassé, vert système — teintes sombres de l'iOS. */
const PALETTE = ['#A5B299', '#D4A857', '#2A8F5A', '#F8F3EA', '#34C759']

interface Piece {
  x: number
  width: number
  height: number
  color: string
  spin: number
  delay: number
  lifetime: number
  speed: number
  gravity: number
  swayWidth: number
  swayRate: number
  swayPhase: number
  flipRate: number
  flipPhase: number
}

/** Générateur reproductible (xorshift) : une gerbe par instant de tir. */
function seeded (seed: number) {
  let state = (seed >>> 0) || 0x9e3779b9
  return (min: number, max: number) => {
    state ^= state << 13
    state ^= state >>> 17
    state ^= state << 5
    return min + ((state >>> 0) / 0xffffffff) * (max - min)
  }
}

function makePieces (start: number): Piece[] {
  const random = seeded(start)
  return Array.from({ length: COUNT }, () => {
    const width = random(5, 10)
    return {
      x: random(-0.02, 1.02),
      width,
      height: width * random(0.45, 1.5),
      color: PALETTE[Math.floor(random(0, PALETTE.length - 0.001))],
      spin: random(-9, 9),
      delay: random(0, MAX_DELAY),
      lifetime: random(1.1, MAX_LIFETIME),
      speed: random(0.18, 0.5),
      gravity: random(0.7, 1.5),
      swayWidth: random(10, 42),
      swayRate: random(4, 10),
      swayPhase: random(0, Math.PI * 2),
      flipRate: random(6, 16),
      flipPhase: random(0, Math.PI * 2)
    }
  })
}

/** Rendue par-dessus TOUTE la fenêtre, jamais dans la vignette qui la déclenche. */
export default function Confetti (props: { start: number }) {
  const canvasRef = React.useRef<HTMLCanvasElement>(null)

  React.useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
    const context = canvas.getContext('2d')
    if (!context) return
    const pieces = makePieces(props.start)
    let frame = 0

    const render = () => {
      const ratio = window.devicePixelRatio || 1
      const width = canvas.clientWidth
      const height = canvas.clientHeight
      if (canvas.width !== Math.round(width * ratio)) canvas.width = Math.round(width * ratio)
      if (canvas.height !== Math.round(height * ratio)) canvas.height = Math.round(height * ratio)
      context.setTransform(ratio, 0, 0, ratio, 0, 0)
      context.clearRect(0, 0, width, height)

      const elapsed = (performance.timeOrigin + performance.now() - props.start) / 1000
      if (elapsed > MAX_DELAY + MAX_LIFETIME) return
      for (const piece of pieces) {
        const age = elapsed - piece.delay
        if (age <= 0) continue
        const life = age / piece.lifetime
        if (life >= 1) continue
        // Chute : vitesse initiale propre, puis pesanteur.
        const travel = piece.speed * life + 0.5 * piece.gravity * life * life
        const y = -30 + travel * height
        const x = piece.x * width +
          Math.sin(life * piece.swayRate + piece.swayPhase) * piece.swayWidth
        const fade = life < 0.45 ? 1 : Math.pow(Math.max(0, (1 - life) / 0.55), 0.85)
        if (fade <= 0.02) continue
        const flip = Math.max(0.12, Math.abs(Math.cos(life * piece.flipRate + piece.flipPhase)))
        context.save()
        context.translate(x, y)
        context.rotate(piece.spin * life)
        context.scale(flip, 1)
        context.globalAlpha = fade
        context.fillStyle = piece.color
        context.fillRect(-piece.width / 2, -piece.height / 2, piece.width, piece.height)
        context.restore()
      }
      frame = requestAnimationFrame(render)
    }
    frame = requestAnimationFrame(render)
    return () => cancelAnimationFrame(frame)
  }, [props.start])

  return <canvas ref={canvasRef} className='bi-confetti' aria-hidden='true' />
}
