// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

/**
 * QR des deux canaux broadcast dev&din, **pré-générés** — cf.
 * `devndin/docs/BROADCASTS.md` §0.
 *
 * Pourquoi des données figées et pas le générateur runtime de Chromium
 * (`components/qr_code_generator`, utilisé par Brave Sync via
 * `BraveSyncHandler::HandleGetQRCode`) : les deux URL sont des constantes de
 * l'entreprise, elles ne dépendent ni du profil ni de la session. Passer par le
 * C++ imposerait un handler et un aller-retour WebUI pour un résultat toujours
 * identique. Un `<path>` SVG reste net à n'importe quelle taille, contrairement
 * au bitmap que renvoie ce générateur.
 *
 * Régénérer si une URL change (`qr-image` est déjà une dépendance du dépôt) :
 *
 *   node -e "const q=require('qr-image');
 *     console.log(q.imageSync('<url>', {type:'svg', ec_level:'M', margin:0}))"
 *
 * puis recopier le `viewBox` dans `size` et l'attribut `d` dans `path`.
 * Correction d'erreur **M** (~15 %) : le niveau par défaut, suffisant pour un QR
 * affiché à l'écran — pas d'impression, pas de surface salie.
 */
export interface ChannelQrCode {
  /** URL encodée — doit rester en phase avec le lien du bouton « ouvrir ici ». */
  url: string
  /** Côté de la grille en modules (= `viewBox="0 0 size size"`). */
  size: number
  /** Chemin SVG des modules noirs, en coordonnées de grille. */
  path: string
}

export const WHATSAPP_QR: ChannelQrCode = {
  url: 'https://whatsapp.com/channel/0029Vb8ydkv5vKABH78PVX32',
  size: 33,
  path:
    'M0 0h7v7h-7zM11 0h1v2h1v1h-1v2h-1v-1h-2v4h-1v-6h2v-1h1zM14 0h1v1h-1zM18 0h4v1h-1v1h1v1h1v1h-1v2h-1v1h-1v-2h1v-1h-1v1h-1v2h-1v-1h-1v-1h1v-3h-1v1h-1v-1h-1v-1h3zM23 0h1v1h-1zM26 0h7v7h-7zM1 1v5h5v-5zM19 1v1h1v-1zM27 1v5h5v-5zM2 2h3v3h-3zM14 2h1v1h-1zM23 2h2v2h-1v-1h-1zM28 2h3v3h-3zM14 4h3v1h-3zM10 5h1v2h-1zM12 5h1v3h1v1h1v1h1v1h1v-3h1v1h2v1h-2v1h1v1h-2v1h-1v-1h-1v-1h-1v1h-1v-3h-1v1h-1v-1h-1v-1h2zM14 6h1v1h-1zM16 6h1v2h-1zM22 6h1v3h1v1h-2v-2h-1v-1h1zM24 6h1v2h-1zM19 7h1v1h-1zM0 8h1v1h1v-1h5v1h-4v1h4v1h-1v1h-1v2h-3v-1h2v-2h-1v1h-1v-2h-2zM26 8h5v1h1v3h-2v1h2v-1h1v2h-1v1h-1v-1h-2v-1h-2v-1h1v-2h1v1h1v-1h-1v-1h-1v1h-1v2h-1v1h1v1h1v1h-1v1h-1v1h1v-1h2v1h-1v1h1v1h1v-1h-1v-1h3v-1h1v2h-2v2h-1v1h-3v-1h-1v-1h1v-1h-1v1h-1v-3h-1v2h-1v2h-2v1h2v1h-1v2h-3v-1h2v-1h-1v-1h-2v-1h1v-1h1v-1h-1v1h-1v-2h1v-1h1v1h2v-1h1v-1h2v-2h-1v-1h1v-1h1zM8 10h1v1h-1zM10 10h1v1h-1zM20 10h2v2h-1v1h-1v1h-1v2h-1v-2h-1v-1h2v-1h1zM24 10h1v1h-1zM7 11h1v2h-2v-1h1zM9 11h1v2h-1zM1 12h1v1h-1zM11 12h2v1h1v1h1v-1h1v1h1v1h-1v2h-1v1h1v-1h1v3h-1v1h1v1h-2v-2h-1v-1h-1v-2h1v-1h1v-1h-3v2h-1v-2h-1v-1h1zM14 12h1v1h-1zM21 13h2v1h-1v2h-1zM0 14h2v1h-2zM5 14h2v1h-2zM3 15h2v1h-2zM8 15h2v3h-1v-2h-1zM29 15h2v1h-2zM0 16h1v1h1v2h1v-1h1v3h-1v-1h-2v-2h-1zM5 16h2v1h-1v1h3v1h-1v1h-1v-1h-1v1h-1zM17 16h1v1h-1zM11 18h1v1h-1zM21 18v1h1v-1zM10 19h1v1h-1zM12 19h1v1h1v2h-1v1h2v3h-1v-2h-2v-1h-1v-1h-1v-1h2zM24 19h1v2h-1zM32 19h1v1h-1zM6 20h1v1h-1zM0 21h1v4h-1zM2 21h1v1h-1zM4 21h1v1h2v1h-2v1h-1zM25 21h2v1h-1v1h3v1h1v1h-1v2h1v-2h1v-1h-1v-1h1v-1h1v3h1v1h-2v2h-1v1h-1v1h-1v-1h-2v1h-2v-2h-1v-2h1v-2h1v-1h-1v-1h1zM30 21h1v1h-1zM32 21h1v1h-1zM9 22h1v2h1v1h-1v1h-2v-1h1v-1h-1v-1h1zM18 22h1v1h-1zM16 23h1v1h-1zM23 23h1v1h-1zM2 24h2v1h-2zM6 24h1v1h-1zM17 24h1v1h3v1h1v2h1v3h-1v-2h-1v1h-1v-2h1v-1h-1v-1h-2v1h2v1h-3v1h-1v-2h1v-1h-1v-1h1zM11 25h2v1h1v1h-2v-1h-1zM25 25v3h3v-3zM0 26h7v7h-7zM10 26h1v1h-1zM15 26h1v1h-1zM26 26h1v1h-1zM1 27v5h5v-5zM8 27h2v1h-1v1h1v3h-1v-1h-1zM14 27h1v2h1v1h1v-1h2v1h-1v1h-2v2h-1v-3h-1zM2 28h3v3h-3zM10 28h2v5h-2v-1h1v-3h-1zM31 29h2v1h-2zM13 30h1v2h-1zM26 30h2v1h-2zM30 30h1v2h-1v1h-1v-1h-1v-1h2zM18 31h1v1h-1zM21 31h1v1h-1zM23 31h1v1h1v-1h1v2h-4v-1h1zM8 32h1v1h-1zM17 32h1v1h-1zM27 32h1v1h-1zM31 32h1v1h-1z'
}

export const TELEGRAM_QR: ChannelQrCode = {
  url: 'https://t.me/devndin_nouveautes',
  size: 29,
  path:
    'M0 0h7v7h-7zM8 0h1v1h1v1h-2zM10 0h1v1h-1zM15 0h6v3h-1v-2h-1v2h-1v-2h-2v2h-3v-1h1v-1h1zM22 0h7v7h-7zM1 1v5h5v-5zM12 1h1v1h-1zM23 1v5h5v-5zM2 2h3v3h-3zM11 2h1v1h1v1h-1v1h1v2h1v-2h1v4h-3v-3h-1zM24 2h3v3h-3zM8 3h1v1h-1zM16 3h2v1h1v-1h1v2h1v2h-1v-1h-1v1h1v1h-1v1h-2v1h-1v2h-3v1h1v1h-2v1h-1v-1h-1v1h-2v-1h1v-1h1v-1h1v1h1v-2h2v-1h1v-1h1v-1h1v-1h1v-2h-1v-1h-1zM9 4h1v1h-1zM13 4h1v1h-1zM8 6h1v1h1v-1h1v2h-3zM16 6h1v1h-1zM0 8h1v1h-1zM2 8h2v1h-1v1h-1zM5 8h3v4h-1v-1h-1v-1h1v-1h-1v1h-2v-1h1zM20 8h1v1h1v-1h1v3h-1v1h-2zM25 8h1v1h-1zM27 8h2v2h-1v-1h-1zM9 9h3v1h-1v1h-2zM24 9h1v1h-1zM0 10h2v2h-1v-1h-1zM18 10h1v1h-1zM26 10h2v1h-2zM3 11h1v2h-1zM23 11h1v1h-1zM28 11h1v1h-1zM6 12h1v1h-1zM16 12h2v2h-1v-1h-1zM19 12h1v2h2v-1h1v1h1v2h2v1h1v-2h-1v-2h-1v-1h2v1h2v2h-1v3h-1v3h2v1h-1v2h-1v-2h-1v2h-1v1h1v1h-3v-1h-1v2h-1v2h-3v-3h-3v1h2v1h-3v-1h-2v-1h2v-2h1v-1h1v-1h4v-1h-4v1h-2v1h-1v-2h-1v-2h1v1h1v1h1v-2h3v-1h1v2h2v-1h1v1h2v-1h1v1h1v-2h-1v-1h-1v1h-1v-3h-1v2h-1v1h-1v-1h-2v-1h3v-1h-3v-1h1zM1 13h1v1h-1zM4 13h1v1h2v1h-1v1h1v1h-3v-1h1v-1h-1zM0 14h1v1h1v1h1v1h-1v1h-1v-2h-1zM14 14h1v1h-1zM3 15h1v1h-1zM10 15h1v1h2v1h1v1h-2v-1h-1v3h-1v-1h-1v-2h-1v-1h2zM13 15h1v1h-1zM15 15h1v1h-1zM7 17h1v1h-1zM0 18h1v1h-1zM3 18h1v2h-1v1h-2v-1h1v-1h1zM6 18h1v1h-1zM7 19h1v1h1v2h1v-1h2v1h-1v2h1v-1h1v2h-2v1h-1v-3h-1v1h-1v-3h-4v-1h3zM21 21v3h3v-3zM0 22h7v7h-7zM22 22h1v1h-1zM1 23v5h5v-5zM17 23v1h1v1h1v3h1v-2h1v-1h-1v-2h-1v1h-1v-1zM2 24h3v3h-3zM26 24h1v1h-1zM28 24h1v1h-1zM8 25h1v2h-1zM27 25h1v1h-1zM26 26h1v1h-1zM28 26h1v1h-1zM10 27h2v1h2v1h-6v-1h2zM24 27h2v2h-1v-1h-1zM27 27h1v2h-1zM22 28h1v1h-1z'
}
