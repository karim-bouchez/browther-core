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

  .channel-head {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .channel-icon svg {
    width: 20px;
    height: 20px;
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

  .qr-hint {
    font-size: 12px;
    line-height: 17px;
    text-align: center;
    margin: 0;
    opacity: 0.85;
  }

  a {
    font-size: 12px;
    color: rgba(160, 165, 235, 1);
    text-decoration: underline;
    text-underline-offset: 2px;
  }
`

export const SameNote = styled.p`
  font-size: 12px;
  margin: 20px 0 0;
  opacity: 0.7;
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
