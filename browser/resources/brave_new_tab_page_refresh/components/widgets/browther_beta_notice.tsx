/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

import * as React from 'react'

import { loadTimeData } from '$web-common/loadTimeData'
import { getString } from '../../lib/strings'

import { style } from './browther_beta_notice.style'

// Browther : bandeau « accès anticipé » en tête du Nouvel Onglet.
//
// Pourquoi ici et pas sur le site : la majorité des installs n'y passent jamais
// (l'app iOS est trouvée directement dans l'App Store), et même celui qui vient
// du site ne revient pas lire la page après avoir téléchargé. Le seul endroit
// qui atteint tout le monde est l'app elle-même, à l'ouverture.
//
// L'enjeu n'est pas d'informer pour informer : un utilisateur qui rencontre un
// bug sans savoir qu'il est sur une version en cours de finition conclut que le
// produit est mauvais, désinstalle — ou pire, garde l'app sans jamais la
// rouvrir. Le contexte transforme la déception en patience, et le lien vers les
// canaux transforme le silence en retour exploitable.
//
// À retirer quand Browther sort de l'accès anticipé (supprimer le composant et
// ses 5 strings, pas de pref à nettoyer — le dismiss vit en localStorage).
const kDismissedKey = 'browther.betaNoticeDismissedVersion'

const kWhatsAppUrl = 'https://whatsapp.com/channel/0029Vb8ydkv5vKABH78PVX32'
const kTelegramUrl = 'https://t.me/devndin_nouveautes'

/**
 * Version applicative en cours, qui sert de clé au « déjà vu ».
 * Vide si l'injection C++ manque : on retombe alors sur un bandeau permanent
 * plutôt que sur un bandeau silencieusement désactivé.
 */
function currentVersion(): string {
  try {
    return loadTimeData.getString('browtherAppVersion')
  } catch {
    return ''
  }
}

/**
 * Le bandeau est fermé « pour cette version ». Une mise à jour le fait revenir
 * une fois : tant qu'on est en accès anticipé, chaque nouvelle build mérite de
 * redire qu'elle n'est pas la version finale. Volontairement pas une pref :
 * rien ici ne doit survivre à un reset de profil ni voyager par la sync.
 */
export function BrowtherBetaNotice() {
  const version = currentVersion()
  const [dismissed, setDismissed] = React.useState(() => {
    try {
      return localStorage.getItem(kDismissedKey) === version && version !== ''
    } catch {
      return false
    }
  })

  if (dismissed) {
    return null
  }

  const onDismiss = () => {
    setDismissed(true)
    try {
      localStorage.setItem(kDismissedKey, version)
    } catch {
      // Stockage indisponible (mode restreint) : le bandeau reviendra au
      // prochain onglet. Dégradation acceptable, on ne bloque pas la fermeture.
    }
  }

  return (
    <div data-css-scope={style.scope}>
      <div className='icon' aria-hidden='true'>
        <svg viewBox='0 0 24 24' fill='none'>
          <circle
            cx='12'
            cy='12'
            r='9'
            stroke='currentColor'
            strokeWidth='2'
          />
          <path
            d='M12 7.5v5.5'
            stroke='currentColor'
            strokeWidth='2'
            strokeLinecap='round'
          />
          <circle cx='12' cy='16.5' r='1.1' fill='currentColor' />
        </svg>
      </div>
      <div className='text'>
        <div className='title'>
          {getString(S.NEW_TAB_BROWTHER_BETA_TITLE)}
        </div>
        <div className='body'>{getString(S.NEW_TAB_BROWTHER_BETA_TEXT)}</div>
        <div className='channels'>
          <span className='channels-label'>
            {getString(S.NEW_TAB_BROWTHER_BETA_FOLLOW)}
          </span>
          <a href={kWhatsAppUrl} target='_blank' rel='noopener noreferrer'>
            WhatsApp
          </a>
          <a href={kTelegramUrl} target='_blank' rel='noopener noreferrer'>
            Telegram
          </a>
        </div>
      </div>
      <button
        className='dismiss'
        onClick={onDismiss}
        title={getString(S.NEW_TAB_BROWTHER_BETA_DISMISS)}
        aria-label={getString(S.NEW_TAB_BROWTHER_BETA_DISMISS)}
      >
        <svg viewBox='0 0 16 16' aria-hidden='true'>
          <path
            d='M4 4l8 8M12 4l-8 8'
            stroke='currentColor'
            strokeWidth='1.8'
            strokeLinecap='round'
          />
        </svg>
      </button>
    </div>
  )
}
