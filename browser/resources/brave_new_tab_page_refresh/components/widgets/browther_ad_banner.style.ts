/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

import { color, radius } from '@brave/leo/tokens/css/variables'
import { scoped } from '$web-common/scoped_css'

// Bannière pub : largeur fluide bornée, ratio 3.2:1 préservé. Carousel
// scroll-snap quand plusieurs pubs sont servies (sinon une seule visible).
export const style = scoped.css`
  & {
    align-self: center;
    width: 100%;
    max-width: 512px;
  }

  .carousel {
    display: flex;
    gap: 12px;
    overflow-x: auto;
    scroll-snap-type: x mandatory;
    scrollbar-width: none;
  }

  .carousel::-webkit-scrollbar {
    display: none;
  }

  .ad {
    flex: 0 0 100%;
    scroll-snap-align: center;
    display: block;
    padding: 0;
    border: none;
    background: none;
    cursor: pointer;
    border-radius: ${radius.xl};
    overflow: hidden;
  }

  .ad img {
    display: block;
    width: 100%;
    aspect-ratio: 3.2 / 1;
    object-fit: cover;
    border-radius: ${radius.xl};
    background: ${color.container.background};
    opacity: 0;
    transition: opacity 200ms;
  }

  .ad img.loaded {
    opacity: 1;
  }
`
