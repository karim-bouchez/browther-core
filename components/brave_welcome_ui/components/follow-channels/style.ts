// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import styled from 'styled-components'

/* Reprise stricte de l'idiome des autres étapes (`help-improve/style.ts`) :
   même carte de verre dépoli, même rayon, même famille de titre. L'écran arrive
   après `HelpImprove`, il ne doit pas se lire comme une page d'un autre produit.
   Aucune couleur de marque en dur hors des deux logos de canaux, qui doivent
   rester reconnaissables. */
export const MainBox = styled.div`
  background: rgba(255, 255, 255, 0.1);
  backdrop-filter: blur(15px);
  border-radius: 30px;
  max-width: 800px;
  color: white;
  font-family: ${(p) => p.theme.fontFamily.heading};
  display: flex;
  align-items: center;
  justify-content: center;
  flex-direction: column;

  .view-header-box {
    display: grid;
    grid-template-columns: 0.1fr 1fr 0.1fr;
    padding: 40px 40px 30px 40px;
  }

  .view-details {
    grid-column: 2;
    text-align: center;
  }

  .view-title {
    font-weight: 600;
    font-size: 36px;
    margin: 0;
  }

  /* Bloc : l'invocation occupe sa propre ligne. Collée en fin de titre, elle
     tombait à cheval sur le retour à la ligne et se retrouvait coupée en deux —
     un texte RTL au bout d'une ligne LTR ne se césure pas proprement. */
  .view-title-dua {
    display: block;
    font-size: 26px;
    font-weight: 500;
    margin-top: 6px;
    opacity: 0.85;
  }

  .view-desc {
    font-size: 16px;
    line-height: 24px;
    margin: 16px auto 0;
    max-width: 540px;
    opacity: 0.9;
  }
`

export const Channels = styled.div`
  display: flex;
  align-items: stretch;
  justify-content: center;
  gap: 24px;
  padding: 0 40px;
`

export const Channel = styled.div`
  flex: 1 1 0;
  max-width: 260px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  padding: 20px;
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.08);
  /* Bordure et halo à la couleur du service : les deux cartes sont par ailleurs
     identiques (même gabarit, même QR noir et blanc), c'est la couleur qui les
     sépare d'un coup d'œil. Assez discrète pour ne pas concurrencer le bouton
     principal. */
  border: 1px solid color-mix(in srgb, var(--channel-accent) 45%, transparent);
  box-shadow: 0 0 24px -12px var(--channel-accent);

  .channel-head {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  /* Pastille blanche : le logo garde sa couleur de marque, qui se perdrait sur
     le verre dépoli violet du fond. */
  .channel-icon {
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    border-radius: 50%;
    background: white;
    color: var(--channel-accent);
    flex-shrink: 0;
  }

  .channel-icon svg {
    width: 18px;
    height: 18px;
    display: block;
  }

  .channel-name {
    font-size: 15px;
    font-weight: 600;
  }

  /* Fond blanc **plein** et non transparent : un QR se lit par contraste, la
     carte de verre dépoli laisserait passer le décor animé du fond et certains
     scanners décrocheraient. */
  .qr-frame {
    background: white;
    border-radius: 10px;
    padding: 8px;
    line-height: 0;
  }

  .qr-frame svg {
    /* 132 px = 4 px par module sur le plus gros des deux QR (33 modules), donc
       des carrés entiers : à une taille non multiple, le rendu tombe sur des
       demi-pixels et les modules bavent. Le shape-rendering crispEdges posé sur
       le path fait le reste.
       (Pas de backtick dans ces commentaires : on est à l'intérieur d'un
       template literal styled-components, un backtick le refermerait.) */
    width: 132px;
    height: 132px;
    display: block;
  }

  /* Blanc et non le bleu-lavande des liens de l'écran précédent
     (rgba(160,165,235,1)) : ce lien est posé sur une carte translucide
     par-dessus un fond violet clair, où ce bleu passait en dessous du seuil de
     contraste — il devenait presque invisible. Le blanc reste lisible quelle
     que soit la zone du décor animé qui défile derrière. */
  a {
    font-size: 12px;
    color: rgba(255, 255, 255, 0.92);
    text-decoration: underline;
    text-underline-offset: 3px;
    text-decoration-color: rgba(255, 255, 255, 0.5);
    transition: color 0.15s ease, text-decoration-color 0.15s ease;
  }

  a:hover {
    color: white;
    text-decoration-color: white;
  }
`

export const FootNote = styled.div`
  margin: 20px 40px 0;
  text-align: center;

  p {
    font-size: 12px;
    line-height: 18px;
    margin: 0;
  }

  /* La marche à suivre d'abord, l'arbitrage entre les deux canaux ensuite —
     hiérarchisés par l'opacité, pas par la taille (deux tailles de plus sur un
     écran qui en compte déjà quatre le rendraient bavard). */
  p:first-child {
    opacity: 0.9;
  }

  p:last-child {
    opacity: 0.65;
    margin-top: 4px;
  }
`

export const ActionBox = styled.div`
  width: 100%;
  display: grid;
  grid-template-columns: 0.5fr 1fr 0.5fr;
  margin: 30px 0 40px;

  .box-center {
    grid-column: 2;

    & leo-button {
      width: 100%;
    }
  }
`
