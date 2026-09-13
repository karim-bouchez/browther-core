// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import { BlurTarget } from './model'
import { VeilPerson, media } from './assets'

// Le voile de Basarunaa, TEL QUE LE MOTEUR LE REND —
// `private/extensions/basarunaa/src/core/blur-compositor.ts` :
//
// 1. flou gaussien sur TOUTE l'image, rayon `max(25, 4 % du plus grand côté)`
//    en pixels du média, bords étirés pour que le flou reste plein au bord ;
// 2. masque qui épouse le corps (polygone pré-calculé, déjà dilaté), adouci de
//    10 px du média ;
// 3. l'image nette dessous, la floutée au travers du masque.
//
// ⛔ Jamais un matériau translucide (`backdrop-filter`, verre dépoli) : ce
// n'est pas un flou, c'est une matière claire qui rend un voile laiteux
// uniforme. C'est l'erreur refusée sur iOS.
//
// Floutage pré-calculé : faire tourner le modèle pendant l'écran coûterait un
// chargement, un délai variable et un rendu qui dépend de la machine, pour une
// scène connue d'avance. Seul le voile est posé ici — le choix « femmes /
// hommes / les deux » reste donc vivant à l'écran.

export type VeilMode =
  /**
   * Rideau : l'état initial, avant que la personne ait rien vu. ⛔ On ne montre
   * pas en clair ce que l'app existe pour cacher, à quelqu'un qui n'a rien
   * demandé.
   */
  | { kind: 'everything' }
  /** Rien de couvert : l'« avant » assumé, une fois le floutage allumé puis éteint. */
  | { kind: 'nothing' }
  | { kind: 'target', target: BlurTarget }

export function sameMode (a: VeilMode, b: VeilMode) {
  return a.kind === b.kind &&
    (a.kind !== 'target' || b.kind !== 'target' || a.target === b.target)
}

/**
 * Faut-il flouter cette personne pour ce choix ? Même règle que le moteur
 * (`src/core/policy.ts`) : la cible choisie, **plus tout ce dont le genre
 * n'est pas sûr**. Dans le doute, on floute.
 */
export function isBlurred (person: VeilPerson, target: BlurTarget) {
  if (target === 'blur-all') return true
  if (target === 'blur-female' && person.gender === 'female') return true
  if (target === 'blur-male' && person.gender === 'male') return true
  return person.confidence < 0.70
}

/** `blurRadiusForImage` du compositeur. */
export function blurRadius (width: number, height: number) {
  return Math.max(25, Math.round(Math.max(width, height) * 0.04))
}

function context (canvas: HTMLCanvasElement) {
  return canvas.getContext('2d') as CanvasRenderingContext2D
}

function sized (canvas: HTMLCanvasElement, width: number, height: number) {
  if (canvas.width !== width) canvas.width = width
  if (canvas.height !== height) canvas.height = height
  return canvas
}

/**
 * Les toiles de travail d'une vignette : les recréer à chaque image de la
 * vidéo coûterait une allocation GPU par image.
 */
export class VeilScratch {
  readonly padded = document.createElement('canvas')
  readonly paddedBlur = document.createElement('canvas')
  readonly blurred = document.createElement('canvas')
  readonly mask = document.createElement('canvas')
  readonly veil = document.createElement('canvas')
}

/** `createEdgeClampedBlur` du compositeur : les bords étirés, puis le flou. */
function edgeClampedBlur (
  source: CanvasImageSource,
  width: number,
  height: number,
  scratch: VeilScratch
) {
  const radius = blurRadius(width, height)
  const pad = radius * 3
  const padded = sized(scratch.padded, width + 2 * pad, height + 2 * pad)
  const p = context(padded)
  p.filter = 'none'
  p.drawImage(source, 0, 0, width, 1, pad, 0, width, pad)
  p.drawImage(source, 0, height - 1, width, 1, pad, pad + height, width, pad)
  p.drawImage(source, 0, 0, 1, height, 0, pad, pad, height)
  p.drawImage(source, width - 1, 0, 1, height, pad + width, pad, pad, height)
  p.drawImage(source, 0, 0, 1, 1, 0, 0, pad, pad)
  p.drawImage(source, width - 1, 0, 1, 1, pad + width, 0, pad, pad)
  p.drawImage(source, 0, height - 1, 1, 1, 0, pad + height, pad, pad)
  p.drawImage(source, width - 1, height - 1, 1, 1, pad + width, pad + height, pad, pad)
  p.drawImage(source, pad, pad, width, height)

  // Le flou est calculé sur TOUTE la toile rembourrée, puis on n'en garde que
  // le centre : flouter directement à la taille du média laisserait le filtre
  // lire du vide au-delà du bord, d'où un halo sombre.
  const paddedBlur = sized(scratch.paddedBlur, padded.width, padded.height)
  const pb = context(paddedBlur)
  pb.clearRect(0, 0, padded.width, padded.height)
  pb.filter = `blur(${radius}px)`
  pb.drawImage(padded, 0, 0)
  pb.filter = 'none'

  const blurred = sized(scratch.blurred, width, height)
  const b = context(blurred)
  b.clearRect(0, 0, width, height)
  b.drawImage(paddedBlur, pad, pad, width, height, 0, 0, width, height)
  return blurred
}

const MASK_PAD = 35

/**
 * Compose une image (photo ou image de vidéo) dans `target`, aux dimensions du
 * média.
 */
export function composeVeil (
  target: HTMLCanvasElement,
  source: CanvasImageSource,
  width: number,
  height: number,
  persons: VeilPerson[],
  mode: VeilMode,
  scratch: VeilScratch
) {
  const out = context(sized(target, width, height))
  out.filter = 'none'
  out.globalCompositeOperation = 'source-over'

  if (mode.kind === 'nothing') {
    out.drawImage(source, 0, 0, width, height)
    return
  }
  const blurred = edgeClampedBlur(source, width, height, scratch)
  if (mode.kind === 'everything') {
    out.drawImage(blurred, 0, 0)
    return
  }

  out.drawImage(source, 0, 0, width, height)
  const visible = persons.filter(p => isBlurred(p, mode.target))
  if (!visible.length) return

  // Le masque déborde du média de `MASK_PAD` : les contours sortent souvent du
  // cadre (corps coupés par le bas), et un flou calculé au bord lirait du vide
  // — le voile s'estomperait là où il doit couvrir. Même marge que le moteur
  // (`FEATHER_PAD`).
  const maskCanvas = sized(scratch.mask, width + 2 * MASK_PAD, height + 2 * MASK_PAD)
  const mask = context(maskCanvas)
  mask.clearRect(0, 0, maskCanvas.width, maskCanvas.height)
  // 10 px du média : les deux médias sont rendus à leur taille d'origine
  // (vidéo 900 px, photo 1200 px), comme sur le moteur.
  mask.filter = 'blur(10px)'
  mask.fillStyle = '#fff'
  for (const person of visible) {
    mask.beginPath()
    person.poly.forEach(([x, y], i) => {
      const px = x * width + MASK_PAD
      const py = y * height + MASK_PAD
      if (i === 0) mask.moveTo(px, py)
      else mask.lineTo(px, py)
    })
    mask.closePath()
    mask.fill()
  }
  mask.filter = 'none'

  const veil = context(sized(scratch.veil, width, height))
  veil.globalCompositeOperation = 'source-over'
  veil.clearRect(0, 0, width, height)
  veil.drawImage(blurred, 0, 0)
  veil.globalCompositeOperation = 'destination-in'
  veil.drawImage(maskCanvas, MASK_PAD, MASK_PAD, width, height, 0, 0, width, height)
  veil.globalCompositeOperation = 'source-over'
  out.drawImage(scratch.veil, 0, 0)
}

/**
 * Les personnes à l'instant `time` de la vidéo : l'échantillon le plus proche.
 * Les contours sont calculés à 8 images/s pour une lecture à 24 — interpoler
 * n'apporterait rien, le voile est large et flou.
 */
export function personsAt (time: number): VeilPerson[] {
  const { fps, frames } = media.videoVeil
  if (!frames.length) return []
  const index = Math.max(0, Math.min(frames.length - 1, Math.round(time * fps)))
  return frames[index].persons
}
