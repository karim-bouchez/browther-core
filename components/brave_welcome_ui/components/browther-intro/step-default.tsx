// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import { getLocale } from '$web-common/locale'

import { icons } from './assets'
import { Glyph } from './glyphs'
import { IntroModel } from './model'
import { Engine, EngineIcon, IntroLayout } from './shared'

/**
 * « Bloque le haram, par défaut. » L'écran montre le BÉNÉFICE — un lien reçu
 * dans une conversation qui s'ouvre protégé — plutôt que le chemin dans les
 * réglages : c'est ce qui décide, et macOS montre lui-même sa demande ensuite.
 */
export default function DefaultBrowserStep (props: { model: IntroModel }) {
  const { model } = props
  const [sheetUp, setSheetUp] = React.useState(false)
  React.useEffect(() => {
    const timer = window.setTimeout(() => setSheetUp(true), 600)
    return () => window.clearTimeout(timer)
  }, [])

  return (
    <IntroLayout
      title={getLocale('browtherIntroDefaultTitle')}
      subtitle={getLocale('browtherIntroDefaultSubtitle')}
      sceneClassName='bi-scene-default'
      scene={
        <div className='bi-chat'>
          <Conversation />
          <BrowserSheet up={sheetUp} />
        </div>
      }
      actions={
        <>
          <button
            type='button'
            className='bi-button bi-button-primary'
            onClick={model.setAsDefaultBrowser}
          >
            {getLocale('braveWelcomeSetDefaultButtonLabel')}
          </button>
          <button
            type='button'
            className='bi-button bi-button-ghost'
            onClick={model.later}
          >
            {getLocale('browtherIntroLaterButton')}
          </button>
        </>
      }
    />
  )
}

/**
 * Une conversation reconnaissable comme telle : barre de contact, fond de la
 * messagerie (celui de WhatsApp — choix de Karim, 2026-09-12 : la scène
 * illustre un lien reçu, elle n'agit pas sur le service), bulles asymétriques.
 */
function Conversation () {
  return (
    <div className='bi-chat-conversation'>
      <div className='bi-chat-contact'>
        <Glyph name='chevronLeft' className='bi-chat-back' />
        <span className='bi-chat-avatar'><Glyph name='people' /></span>
        <span className='bi-chat-who'>
          <strong>{getLocale('browtherIntroDemoContactName')}</strong>
          <small>{getLocale('browtherIntroDemoMessagingApp')}</small>
        </span>
        <Glyph name='video' />
        <Glyph name='phone' />
      </div>
      <div
        className='bi-chat-thread'
        style={{ backgroundImage: `url("${icons.chatWallpaper}")` }}
      >
        <div className='bi-bubble'>{getLocale('browtherIntroDemoMessageIncoming')}</div>
        <div className='bi-bubble bi-bubble-link'>
          <span className='bi-bubble-thumb' />
          <span className='bi-bubble-text'>
            <strong>{getLocale('browtherIntroDemoArticleTitle')}</strong>
            <small>{getLocale('browtherIntroDemoSiteName')}</small>
          </span>
        </div>
      </div>
    </div>
  )
}

/**
 * Ce que devient le lien. ⚠️ Ça doit ressembler à un NAVIGATEUR et se DÉTACHER
 * de la conversation : surface plus élevée, liseré net, ombre portée, en-tête
 * nommé, barre d'adresse avec son cadenas, et ce que Browther vient de retirer,
 * nommé — un « 3 bloqués » ne dit pas quoi.
 */
function BrowserSheet (props: { up: boolean }) {
  return (
    <div className={'bi-chat-sheet' + (props.up ? ' is-up' : '')}>
      <span className='bi-chat-sheet-grip' />
      <div className='bi-chat-sheet-head'>
        <img src={icons.app} alt='' />
        <strong>{getLocale('browtherIntroDemoOpenedIn')}</strong>
        <Glyph name='xmark' />
      </div>
      <div className='bi-chat-address'>
        <Glyph name='lock' />
        <span>{getLocale('browtherIntroDemoSiteName')}</span>
        <EngineIcon engine='shields' />
      </div>
      <div className='bi-chat-stats'>
        <Stat engine='shields' label={getLocale('browtherIntroDemoStatAds')} />
        <Stat engine='sawtunaa' label={getLocale('browtherIntroDemoStatMusic')} />
        <Stat engine='basarunaa' label={getLocale('browtherIntroDemoStatImages')} />
      </div>
      <div className='bi-chat-page'>
        <span className='bi-chat-page-hero' />
        <span className='bi-chat-page-line' style={{ width: '70%' }} />
        <span className='bi-chat-page-line' />
        <span className='bi-chat-page-line' style={{ width: '85%' }} />
      </div>
    </div>
  )
}

function Stat (props: { engine: Engine, label: string }) {
  return (
    <span className='bi-chat-stat'>
      <EngineIcon engine={props.engine} />
      {props.label}
    </span>
  )
}
