// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

/// <reference path="./media.d.ts" />

// 🔴 Les médias, les icônes et les visuels sont ceux de l'iOS, importés À LEUR
// PLACE et non recopiés : les mêmes fichiers sur toutes les plateformes
// (ONBOARDING-SPEC.md § 6), produits une fois et arbitrés avec Karim. Un
// déplacement côté iOS casse ce build bruyamment — c'est voulu.

// Vidéo et audio : la config webpack commune n'a pas de règle pour eux, d'où
// le chargeur explicite. L'audio est servi en `.mp4` (même conteneur MP4,
// octets identiques) : la source WebUI ne connaît que ce type MIME.
import videoUrl from '!!file-loader!../../../../ios/brave-ios/Sources/Brave/Frontend/Browther/Intro/Resources/browther-intro-video.mp4'
import audioBeforeUrl from '!!file-loader?name=[contenthash].mp4!../../../../ios/brave-ios/Sources/Brave/Frontend/Browther/Intro/Resources/browther-intro-audio-before.m4a'
import audioAfterUrl from '!!file-loader?name=[contenthash].mp4!../../../../ios/brave-ios/Sources/Brave/Frontend/Browther/Intro/Resources/browther-intro-audio-after.m4a'
import photoUrl from '../../../../ios/brave-ios/Sources/Brave/Frontend/Browther/Intro/Resources/browther-intro-photo.jpg'
import amiriQuranUrl from '../../../../ios/brave-ios/Sources/Brave/Frontend/Browther/Intro/Resources/AmiriQuran-Regular.ttf'
import * as videoVeilModule from '../../../../ios/brave-ios/Sources/Brave/Frontend/Browther/Intro/Resources/browther-intro-video.json'
import * as photoVeilModule from '../../../../ios/brave-ios/Sources/Brave/Frontend/Browther/Intro/Resources/browther-intro-photo.json'

// Icônes de la barre d'outils : la personne les retrouvera en haut de sa
// fenêtre, c'est ce qui relie l'écran au moteur.
import shieldIconUrl from '../../../../ios/brave-ios/Sources/Brave/Assets/Images.xcassets/browther.shield.bar.imageset/browther.shield.bar.svg'
import basarunaaIconUrl from '../../../../ios/brave-ios/Sources/Brave/Assets/Images.xcassets/basarunaa.icon.imageset/basarunaa.icon.svg'
import sawtunaaIconUrl from '../../../../ios/brave-ios/Sources/Brave/Assets/Images.xcassets/sawtunaa.icon.imageset/sawtunaa.icon.svg'
import appIconUrl from '../../../../ios/brave-ios/Sources/Brave/Assets/Images.xcassets/browther.app.icon.imageset/browther.app.icon@3x.png'
import chatWallpaperUrl from '../../../../ios/brave-ios/Sources/Brave/Assets/Images.xcassets/browther-chat-wallpaper.imageset/browther-chat-wallpaper-dark.png'
import whatsappLogoUrl from '../../../../ios/brave-ios/Sources/Onboarding/WelcomeFocus/Resources/FocusOnboardingImages.xcassets/channel-whatsapp.imageset/channel-whatsapp@3x.png'
import telegramLogoUrl from '../../../../ios/brave-ios/Sources/Onboarding/WelcomeFocus/Resources/FocusOnboardingImages.xcassets/channel-telegram.imageset/channel-telegram@3x.png'
import channelsFrUrl from '../../../../ios/brave-ios/Sources/Onboarding/WelcomeFocus/Resources/FocusOnboardingImages.xcassets/devndin-channels-fr.imageset/devndin-channels-fr.png'
import channelsEnUrl from '../../../../ios/brave-ios/Sources/Onboarding/WelcomeFocus/Resources/FocusOnboardingImages.xcassets/devndin-channels-en.imageset/devndin-channels-en.png'
import channelsArUrl from '../../../../ios/brave-ios/Sources/Onboarding/WelcomeFocus/Resources/FocusOnboardingImages.xcassets/devndin-channels-ar.imageset/devndin-channels-ar.png'
// Même tracé que `browther-devndin-logo.imageset` (variante sombre), généré par
// la fonction de `private/assets/gen-ios-devndin-logo.py`.
import devndinLogoUrl from './assets/devndin-logo-dark.svg'

export interface VeilPerson {
  /** Contour du voile, normalisé (0…1) et déjà dilaté par le moteur. */
  poly: number[][]
  gender: string
  confidence: number
}

/** Le contenu d'un module JSON, quelle que soit la façon dont il est exposé. */
function jsonOf<T> (module: unknown): T {
  return ((module as { default?: T }).default ?? module) as T
}

export const media = {
  videoUrl: videoUrl as string,
  audioBeforeUrl: audioBeforeUrl as string,
  audioAfterUrl: audioAfterUrl as string,
  photoUrl: photoUrl as string,
  amiriQuranUrl: amiriQuranUrl as string,
  videoVeil: jsonOf<{
    fps: number
    frames: Array<{ t: number, persons: VeilPerson[] }>
  }>(videoVeilModule),
  photoVeil: jsonOf<{ persons: VeilPerson[] }>(photoVeilModule)
}

export const icons = {
  shields: shieldIconUrl as string,
  basarunaa: basarunaaIconUrl as string,
  sawtunaa: sawtunaaIconUrl as string,
  app: appIconUrl as string,
  chatWallpaper: chatWallpaperUrl as string,
  whatsapp: whatsappLogoUrl as string,
  telegram: telegramLogoUrl as string,
  devndinLogo: devndinLogoUrl as string
}

/**
 * Un des fonds du Nouvel Onglet déjà embarqués : aucun asset de plus, et la
 * continuité visuelle est gratuite. C'est le pendant paysage du fond de l'iOS
 * (ciel étoilé dégradé vers le sable), servi par la source des fonds du NTP.
 */
export const welcomeBackgroundUrl =
  'chrome://background-wallpaper/mengyu-xu-AJpbLXg65yk-unsplash.jpg'

/** Le visuel existe en français, en anglais et en arabe, comme sur iOS. */
export function channelsVisualUrl (language: string): string {
  if (language.startsWith('fr')) return channelsFrUrl
  if (language.startsWith('ar')) return channelsArUrl
  return channelsEnUrl
}
