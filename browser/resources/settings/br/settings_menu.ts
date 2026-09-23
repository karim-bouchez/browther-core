/* Copyright (c) 2020 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

import {RegisterPolymerTemplateModifications, RegisterStyleOverride} from 'chrome://resources/brave/polymer_overriding.js'
import {html} from 'chrome://resources/polymer/v3_0/polymer/polymer_bundled.min.js'

import {loadTimeData} from '../i18n_setup.js'
import {pageVisibility} from './page_visibility.js'
import 'chrome://resources/brave/leo.bundle.js'

/** L'écran Parrainage (`browther_referral_launch.h` côté C++). */
const BROWTHER_REFERRAL_URL = 'browther://referral'
const BROWTHER_REFERRAL_ID = 'browtherReferralLink'

function createMenuElement(
  title: string,
  href: string,
  iconName: string,
  pageVisibilitySection: keyof typeof pageVisibility) {
  const menuEl = document.createElement('a')
  if (pageVisibilitySection) {
    menuEl.hidden = !pageVisibility[pageVisibilitySection]
  }
  menuEl.href = href
  menuEl.setAttribute('role', 'menuitem')
  menuEl.setAttribute('class', 'cr-nav-menu-item')

  const icon = document.createElement('cr-icon')
  icon.setAttribute('icon', iconName)
  menuEl.appendChild(icon)

  const text = document.createTextNode(title)
  menuEl.appendChild(text)
  const crRippleChild = document.createElement('cr-ripple')
  menuEl.appendChild(crRippleChild)
  return menuEl
}

function getMenuElement(
  templateContent: HTMLTemplateElement,
  href: string) {
  let menuEl = templateContent.querySelector(`a[href="${href}"]`)
  if (!menuEl) {
    // Search templates
    const templates = templateContent.querySelectorAll('template')
    for (const template of templates) {
      menuEl = template.content.querySelector(`a[href="${href}"]`)
      if (menuEl) {
        return menuEl
      }
    }
    console.error(`[Settings] Could not find menu item '${href}'`)
  }
  return menuEl
}

RegisterStyleOverride(
  'settings-menu',
  html`
    <style>
      :host {
        --brave-settings-menu-margin-v: 24px;
        --brave-settings-menu-padding: 24px;
        --settings-nav-item-color: var(--leo-color-text-secondary) !important;
        position: sticky;
        top: var(--brave-settings-menu-margin-v);
        margin: 0 !important;
        min-width: 172px;
        max-width: 250px;
        overflow-y: auto;
        padding: 12px 24px !important;
      }
      .cr-nav-menu-item {
        min-height: 20px !important;
        border-end-end-radius: 0px !important;
        border-start-end-radius: 0px !important;
        box-sizing: content-box !important;
        overflow: visible !important;

        --iron-icon-width: 20px;
        --iron-icon-height: 20px;
        --iron-icon-fill-color: currentColor;
      }

      .cr-nav-menu-item:hover {
        background: transparent !important;
      }

      .cr-nav-menu-item[selected] {
        --iron-icon-fill-color: var(--leo-color-icon-interactive);

        color: var(--leo-color-text-interactive) !important;
        background: transparent !important;
      }

      .cr-nav-menu-item cr-ripple {
        display: none !important;
      }

      /* ⭐ Browther : l'entrée « Parrainage ». Tout ce rail est gris ; sans un
         accent elle passe inaperçue, et c'est la seule porte vers les mois
         offerts (recette Karim, 2026-09-23). Un aplat doré très léger + le
         cadeau doré — l'or du parrainage (--gold de
         private/webui/referral/src/styles.css). ⚠️ Pas d'accent grave ici : ce
         bloc vit dans un template literal, une seule apostrophe inverse le
         couperait en deux. ⛔ Ni gras, ni pastille : l'entrée est permanente,
         elle n'annonce rien. */
      #browtherReferralLink {
        --iron-icon-fill-color: #9a5a0c;

        background: rgb(226 185 92 / 0.16) !important;
        border-radius: 8px !important;
        padding-inline: 8px !important;
        margin-inline: -8px !important;
      }

      #browtherReferralLink:hover {
        background: rgb(226 185 92 / 0.28) !important;
      }

      /* La flèche « ça s'ouvre dans un onglet » suit la même couleur. */
      #browtherReferralLink .cr-icon.icon-external {
        --cr-icon-color: #9a5a0c;
      }

      @media (prefers-color-scheme: dark) {
        #browtherReferralLink {
          --iron-icon-fill-color: #e2b95c;
        }

        #browtherReferralLink .cr-icon.icon-external {
          --cr-icon-color: #e2b95c;
        }
      }

      .menu-separator {
        margin: 4px -24px !important;
      }

      @media (prefers-color-scheme: dark) {
        :host {
          --settings-nav-item-color: var(--leo-color-text-primary) !important;
          border-color: transparent !important;
        }
      }

      a[href] {
        font-weight: 500 !important;
        margin: 0 20px 22px 0 !important;
        margin-inline-start: 0 !important;
        margin-inline-end: 0 !important;
        padding-bottom: 0 !important;
        padding-top: 0 !important;
        padding-inline-start: 0 !important;
        position: relative !important;
      }

      a[href]:focus-visible {
        box-shadow: 0 0 0 4px rgba(160, 165, 235, 1) !important;
        outline: none !important;
        border-radius: 6px !important;
      }

      a[href].selected {
        color: #DB2F04;
      }

      a:hover, cr-icon:hover {
        color: var(--leo-color-icon-interactive) !important;
      }

      cr-icon, leo-icon {
        margin-inline-end: 16px !important;
        width: 20px;
        height: 20px;
      }

      a[href].selected::before {
        content: "";
        position: absolute;
        top: 50%;
        left: calc(-1 * var(--brave-settings-menu-padding));
        transform: translateY(-50%);
        display: block;
        height: 28px;
        width: 4px;
        background: var(--leo-color-text-interactive);
        border-radius: 0px 2px 2px 0px;
      }

      @media (prefers-color-scheme: dark) {
        a[href].selected {
          color: #FB5930;
        }

        a:hover, cr-icon:hover {
          --iron-icon-fill-color: var(--leo-color-icon-interactive) !important;
          color: var(--leo-color-icon-interactive) !important;
        }
      }

      a[href],
      #advancedButton {
        --cr-selectable-focus_-_outline: var(--brave-focus-outline) !important;
      }

      #advancedButton {
        padding: 0 !important;
        margin-top: 30px !important;
        line-height: 1.25 !important;
        border: none !important;
      }

      #advancedButton > cr-icon {
        margin-inline-end: 0 !important;
      }

      #settingsHeader,
      #advancedButton {
        align-items: center !important;
        font-weight: normal !important;
        font-size: larger !important;
        color: var(--settings-nav-item-color) !important;
        margin-bottom: 20px !important;
      }

      #autofill {
        margin-top: 20px !important;
      }

      #about-menu {
        display: flex;
        flex-direction: row;
        align-items: flex-start;
        justify-content: flex-start;
        color: var(--leo-color-text-tertiary) !important;
        margin: 16px 0 0 0 !important;
        text-decoration: none !important;
      }
      .brave-about-graphic {
        flex: 0;
        display: flex;
        align-items: center;
        justify-content: flex-start;
        align-self: stretch;
        margin-right: var(--leo-spacing-xl);
      }
      .brave-about-menu-link-text{
        font-size: 14px !important;
        font-weight: 500 !important;
        color: var(--leo-color-text-secondary) !important;
      }
      .brave-about-meta {
        flex: 1;
      }
      .brave-about-item {
        display: block;
      }
    </style>
  `
)

RegisterPolymerTemplateModifications({
  'settings-menu': (templateContent) => {
    // Hide performance menu. We moved it under system menu instead.
    const performanceEl = getMenuElement(templateContent, '/performance')
    if (performanceEl) {
      performanceEl.remove()
    }

    // Add 'Get Started' item
    const getStartedEl = createMenuElement(
      loadTimeData.getString('braveGetStartedTitle'),
      '/getStarted',
      'rocket',
      'getStarted'
    )
    const peopleEl = getMenuElement(templateContent, '/people')
    if (peopleEl) {
      peopleEl.insertAdjacentElement('afterend', getStartedEl)
    }

    // Brave Origin
    const originEl = createMenuElement(
      loadTimeData.getString('braveOriginTitle'),
      '/origin',
      'product-origin',
      'origin',
    )
    getStartedEl.insertAdjacentElement('afterend', originEl)

    // Move Appearance item
    const contentEl = createMenuElement(
      loadTimeData.getString('contentSettingsContentSection'),
      '/braveContent',
      'window-content',
      'content',
    )
    const appearanceBrowserEl = getMenuElement(templateContent, '/appearance')
    if (appearanceBrowserEl && contentEl) {
      // Insert after Origin if visible, otherwise after Get Started
      const insertAfter = originEl.hidden ? getStartedEl : originEl
      insertAfter.insertAdjacentElement('afterend', appearanceBrowserEl)
      appearanceBrowserEl.insertAdjacentElement('afterend', contentEl)
    }

    // Add Shields item
    const shieldsEl = createMenuElement(
      loadTimeData.getString('braveShieldsTitle'),
      '/shields',
      'shield-done',
      'shields',
    )
    contentEl.insertAdjacentElement('afterend', shieldsEl)

    // Add privacy item
    const privacyEl = getMenuElement(templateContent, '/privacy')
    if (privacyEl && shieldsEl) {
      shieldsEl.insertAdjacentElement('afterend', privacyEl)
    }

    // Track last inserted element to simplify conditional insertions
    let lastInserted = privacyEl!

    // Browther: Web3/Wallet disabled — menu item removed
    // <if expr="enable_brave_wallet">
    // </if>

    // Browther: Leo (AI Chat) disabled — menu item removed
// <if expr="enable_ai_chat">
// </if>

    // Browther: Brave Sync disabled — endpoint `brave_sync_endpoint` est en
    // dummy (build args, cf. buildArgs.ts:158), donc Sync ne fonctionne pas.
    // Menu item retiré pour ne pas exposer une feature cassée.
    // const syncEl = createMenuElement(
    //   loadTimeData.getString('braveSync'),
    //   '/braveSync',
    //   'product-sync',
    //   'braveSync',
    // )
    // lastInserted = lastInserted.insertAdjacentElement('afterend', syncEl)!

    // Add search item
    const searchEl = getMenuElement(templateContent, '/search')
    if (searchEl) {
      lastInserted.insertAdjacentElement('afterend', searchEl)
    }

    // Add Extensions item
    const extensionEl = createMenuElement(
      loadTimeData.getString('braveDefaultExtensions'),
      '/extensions',
      'browser-extensions',
      'extensions',
    )
    if (extensionEl && searchEl) {
      searchEl.insertAdjacentElement('afterend', extensionEl)
    }

    // ⭐ Browther : « Parrainage ». ⛔ Ce n'est PAS une page de réglages : l'écran
    // vit à `browther://referral` (une adresse, où le retour de paiement, la
    // garde Sawtunaa et les toasts renvoient avec des paramètres). L'entrée
    // OUVRE donc un nouvel onglet — même patron que le lien « Extensions »
    // d'upstream : `target="_blank"`, l'icône `icon-external`, et l'entrée
    // EXCLUE du `selectable` de `<cr-menu-selector>` (sinon le menu cherche
    // une route interne pour cette adresse et casse : « settings-menu has an
    // entry with an invalid route », vu le 2026-09-23).
    // Son libellé vient du C++ (`browtherReferralTitle` = la clé `home.title`
    // des textes de l'app, déjà traduite partout), ⛔ pas d'une chaîne grit.
    // ⚠️ Le NOM de la rubrique ici, le GESTE dans le menu ⋯ : cf.
    // `browther_referral_files.h` § MenuLabel/SettingsTitle.
    if (loadTimeData.getBoolean('browtherReferralEnabled') && extensionEl) {
      const menuSelector = templateContent.querySelector('#menu')
      if (!menuSelector) {
        console.error('[Settings] Could not find menu selector')
      } else {
        const selectable = menuSelector.getAttribute('selectable') ?? 'a'
        menuSelector.setAttribute(
          'selectable', `${selectable}:not(#${BROWTHER_REFERRAL_ID})`)
      }

      const referralEl = document.createElement('a')
      referralEl.setAttribute('role', 'menuitem')
      referralEl.setAttribute('id', BROWTHER_REFERRAL_ID)
      referralEl.setAttribute('class', 'cr-nav-menu-item')
      referralEl.setAttribute('href', BROWTHER_REFERRAL_URL)
      referralEl.setAttribute('target', '_blank')

      const referralIcon = document.createElement('cr-icon')
      referralIcon.setAttribute('icon', 'gift')
      referralEl.appendChild(referralIcon)

      const referralText = document.createElement('span')
      referralText.textContent = loadTimeData.getString('browtherReferralTitle')
      referralEl.appendChild(referralText)

      // L'icône qui dit « ça s'ouvre dans un onglet » (celle d'upstream).
      const externalIcon = document.createElement('div')
      externalIcon.setAttribute('class', 'cr-icon icon-external')
      referralEl.appendChild(externalIcon)

      referralEl.appendChild(document.createElement('cr-ripple'))
      extensionEl.insertAdjacentElement('afterend', referralEl)
    }

    // Browther: page Sawtunaa retirée — la popup toolbar suffit (décision
    // 2026-05-17). Menu item retiré + route retirée dans brave_routes.ts +
    // import retiré dans basic_page.ts.
    // const sawtunaaEl = createMenuElement(
    //   loadTimeData.getString('sawtunaaTitle'),
    //   '/sawtunaa',
    //   'media-visualizer',
    //   'sawtunaa' as keyof typeof pageVisibility,
    // )
    // if (extensionEl) {
    //   extensionEl.insertAdjacentElement('afterend', sawtunaaEl)
    // }

    // Move autofill to advanced
    const autofillEl = getMenuElement(templateContent, '/autofill')
    const languagesEl = getMenuElement(templateContent, '/languages')
    if (autofillEl && languagesEl) {
      languagesEl.insertAdjacentElement('beforebegin', autofillEl)
    }

    // Remove extensions link
    const extensionsLinkEl = templateContent.querySelector('#extensionsLink')
    if (!extensionsLinkEl) {
      console.error('[Settings] Could not find extensionsLinkEl to remove')
      return
    }
    extensionsLinkEl.remove()
    // Add version number to 'about' link
    const aboutEl = templateContent.querySelector('#about-menu')
    if (!aboutEl) {
      console.error('[Settings] Could not find about-menu element')
      return
    }
    const parent = aboutEl.parentNode
    parent.removeChild(aboutEl)

    const newAboutEl = document.createElement('a')
    newAboutEl.setAttribute('href', '/help')
    newAboutEl.setAttribute('id', aboutEl.id)
    newAboutEl.setAttribute('role', 'menuitem')

    const graphicsEl = document.createElement('div')
    graphicsEl.setAttribute('class', 'brave-about-graphic')

    // Use per-channel logo image.
    const icon = document.createElement('img')
    icon.setAttribute('srcset', 'chrome://theme/current-channel-logo@1x, chrome://theme/current-channel-logo@2x 2x')
    icon.setAttribute('width', '20px')
    icon.setAttribute('height', '20px')

    const metaEl = document.createElement('div')
    metaEl.setAttribute('class', 'brave-about-meta')

    const menuLink = document.createElement('span')
    menuLink.setAttribute('class', 'brave-about-item brave-about-menu-link-text')
    menuLink.textContent = aboutEl.textContent

    const versionEl = document.createElement('span')
    versionEl.setAttribute('class', 'brave-about-item brave-about-menu-version')
    // Browther: affiche notre CalVer (YYYY.MM.DD[.N]) au lieu de la version
    // Brave upstream. browtherProductVersion est exposé par
    // brave/browser/ui/webui/brave_settings_ui.cc.
    versionEl.textContent = `v ${loadTimeData.getString('browtherProductVersion')}`

    parent.appendChild(newAboutEl)
    newAboutEl.appendChild(graphicsEl)
    graphicsEl.appendChild(icon)
    newAboutEl.appendChild(metaEl)
    metaEl.appendChild(menuLink)
    metaEl.appendChild(versionEl)
  }
})
