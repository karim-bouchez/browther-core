// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import { getLocale } from '$web-common/locale'

import BraveSVG from '../svg/browser-icons/brave'
import ChromeSVG from '../svg/browser-icons/chrome'
import ChromeBetaSVG from '../svg/browser-icons/chrome-beta'
import ChromeCanarySVG from '../svg/browser-icons/chrome-canary'
import ChromeDevSVG from '../svg/browser-icons/chrome-dev'
import ChromiumSVG from '../svg/browser-icons/chromium'
import EdgeSVG from '../svg/browser-icons/edge'
import FirefoxSVG from '../svg/browser-icons/firefox'
import MicrosoftIE from '../svg/browser-icons/ie'
import OperaSVG from '../svg/browser-icons/opera'
import SafariSVG from '../svg/browser-icons/safari'
import VivaldiSVG from '../svg/browser-icons/vivaldi'
import WhaleSVG from '../svg/browser-icons/whale'
import YandexSVG from '../svg/browser-icons/yandex'
import { icons } from './assets'
import { Glyph, GlyphName } from './glyphs'
import { ImportItem, ImportSource, IntroImport, offeredItems } from './import'
import { IntroModel } from './model'
import { IntroLayout } from './shared'

/** Les logos de l'écran d'import Brave, repris tels quels. */
const BROWSER_ICONS: Record<string, React.ComponentType> = {
  'Google Chrome Canary': ChromeCanarySVG,
  'Google Chrome': ChromeSVG,
  'Google Chrome Dev': ChromeDevSVG,
  'Google Chrome Beta': ChromeBetaSVG,
  'Chromium': ChromiumSVG,
  'Microsoft Edge': EdgeSVG,
  'Firefox': FirefoxSVG,
  'Opera': OperaSVG,
  'Safari': SafariSVG,
  'Vivaldi': VivaldiSVG,
  'NAVER Whale': WhaleSVG,
  'Yandex': YandexSVG,
  'Microsoft Internet Explorer': MicrosoftIE,
  'Brave': BraveSVG
}

/** Libellés des cases d'import des Réglages : déjà traduits partout. */
const ITEMS: Record<ImportItem, { label: string, glyph: GlyphName }> = {
  favorites: { label: 'browtherIntroImportFavorites', glyph: 'star' },
  passwords: { label: 'browtherIntroImportPasswords', glyph: 'key' },
  history: { label: 'browtherIntroImportHistory', glyph: 'clock' },
  extensions: { label: 'browtherIntroImportExtensions', glyph: 'puzzle' },
  payments: { label: 'browtherIntroImportPayments', glyph: 'creditCard' },
  autofillFormData: { label: 'browtherIntroImportAutofill', glyph: 'textCursor' },
  search: { label: 'browtherIntroImportSearch', glyph: 'magnifier' }
}

// Même test que `chrome://resources/js/platform.js`.
const isMac = /Mac/.test(navigator.platform)

/**
 * « Emporte tes favoris. » Écran propre au desktop, présenté seulement si un
 * autre navigateur est installé. La scène montre ce qui passe d'un navigateur
 * à l'autre, élément par élément, au rythme RÉEL de l'import (événements
 * natifs) : rien n'y est simulé.
 */
export default function ImportStep (props: { model: IntroModel }) {
  const { model } = props
  const { importer } = model
  const { status, source } = importer
  const profile = source?.profile
  const settled = status === 'done' || status === 'failed'
  // macOS demande le mot de passe de la session pour ouvrir les secrets de
  // l'autre navigateur (« Chrome Safe Storage ») : prévenu, ce n'est plus une
  // alerte inquiétante au milieu de l'introduction.
  const keychain = isMac && !settled &&
    Boolean(profile?.passwords || profile?.payments) &&
    source?.browserType !== 'Safari' && source?.browserType !== 'Firefox'

  return (
    <IntroLayout
      title={getLocale('browtherIntroImportTitle')}
      subtitle={getLocale('browtherIntroImportSubtitle')}
      sceneClassName='bi-scene-import'
      scene={<Transfer importer={importer} />}
      actions={
        <>
          <SourcePicker importer={importer} />
          {keychain && (
            <p className='bi-footnote bi-import-note'>
              {getLocale('browtherIntroImportKeychainNote')}
            </p>
          )}
          <div className='bi-import-actions'>
            <button
              type='button'
              className='bi-button bi-button-primary'
              disabled={status === 'running' || !profile}
              onClick={settled ? model.advance : model.startImport}
            >
              {getLocale(settled
                ? 'browtherIntroContinue'
                : status === 'running'
                  ? 'browtherIntroImportInProgress'
                  : 'braveWelcomeImportButtonLabel')}
            </button>
            {/* Hauteur réservée : le bouton du dessus ne bouge pas quand
                « Plus tard » s'efface. */}
            <button
              type='button'
              className={'bi-button bi-button-ghost' +
                (status === 'idle' ? '' : ' is-hidden')}
              disabled={status !== 'idle'}
              onClick={model.skipImport}
            >
              {getLocale('browtherIntroLaterButton')}
            </button>
          </div>
        </>
      }
    />
  )
}

function BrowserLogo (props: { source: ImportSource | undefined }) {
  const Logo = props.source?.browserType
    ? BROWSER_ICONS[props.source.browserType]
    : undefined
  return Logo ? <Logo /> : <Glyph name='photo' />
}

/**
 * Les navigateurs trouvés : une ligne par profil, un seul choix, un vrai bouton
 * radio. ⛔ Pas les cartes puis des pastilles de profils en dessous : deux
 * niveaux, et les pastilles répétaient le nom du navigateur (recette Karim,
 * 2026-09-13).
 */
function SourcePicker (props: { importer: IntroImport }) {
  const { importer } = props
  const locked = importer.status === 'running'
  return (
    <div className='bi-sources' role='radiogroup'>
      {importer.sources.map(source => {
        const selected = source === importer.source
        return (
          <button
            key={source.profile.index}
            type='button'
            role='radio'
            aria-checked={selected}
            disabled={locked && !selected}
            className={'bi-source' + (selected ? ' is-selected' : '')}
            onClick={() => importer.selectSource(source.profile.index)}
          >
            <span className='bi-source-logo'><BrowserLogo source={source} /></span>
            <span className='bi-source-name'>
              <strong>{source.browser}</strong>
              {source.profileLabel && <small>{source.profileLabel}</small>}
            </span>
            <span className='bi-source-radio' />
          </button>
        )
      })}
    </div>
  )
}

/**
 * L'ancien navigateur, Browther, et ce qui passe de l'un à l'autre. Avant
 * l'import, la liste n'est qu'un aperçu : ⛔ pas d'anneau vide en bout de
 * ligne, il se lisait comme une case à cocher (recette Karim, 2026-09-13).
 * Pendant l'import : en cours (anneau qui tourne), importé (coche). Un élément
 * que l'import n'a pas ramené reste barré d'un tiret : on ne coche pas ce qui
 * n'est pas arrivé.
 */
function Transfer (props: { importer: IntroImport }) {
  const { importer } = props
  const { status } = importer
  const items = offeredItems(importer.source?.profile)
  return (
    <div className={`bi-transfer is-${status}`}>
      <div className='bi-transfer-head'>
        <span className='bi-transfer-app'>
          <span className='bi-transfer-tile'><BrowserLogo source={importer.source} /></span>
          <span className='bi-transfer-label'>
            {importer.source?.browser}
            {importer.source?.profileLabel && <small>{importer.source.profileLabel}</small>}
          </span>
        </span>
        <span className='bi-transfer-track' aria-hidden='true'>
          <span /><span /><span /><span /><span />
        </span>
        <span className='bi-transfer-app'>
          <span className='bi-transfer-tile'><img src={icons.app} alt='' /></span>
          <span className='bi-transfer-label'>Browther</span>
        </span>
      </div>
      <p className='bi-transfer-status' aria-live='polite'>
        {status === 'done' && <Glyph name='check' />}
        {status === 'done' && getLocale('browtherIntroImportDone')}
        {status === 'failed' && getLocale('browtherIntroImportFailed')}
        {status === 'running' && getLocale('browtherIntroImportInProgress')}
      </p>
      <ul className='bi-transfer-items'>
        {items.map(item => {
          const state = importer.imported.includes(item)
            ? 'is-imported'
            : importer.current === item
              ? 'is-current'
              : status === 'done' || status === 'failed' ? 'is-missed' : ''
          return (
            <li key={item} className={'bi-transfer-item ' + state}>
              <Glyph name={ITEMS[item].glyph} className='bi-transfer-glyph' />
              <span>{getLocale(ITEMS[item].label)}</span>
              <span className='bi-transfer-state'>
                {state === 'is-imported' && <Glyph name='check' />}
              </span>
            </li>
          )
        })}
      </ul>
    </div>
  )
}
