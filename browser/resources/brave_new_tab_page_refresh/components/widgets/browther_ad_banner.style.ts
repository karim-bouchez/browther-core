/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

import { color, font, radius } from '@brave/leo/tokens/css/variables'
import { scoped } from '$web-common/scoped_css'

// Bannière pub : largeur fluide bornée, aspect-ratio piloté par le champ
// `ratio` du serve (inline style sur .ad — pas de valeur en dur ici).
// Carousel conforme à INTEGRATION.md § 3 « UX carousel — principes communs » :
// slides 100 % sans peek, dots overlay bas-centre cliquables, flèches
// toujours visibles à cheval sur les bords (style chrome de l'app, non
// confondables avec la créa), label « Pub » en onglet à cheval sur le coin
// haut de sa slide (il glisse avec elle).
export const style = scoped.css`
  & {
    align-self: center;
    width: 100%;
    max-width: 512px;
  }

  .carousel-wrapper {
    position: relative;
  }

  .carousel {
    display: flex;
    gap: 12px;
    overflow-x: auto;
    scroll-snap-type: x mandatory;
    scrollbar-width: none;
    /* Headroom pour l'onglet « Pub » à cheval sur le coin haut des slides
       (sinon rogné par le conteneur de scroll). */
    padding-top: 10px;
  }

  .carousel::-webkit-scrollbar {
    display: none;
  }

  .ad {
    position: relative;
    flex: 0 0 100%;
    scroll-snap-align: center;
    display: block;
    padding: 0;
    border: none;
    background: none;
    cursor: pointer;
    border-radius: ${radius.xl};
  }

  .ad img {
    display: block;
    width: 100%;
    height: 100%;
    object-fit: cover;
    border-radius: ${radius.xl};
    background: ${color.container.background};
    opacity: 0;
    transition: opacity 200ms;
  }

  .ad img.loaded {
    opacity: 1;
  }

  /* Label « Pub » (annonceur externe, showAdLabel) : onglet à cheval sur le
     coin haut de la créa, langage visuel du chrome de l'app (fond + bordure)
     pour ne pas être confondu avec un élément de la pub. */
  .ad-label {
    position: absolute;
    top: -10px;
    inset-inline-start: 12px;
    z-index: 1;
    padding: 2px 8px;
    font: ${font.xSmall.semibold};
    color: ${color.text.secondary};
    background: ${color.container.background};
    border: 1px solid ${color.divider.subtle};
    border-radius: ${radius.s};
    pointer-events: none;
  }

  /* Flèches : toujours visibles (pas de hover-only), à cheval sur les bords
     de la créa, style contrôle de l'app. Rendues seulement hors extrémités
     et si plusieurs pubs (cf. tsx). */
  .arrow {
    position: absolute;
    top: 50%;
    z-index: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    width: 24px;
    height: 24px;
    padding: 0;
    border: 1px solid ${color.divider.subtle};
    border-radius: 50%;
    background: ${color.container.background};
    color: ${color.icon.default};
    cursor: pointer;
    box-shadow: 0 1px 4px rgba(0, 0, 0, 0.15);
  }

  .arrow svg {
    width: 14px;
    height: 14px;
  }

  .arrow-prev {
    inset-inline-start: 0;
    transform: translate(-50%, -50%);
  }

  .arrow-next {
    inset-inline-end: 0;
    transform: translate(50%, -50%);
  }

  /* Dots : overlay bas-centre de la créa, nus (pas de pastille de fond),
     lisibles sur créa claire via une fine ombre. Cliquables. */
  .dots {
    position: absolute;
    bottom: 6px;
    left: 0;
    right: 0;
    display: flex;
    justify-content: center;
    gap: 6px;
    pointer-events: none;
  }

  .dot {
    width: 6px;
    height: 6px;
    padding: 0;
    border: none;
    border-radius: 50%;
    background: rgba(255, 255, 255, 0.55);
    box-shadow: 0 0 2px rgba(0, 0, 0, 0.45);
    cursor: pointer;
    pointer-events: auto;
    transition: background 150ms;
  }

  .dot.active {
    background: #ffffff;
  }
`
