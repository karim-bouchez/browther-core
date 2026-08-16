/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

import { color, font, radius } from '@brave/leo/tokens/css/variables'
import { scoped } from '$web-common/scoped_css'

// Même matière que les widgets NTP (`material.thin` + blur) : le bandeau doit
// se poser sur le fond photo sans le masquer ni se faire avaler par lui.
// L'accent est l'ambre du badge « Beta » du site, seule couleur du bandeau —
// on signale sans dramatiser : ce n'est pas une erreur.
export const style = scoped.css`
  & {
    align-self: center;
    width: 100%;
    max-width: 560px;
    display: flex;
    align-items: flex-start;
    gap: 12px;
    padding: 14px 16px;
    border-radius: ${radius.xl};
    background: ${color.material.thin};
    backdrop-filter: blur(50px);
    border: 1px solid rgba(251, 191, 36, 0.32);
    color: ${color.text.primary};
    text-align: start;
  }

  .icon {
    flex-shrink: 0;
    margin-top: 1px;
    color: #fbbf24;
    --leo-icon-size: 22px;
    /* L'icône Leo hérite sa couleur du conteneur — l'ambre s'applique au
       bécher sans avoir à toucher au SVG. */
    --leo-icon-color: currentColor;
  }

  .text {
    flex: 1 1 auto;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }

  .title {
    font: ${font.components.buttonDefault};
    color: ${color.text.primary};
  }

  .body {
    font: ${font.small.regular};
    color: ${color.text.secondary};
  }

  .channels {
    margin-top: 5px;
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 4px 10px;
    font: ${font.small.regular};

    a {
      color: #fbbf24;
      text-decoration: none;
      font: ${font.small.semibold};

      &:hover {
        text-decoration: underline;
      }
    }
  }

  .channels-label {
    color: ${color.text.secondary};
  }

  .dismiss {
    flex-shrink: 0;
    /* Cible de clic confortable sans élargir la ligne du titre : le bouton
       remonte de son propre padding pour rester aligné sur le texte. */
    margin: -6px -6px 0 0;
    padding: 6px;
    background: none;
    border: none;
    cursor: pointer;
    color: ${color.text.tertiary};
    line-height: 0;

    svg {
      width: 16px;
      height: 16px;
      display: block;
    }

    &:hover {
      color: ${color.text.primary};
    }
  }
`
