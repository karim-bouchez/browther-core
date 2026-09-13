// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import { getLocale } from '$web-common/locale'
import { loadTimeData } from '$web-common/loadTimeData'

import { ChannelQrCode, TELEGRAM_QR, WHATSAPP_QR } from '../follow-channels/qr_codes'
import { channelsVisualUrl, icons } from './assets'
import { CHANNEL_URLS, Channel, IntroModel, isEarlyAccess } from './model'

function uiLanguage () {
  return loadTimeData.data_['language'] || navigator.language
}

/**
 * Dernière étape : Browther replacé dans l'écosystème dev&din, et les deux
 * chaînes où l'on annonce ce qui sort.
 *
 * Adaptation desktop (Karim, 2026-09-12) : chaque bouton porte aussi le QR de
 * sa chaîne. Sur un ordinateur, presque personne n'a WhatsApp ou Telegram
 * installé — scanner avec le téléphone est le chemin principal ; le clic ouvre
 * la chaîne dans un nouvel onglet, l'introduction reste dans le sien.
 */
export default function ChannelsStep (props: { model: IntroModel }) {
  const { model } = props
  return (
    <div className='bi-layout'>
      <div className='bi-copy'>
        <div className='bi-copy-top'>
          <h1 className='bi-title'>
            {getLocale(isEarlyAccess
              ? 'browtherIntroChannelsSoonTitle'
              : 'braveWelcomeFollowChannelsTitle')}
          </h1>
          <p className='bi-subtitle'>
            {getLocale(isEarlyAccess
              ? 'browtherIntroChannelsSoonDescription'
              : 'braveWelcomeFollowChannelsHook')}
          </p>
        </div>
        <div className='bi-actions'>
          <ChannelButton model={model} channel='whatsapp' qr={WHATSAPP_QR} />
          <ChannelButton model={model} channel='telegram' qr={TELEGRAM_QR} />
          {/* Cette mention appartient aux deux boutons du dessus : l'air
              au-dessous le dit. */}
          <p className='bi-channels-same'>{getLocale('browtherIntroChannelsSameContent')}</p>
          <button
            type='button'
            className='bi-button bi-button-outline'
            onClick={model.finish}
          >
            {getLocale('browtherIntroStartBrowsing')}
          </button>
        </div>
      </div>
      <div className='bi-scene bi-scene-channels'>
        <div className='bi-channels-stack'>
          <img className='bi-channels-visual' src={channelsVisualUrl(uiLanguage())} alt='' />
          <Notifications />
        </div>
      </div>
    </div>
  )
}

/**
 * Les deux notifications du prototype v2, SOUS le visuel de l'écosystème
 * (Karim, 2026-09-13). Elles ont quitté l'iOS faute de place sur l'écran d'un
 * téléphone ; ici elles tiennent. Sous le visuel parce qu'elles entrent en
 * animation : leur place est réservée dès l'arrivée, rien d'autre ne bouge.
 */
function Notifications () {
  const language = uiLanguage()
  const time = new Intl.RelativeTimeFormat(language, { numeric: 'auto', style: 'narrow' })
  return (
    <div className='bi-notifs'>
      <div className='bi-notif' style={{ '--i': 0 } as React.CSSProperties}>
        <span className='bi-notif-icon bi-notif-icon-devndin'>
          <img src={icons.devndinLogo} alt='' />
        </span>
        <div>
          <b>dev&amp;din</b>
          <p>{getLocale(isEarlyAccess ? 'browtherIntroNotifBlur' : 'browtherIntroNotifNewProject')}</p>
        </div>
        <time>{time.format(0, 'second')}</time>
      </div>
      <div className='bi-notif' style={{ '--i': 1 } as React.CSSProperties}>
        <span className='bi-notif-icon'>
          <img src={icons.app} alt='' />
        </span>
        <div>
          <b>Browther</b>
          <p>{getLocale('browtherIntroNotifMusic')}</p>
        </div>
        <time>{time.format(-2, 'day')}</time>
      </div>
    </div>
  )
}

function ChannelButton (props: { model: IntroModel, channel: Channel, qr: ChannelQrCode }) {
  const whatsapp = props.channel === 'whatsapp'
  return (
    <button
      type='button'
      className={'bi-channel bi-channel-' + props.channel}
      onClick={() => props.model.openChannel(props.channel)}
      title={CHANNEL_URLS[props.channel]}
    >
      <span className='bi-channel-logo'>
        <img src={whatsapp ? icons.whatsapp : icons.telegram} alt='' />
      </span>
      <span className='bi-channel-label'>
        {getLocale(whatsapp
          ? 'braveWelcomeFollowChannelsWhatsApp'
          : 'braveWelcomeFollowChannelsTelegram')}
      </span>
      {/* Décoratif pour un lecteur d'écran : le bouton dit déjà où il mène. */}
      <span className='bi-channel-qr' aria-hidden='true'>
        <svg viewBox={`0 0 ${props.qr.size} ${props.qr.size}`}>
          <path d={props.qr.path} fill='#000' shapeRendering='crispEdges' />
        </svg>
      </span>
    </button>
  )
}
