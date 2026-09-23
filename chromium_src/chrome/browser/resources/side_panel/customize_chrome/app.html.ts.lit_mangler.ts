// Copyright (c) 2025 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

import { mangle } from 'lit_mangler'

// Insert icon to "Appearance" section's heading
mangle(
  (element: DocumentFragment) => {
    const headingEl = element.querySelector(
      '#appearance sp-heading h2[slot="heading"]',
    )
    if (!headingEl) {
      throw new Error('[Customize Chrome] <#appearance sp-heading h2> is gone.')
    }

    headingEl.insertAdjacentHTML(
      'afterbegin',
      /* html */ `<leo-icon name="themes"></leo-icon>`,
    )
  },
  (template) => template.text.includes('id="appearance"'),
)

// 🔴 Browther : « Personnaliser la barre d'outils » retirée du panneau Thème
// (2026-09-23), comme la ligne jumelle des Paramètres
// (`browser/resources/settings/br/appearance_page.ts`) : elle propose d'épingler
// des fonctionnalités que Browther a COUPÉES (barre latérale, Portefeuille,
// Leo…), donc une barre d'outils à moitié vide. ⚠️ La sous-page
// `customize-chrome-toolbar` reste dans le bundle : plus rien n'y mène, et
// Brave la garde à jour — on ne retire QUE la porte d'entrée.
mangle(
  (element) => {
    const el = element.querySelector('#toolbarButton')
    if (!el) {
      throw new Error('[Customize Chrome] #toolbarButton is gone.')
    }

    // Le séparateur qui la précède part avec elle, sinon deux traits se suivent.
    const separator = el.previousElementSibling
    if (separator?.classList.contains('sp-cards-separator')) {
      separator.remove()
    }
    el.remove()
  },
  (template) => template.text.includes('id="toolbarButton"'),
)

// Insert a close button into the sp-heading element.
mangle(
  (element: DocumentFragment) => {
    const el = element.querySelector('sp-heading')
    if (!el) {
      throw new Error('[Customize Chrome] sp-heading is gone.')
    }

    el.insertAdjacentHTML(
      'afterbegin',
      /* html */ `
      <close-panel-button id="closeButton" iron-icon="close" slot="buttons"/>`,
    )
  },
  (template) => template.text.includes('sp-heading'),
)

// Add Brave Midnight(Darker) theme option
mangle(
  (element: DocumentFragment) => {
    const appearance = element.querySelector('#appearance')
    if (!appearance) {
      throw new Error('[Customize Chrome] #appearance is gone.')
    }

    appearance.insertAdjacentHTML(
      'beforeend',
      /* html */ `
      <brave-darker-theme-toggle></brave-darker-theme-toggle>`
    )
  },
  (template) => template.text.includes('id="appearance"'),
)

