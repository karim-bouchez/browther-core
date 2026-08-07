/* Copyright (c) 2020 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

// Browther: réécriture complète du rendu version dans chrome://settings/help.
// L'original Brave construit un lien cliquable vers brave.com/latest/ avec
// "Brave X.X.X (Developer Build)" + une seconde ligne "Chromium: Y.Y.Y.Y".
// On préfère un layout à 3 lignes sans lien externe :
//   Browther YYYY.MM.DD[.N]
//   Brave X.X.X
//   Chromium Y.Y.Y.Y
// La version Browther vient de loadTimeData.getString('browtherProductVersion')
// (exposé par brave/browser/ui/webui/brave_settings_ui.cc, valeur de
// BROWTHER_VERSION_STRING dans brave/common/browther_version.h).

import {html} from 'chrome://resources/polymer/v3_0/polymer/polymer_bundled.min.js'
import {loadTimeData} from 'chrome://resources/js/load_time_data.js'
import {OpenWindowProxyImpl} from 'chrome://resources/js/open_window_proxy.js'

import {
  html as braveHtml,
  RegisterPolymerPrototypeModification,
  RegisterPolymerTemplateModifications,
  RegisterStyleOverride
} from 'chrome://resources/brave/polymer_overriding.js'

/** Hub dev&din — même destination que le dock du site et l'étape d'onboarding. */
const DEVNDIN_URL = 'https://devndin.com'

// Browther : « Découvrir les autres projets dev&din » sous « Obtenir de l'aide ».
// C'est le seul endroit permanent du navigateur qui parle de dev&din — l'étape
// d'onboarding ne passe qu'une fois, et personne ne la revoit.
RegisterPolymerPrototypeModification({
  'settings-about-page': (prototype: any) => {
    prototype.onBrowtherDevndinClick_ = function () {
      // `OpenWindowProxyImpl` et pas `window.open` : c'est le chemin que prend
      // déjà cette page pour ses liens externes (cf. `onPrivacyPolicyClick_`
      // upstream), et il reste testable.
      OpenWindowProxyImpl.getInstance().openUrl(DEVNDIN_URL)
    }
  }
})

RegisterStyleOverride(
  'settings-about-page',
  html`
    <style>
      #browther-version-block {
        display: block;
        margin-inline-start: unset;
        line-height: 1.45;
      }
      #browther-version-block .product-version {
        font-weight: 500;
      }
      #browther-version-block .secondary-version {
        color: var(--cr-secondary-text-color);
      }
    </style>
  `
)

const extractVersions = (versionElement: Element) => {
  // L'original Chromium produit "1.90.0 Chromium: 146.0.7680.164 (Official Build) (arm64)"
  // (le suffixe "Chromium:" vient de Brave qui patche GetVersionInformationalSuffix).
  // Regex strict : 1er numéro = Brave version, 2e numéro = Chromium version,
  // reste = build (Official Build) + bits (arm64).
  const text = versionElement.textContent ?? ''
  const match = text.match(/(\d+\.\d+(?:\.\d+)*)\D+(\d+\.\d+(?:\.\d+)*)(.*)/)
  if (!match) return { braveVersion: '', chromiumVersion: '', build: '' }
  return {
    braveVersion: match[1],
    chromiumVersion: match[2],
    build: match[3].trim(),
  }
}

const buildBrowtherVersionBlock = (
  browtherVersion: string,
  braveVersion: string,
  chromiumVersion: string,
  build: string,
) => {
  const wrapper = document.createElement('div')
  wrapper.setAttribute('id', 'browther-version-block')

  const browtherLine = document.createElement('div')
  browtherLine.classList.add('product-version')
  browtherLine.textContent = `Browther ${browtherVersion}`
  wrapper.appendChild(browtherLine)

  const braveLine = document.createElement('div')
  braveLine.classList.add('secondary-version')
  braveLine.textContent = build
    ? `Brave ${braveVersion} ${build}`
    : `Brave ${braveVersion}`
  wrapper.appendChild(braveLine)

  const chromiumLine = document.createElement('div')
  chromiumLine.classList.add('secondary-version')
  chromiumLine.textContent = `Chromium ${chromiumVersion}`
  wrapper.appendChild(chromiumLine)

  return wrapper
}

RegisterPolymerTemplateModifications({
  'settings-about-page': (templateContent) => {
    if (!templateContent.querySelector('#browther-version-block')) {
      const version =
        templateContent.querySelector('#updateStatusMessage ~ .secondary')
      if (!version) {
        console.error('[Settings] Could not find version div')
        return
      }
      const { braveVersion, chromiumVersion, build } = extractVersions(version)
      const browtherVersion =
        loadTimeData.getString('browtherProductVersion')
      const versionBlock = buildBrowtherVersionBlock(
        browtherVersion,
        braveVersion,
        chromiumVersion,
        build,
      )
      version.parentNode?.replaceChild(versionBlock, version)
    }

    // Ligne « les autres projets dev&din », juste après « Obtenir de l'aide ».
    // `external` pose la même icône de lien sortant que la ligne d'aide : les
    // deux quittent le navigateur, elles doivent l'annoncer pareil.
    const helpRow = templateContent.querySelector('#help')
    if (helpRow && !templateContent.querySelector('#browtherDevndin')) {
      helpRow.insertAdjacentElement('afterend', braveHtml`
        <cr-link-row
          class="hr"
          id="browtherDevndin"
          on-click="onBrowtherDevndinClick_"
          label="${loadTimeData.getString('browtherAboutDevndinLabel')}"
          sub-label="${loadTimeData.getString('browtherAboutDevndinSubLabel')}"
          external>
        </cr-link-row>`)
    }

    // Help link shown if update fails
    const updateStatusMessageLink =
      templateContent.querySelector('#updateStatusMessage a')
    if (updateStatusMessageLink) {
      // Browther: redirige vers notre site (l'updater natif Brave/Sparkle
      // est désactivé en V1, l'aide tient en une page sur browther.devndin.com).
      updateStatusMessageLink.setAttribute(
        'href',
        'https://browther.devndin.com/support'
      )
    }
  }
})
