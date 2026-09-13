// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import { getLocale } from '$web-common/locale'

import { media } from './assets'
import { Glyph, GlyphName } from './glyphs'
import { VeilMode, VeilScratch, composeVeil, personsAt, sameMode } from './veil'

function TileTag (props: { glyph: GlyphName, label: string }) {
  return (
    <span className='bi-tile-tag'>
      <Glyph name={props.glyph} />
      {props.label}
    </span>
  )
}

// MARK: - Vidéo

const VIDEO_WIDTH = 900
const VIDEO_HEIGHT = 506

/**
 * La vignette « vidéo » : le voile suit les personnes, image par image.
 *
 * Le filtre tourne DANS LE FLUX : `requestVideoFrameCallback` donne l'instant
 * exact de l'image qui va s'afficher, c'est lui qui choisit les contours — le
 * voile ne peut pas prendre une image de retard sur la personne qu'il couvre.
 * L'élément `<video>` reste dans la page (sinon Chromium cesse de décoder),
 * mais transparent : seule la toile composée est visible, jamais l'image
 * nette avant son voile.
 */
export function VideoTile (props: { mode: VeilMode }) {
  const videoRef = React.useRef<HTMLVideoElement>(null)
  const canvasRef = React.useRef<HTMLCanvasElement>(null)
  const modeRef = React.useRef(props.mode)
  modeRef.current = props.mode

  React.useEffect(() => {
    const video = videoRef.current
    const canvas = canvasRef.current
    if (!video || !canvas) return
    const scratch = new VeilScratch()
    let handle = 0
    const draw = (_now: number, frame: VideoFrameCallbackMetadata) => {
      composeVeil(canvas, video, VIDEO_WIDTH, VIDEO_HEIGHT,
        personsAt(frame.mediaTime), modeRef.current, scratch)
      handle = video.requestVideoFrameCallback(draw)
    }
    handle = video.requestVideoFrameCallback(draw)
    video.play().catch(() => {})
    return () => {
      video.cancelVideoFrameCallback(handle)
      video.pause()
    }
  }, [])

  return (
    <div className='bi-tile'>
      <video
        ref={videoRef}
        className='bi-tile-video-source'
        src={media.videoUrl}
        muted
        loop
        playsInline
        aria-hidden='true'
      />
      <canvas ref={canvasRef} className='bi-tile-canvas' />
      <TileTag glyph='play' label={getLocale('browtherIntroTileVideo')} />
    </div>
  )
}

// MARK: - Photo

let photoPromise: Promise<HTMLImageElement> | undefined
function loadPhoto () {
  photoPromise = photoPromise ?? new Promise((resolve, reject) => {
    const image = new Image()
    image.onload = () => resolve(image)
    image.onerror = reject
    image.src = media.photoUrl
  })
  return photoPromise
}

/**
 * La vignette « image » : le voile y est propre. Deux toiles superposées : la
 * nouvelle composition apparaît en fondu PAR-DESSUS l'ancienne, qui reste
 * affichée dessous — changer de cible ne fait pas sauter l'image, et le fond
 * ne transparaît jamais.
 */
export function PhotoTile (props: { mode: VeilMode }) {
  const canvases = [
    React.useRef<HTMLCanvasElement>(null),
    React.useRef<HTMLCanvasElement>(null)
  ]
  const scratch = React.useMemo(() => new VeilScratch(), [])
  const [front, setFront] = React.useState(0)
  const [drawn, setDrawn] = React.useState<VeilMode | null>(null)

  React.useEffect(() => {
    if (drawn && sameMode(drawn, props.mode)) return
    let cancelled = false
    loadPhoto().then(image => {
      if (cancelled) return
      const back = drawn ? 1 - front : front
      const canvas = canvases[back].current
      if (!canvas) return
      composeVeil(canvas, image, image.naturalWidth, image.naturalHeight,
        media.photoVeil.persons, props.mode, scratch)
      setFront(back)
      setDrawn(props.mode)
    }).catch(() => {})
    return () => { cancelled = true }
  }, [props.mode])

  return (
    <div className='bi-tile'>
      {canvases.map((ref, i) => (
        <canvas
          key={i}
          ref={ref}
          className={'bi-tile-canvas' +
            (drawn ? (i === front ? ' is-front' : '') : ' is-empty')}
        />
      ))}
      <TileTag glyph='photo' label={getLocale('browtherIntroTileImage')} />
    </div>
  )
}
