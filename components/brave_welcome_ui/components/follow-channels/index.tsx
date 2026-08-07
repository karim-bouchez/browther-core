// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import Button from '@brave/leo/react/button'

import * as S from './style'
import { getLocale } from '$web-common/locale'
import { WelcomeBrowserProxyImpl } from '../../api/welcome_browser_proxy'
import { ChannelQrCode, TELEGRAM_QR, WHATSAPP_QR } from './qr_codes'

/**
 * Dernière étape de l'onboarding : proposer de suivre les deux canaux broadcast
 * publics dev&din (cf. `devndin/docs/BROADCASTS.md` §0).
 *
 * Pourquoi ici et pas dans les Réglages, comme sur Sawtunaa : Browther s'utilise
 * **sans compte**, il n'y a donc aucun mur de connexion derrière lequel la
 * proposition serait enfermée — mais il n'y a pas non plus d'écran où un
 * utilisateur irait la chercher. L'onboarding est le seul moment où l'on a
 * l'attention de la personne, et il est déjà là. (Décision Karim, 2026-08-07.)
 *
 * Ce n'est **pas** un formulaire : on ne collecte rien, on n'attend aucun retour.
 * Le canal public ne renvoie aucun signal d'abonnement — impossible de savoir
 * qui s'est abonné, donc rien à valider et rien à attendre. L'écran se termine
 * sur l'action de l'utilisateur, « Terminer » ou « Passer », et les deux mènent
 * exactement au même endroit.
 *
 * Le **QR est le chemin principal** : on est sur un ordinateur, presque personne
 * n'y a WhatsApp ou Telegram installé et un lien ouvrirait une impasse dans un
 * onglet. « Ouvrir sur cet ordinateur » reste offert en secondaire pour les
 * rares qui les ont. Pas de détection tactile ici (contrairement à Sawtunaa, qui
 * tourne aussi sur PC convertible) : ce WebUI n'existe que sur desktop. Les
 * portages iOS et Android devront inverser l'arbitrage — ouverture directe,
 * pas de QR.
 */

interface ChannelProps {
  qr: ChannelQrCode
  name: string
  icon: React.ReactNode
  /** Nom de l'event PostHog du clic « ouvrir ici ». */
  event: string
  /**
   * Couleur officielle du service. Les deux cartes étaient distinguées par leur
   * seul intitulé, ce qui obligeait à *lire* pour savoir laquelle est laquelle —
   * or ces deux marques se reconnaissent d'abord à leur couleur. Elle habille
   * la pastille du logo et la bordure de la carte.
   */
  accent: string
}

function TelegramIcon () {
  return (
    <svg viewBox='0 0 24 24' fill='currentColor' aria-hidden='true'>
      <path d='M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z' />
    </svg>
  )
}

function WhatsAppIcon () {
  return (
    <svg viewBox='0 0 24 24' fill='currentColor' aria-hidden='true'>
      <path d='M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 0 1-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 0 1-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 0 1 2.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0 0 12.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 0 0 5.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 0 0-3.48-8.413z' />
    </svg>
  )
}

function Channel (props: ChannelProps) {
  const { qr, name, icon, event, accent } = props

  const handleOpenHere = () => {
    WelcomeBrowserProxyImpl.getInstance().trackOnboardingEvent(event, {
      source: 'onboarding'
    })
  }

  return (
    <S.Channel style={{ '--channel-accent': accent } as React.CSSProperties}>
      <div className='channel-head'>
        {/* Logo dans une pastille blanche, comme les deux marques s'affichent
            partout ailleurs : sur le verre dépoli violet, un logo teinté à même
            le fond perdrait sa couleur. */}
        <span className='channel-icon'>{icon}</span>
        <span className='channel-name'>{name}</span>
      </div>

      {/* Le QR est décoratif pour un lecteur d'écran : il ne porte rien que le
          lien « ouvrir ici », juste en dessous, ne dise déjà. */}
      <div className='qr-frame'>
        <svg viewBox={`0 0 ${qr.size} ${qr.size}`} aria-hidden='true'>
          <path d={qr.path} fill='#000' shapeRendering='crispEdges' />
        </svg>
      </div>

      {/* Pas d'instruction « scanne ce QR » ici : répétée à l'identique sous
          chacune des deux cartes, elle doublait le bruit sans rien apprendre à
          la seconde lecture. Elle est dite une fois, sous les deux. */}
      <a
        href={qr.url}
        target='_blank'
        rel='noopener noreferrer'
        onClick={handleOpenHere}
      >
        {getLocale('braveWelcomeFollowChannelsOpenHere')}
      </a>
    </S.Channel>
  )
}

function FollowChannels () {
  // Résolue au montage et pas au clic : l'URL de fin d'onboarding est un
  // aller-retour vers le navigateur, la demander pendant que la personne lit
  // l'écran évite d'attendre au moment de cliquer. Même pattern que HelpImprove,
  // qui portait cette redirection avant que cette étape n'existe.
  const [completeURLPromise] = React.useState(() => {
    return WelcomeBrowserProxyImpl.getInstance().getWelcomeCompleteURL()
  })

  const handleFinish = () => {
    completeURLPromise.then((url) => {
      window.open(url || 'chrome://newtab', '_self', 'noopener')
    })
  }

  return (
    <S.MainBox>
      <div className='view-header-box'>
        <div className='view-details'>
          <h1 className='view-title'>
            {getLocale('braveWelcomeFollowChannelsTitle')}
            {/* L'invocation est posée ici et **pas** dans la string traduite :
                collée en fin de titre elle se faisait couper en plein milieu
                par le retour à la ligne (le mélange LTR/RTL empêche un césure
                propre). Sur sa propre ligne, elle est lisible et n'a pas à être
                retraduite — la formule est la même dans toutes les langues. */}
            <span className='view-title-dua' dir='rtl' lang='ar'>
              إن شاء الله
            </span>
          </h1>
          <p className='view-desc'>
            {getLocale('braveWelcomeFollowChannelsHook')}
          </p>
        </div>
      </div>

      <S.Channels>
        {/* Couleurs officielles des deux services (mêmes valeurs que le panneau
            QR de Sawtunaa, `ChannelQrPanel.tsx`) : ce sont elles qui font
            reconnaître la carte avant même d'en lire l'intitulé. */}
        <Channel
          qr={WHATSAPP_QR}
          name={getLocale('braveWelcomeFollowChannelsWhatsApp')}
          icon={<WhatsAppIcon />}
          event='marketing_whatsapp_channel_clicked'
          accent='#25D366'
        />
        <Channel
          qr={TELEGRAM_QR}
          name={getLocale('braveWelcomeFollowChannelsTelegram')}
          icon={<TelegramIcon />}
          event='marketing_telegram_channel_clicked'
          accent='#229ED9'
        />
      </S.Channels>

      {/* Les deux seules choses à savoir, dites une fois pour les deux cartes :
          comment faire, puis pourquoi le choix n'a pas d'importance (les canaux
          sont à égalité, seule compte l'app déjà utilisée). */}
      <S.FootNote>
        <p>{getLocale('braveWelcomeFollowChannelsScanHint')}</p>
        <p>{getLocale('braveWelcomeFollowChannelsSameContent')}</p>
      </S.FootNote>

      <S.ActionBox>
        <div className='box-center'>
          <Button kind='filled' onClick={handleFinish} size='large'>
            {getLocale('braveWelcomeFinishButtonLabel')}
          </Button>
        </div>
      </S.ActionBox>
    </S.MainBox>
  )
}

export default FollowChannels
