// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'
import { getLocale } from '$web-common/locale'

import { useIntroAudio, useSystemVolume } from './audio'
import { Glyph } from './glyphs'
import { IntroModel } from './model'
import { AdvanceButton, IntroLayout, StampPair, SwitchRow } from './shared'

export default function MusicStep (props: { model: IntroModel, isActive: boolean }) {
  const { model } = props
  const audio = useIntroAudio()
  const first = React.useRef(true)

  React.useEffect(() => {
    // L'interrupteur ne relance rien : il change de canal, à la même position.
    // S'il n'y a encore rien à entendre, il lance l'extrait — c'est le geste
    // qui décide, jamais l'arrivée sur l'écran.
    audio.setMusicRemoved(model.musicDemoOn)
    if (first.current) {
      first.current = false
      return
    }
    if (model.musicDemoOn) audio.play()
  }, [model.musicDemoOn])

  // L'écran qui s'en va (transition, retour) se tait tout de suite.
  React.useEffect(() => {
    if (!props.isActive) audio.stop()
  }, [props.isActive])

  return (
    <IntroLayout
      title={getLocale('browtherIntroMusicTitle')}
      subtitle={getLocale('browtherIntroMusicSubtitle')}
      footnote={<p className='bi-footnote'>{getLocale('browtherIntroMusicCompat')}</p>}
      sceneClassName='bi-scene-music'
      scene={
        <div className='bi-player-card'>
          <div className='bi-player'>
            <button
              type='button'
              className='bi-player-button'
              onClick={audio.toggle}
              aria-label={getLocale(audio.isPlaying ? 'browtherIntroMusicPause' : 'browtherIntroMusicListen')}
            >
              <Glyph name={audio.isPlaying ? 'pause' : 'play'} />
            </button>
            <Scrubber
              progress={audio.progress}
              onScrub={audio.setScrubbing}
              onSeek={audio.seek}
            />
            <VolumeControl />
          </div>
          <Lanes musicRemoved={model.musicDemoOn} />
          <StampPair isOn={model.musicDemoOn} />
        </div>
      }
      actions={
        <>
          <SwitchRow
            engine='sawtunaa'
            title='Sawtunaa'
            offLabel={getLocale('browtherIntroMusicSwitchOff')}
            onLabel={getLocale('browtherIntroMusicSwitchOn')}
            isOn={model.musicDemoOn}
            onToggle={() => model.toggleDemo('music')}
          />
          <AdvanceButton
            enabled={model.musicDemoOn}
            onClick={() => {
              // ⛔ Le son s'arrête ICI, pas seulement en quittant l'écran : la
              // feuille de l'accès anticipé garde l'écran monté, l'extrait
              // continuerait derrière elle.
              audio.stop()
              model.activate('sawtunaa')
            }}
          />
        </>
      }
    />
  )
}

/**
 * La barre de lecture, déplaçable au pointeur (les deux pistes ensemble).
 * ⛔ La tête de lecture ne bouge qu'au relâcher : le curseur suit le pointeur
 * en local, sinon les lecteurs re-tamponnent et la barre saccade.
 */
function Scrubber (props: {
  progress: number
  onScrub: (scrubbing: boolean) => void
  onSeek: (fraction: number) => void
}) {
  const ref = React.useRef<HTMLDivElement>(null)
  const [dragged, setDragged] = React.useState<number | null>(null)
  const fractionAt = (clientX: number) => {
    const rect = ref.current!.getBoundingClientRect()
    return Math.min(1, Math.max(0, (clientX - rect.left) / rect.width))
  }
  const shown = Math.min(1, Math.max(0, dragged ?? props.progress))
  return (
    <div
      ref={ref}
      className={'bi-scrubber' + (dragged !== null ? ' is-dragging' : '')}
      onPointerDown={event => {
        event.currentTarget.setPointerCapture(event.pointerId)
        props.onScrub(true)
        setDragged(fractionAt(event.clientX))
      }}
      onPointerMove={event => {
        if (dragged !== null) setDragged(fractionAt(event.clientX))
      }}
      onPointerUp={event => {
        if (dragged === null) return
        const target = fractionAt(event.clientX)
        setDragged(null)
        props.onScrub(false)
        props.onSeek(target)
      }}
    >
      <div className='bi-scrubber-track'>
        <span className='bi-scrubber-fill' style={{ width: `${shown * 100}%` }} />
      </div>
      <span className='bi-scrubber-knob' style={{ left: `${shown * 100}%` }} />
    </div>
  )
}

/**
 * Le son de l'ordinateur, visible en permanence, et de quoi le régler. À zéro
 * (ou en sourdine), la jauge devient un avertissement.
 */
function VolumeControl () {
  const { volume, setLevel, startDrag, endDrag } = useSystemVolume()
  if (!volume.available || volume.level === undefined) return null
  const level = volume.muted ? 0 : volume.level
  const silent = level <= 0.001
  return (
    <div className={'bi-volume' + (silent ? ' is-silent' : '')}>
      <div className='bi-volume-row'>
        <Glyph name={silent ? 'speakerSlash' : 'speaker'} />
        <input
          type='range'
          min={0}
          max={1}
          step={0.01}
          value={level}
          aria-label={getLocale('browtherIntroVolumeLabel')}
          style={{ '--level': `${level * 100}%` } as React.CSSProperties}
          onPointerDown={startDrag}
          onPointerUp={event => endDrag(Number(event.currentTarget.value))}
          onChange={event => setLevel(Number(event.currentTarget.value))}
        />
        {/* 100 % est le cas le plus large : la place lui est réservée. */}
        <span className='bi-volume-value'>{Math.round(level * 100)} %</span>
      </div>
      <p className='bi-volume-warning'>{getLocale('browtherIntroVolumeMuted')}</p>
    </div>
  )
}

const BARS = 34

/**
 * Les deux pistes, Voix et Musique : la seconde s'écrase à presque rien et se
 * marque « retirée » quand c'est allumé.
 */
function Lanes (props: { musicRemoved: boolean }) {
  return (
    <div className='bi-lanes'>
      <Lane title={getLocale('browtherIntroMusicLaneVoice')} color='#A5B299' seed={0.7} scale={1} />
      <Lane
        title={getLocale('browtherIntroMusicLaneMusic')}
        color='#D4A857'
        seed={1.9}
        scale={props.musicRemoved ? 0.04 : 1}
        trailing={props.musicRemoved ? getLocale('browtherIntroMusicRemoved') : undefined}
      />
    </div>
  )
}

function Lane (props: {
  title: string
  color: string
  seed: number
  scale: number
  trailing?: string
}) {
  const canvasRef = React.useRef<HTMLCanvasElement>(null)
  const target = React.useRef(props.scale)
  target.current = props.scale

  React.useEffect(() => {
    const canvas = canvasRef.current
    const context = canvas?.getContext('2d')
    if (!canvas || !context) return
    let scale = target.current
    let frame = 0
    let last = 0
    const draw = (now: number) => {
      frame = requestAnimationFrame(draw)
      if (now - last < 50) return
      const dt = last ? (now - last) / 1000 : 0
      last = now
      // Rejoint sa hauteur cible en ~0,4 s, comme l'animation de l'iOS.
      scale += (target.current - scale) * Math.min(1, dt * 7)
      const ratio = window.devicePixelRatio || 1
      const width = canvas.clientWidth
      const height = canvas.clientHeight
      canvas.width = Math.round(width * ratio)
      canvas.height = Math.round(height * ratio)
      context.setTransform(ratio, 0, 0, ratio, 0, 0)
      const gap = 3
      const barWidth = (width - gap * (BARS - 1)) / BARS
      const time = now / 1000
      context.fillStyle = props.color
      for (let i = 0; i < BARS; i++) {
        const phase = time * 4.2 + i * props.seed * 0.3
        const amplitude = (0.35 + 0.65 * Math.abs(Math.sin(phase))) * scale
        const barHeight = Math.max(3, height * amplitude)
        const x = i * (barWidth + gap)
        const y = (height - barHeight) / 2
        const radius = Math.min(barWidth / 2, 3)
        context.beginPath()
        context.roundRect(x, y, barWidth, barHeight, radius)
        context.fill()
      }
    }
    frame = requestAnimationFrame(draw)
    return () => cancelAnimationFrame(frame)
  }, [])

  return (
    <div className='bi-lane'>
      <span className='bi-lane-title'>{props.title}</span>
      <canvas ref={canvasRef} className='bi-lane-bars' />
      <span className={'bi-lane-trailing' + (props.trailing ? '' : ' is-hidden')}>
        {props.trailing}
      </span>
    </div>
  )
}
