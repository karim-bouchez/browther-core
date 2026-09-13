// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

import * as React from 'react'

import { media } from './assets'
import { SystemVolume, getSystemVolume, setSystemVolume } from './model'

/**
 * ⚠️ `XMLHttpRequest`, pas `fetch` : `fetch()` refuse le schéma `chrome://`
 * (« Failed to fetch »), et l'extrait ne démarrait jamais dans la WebUI alors
 * qu'il jouait dans un aperçu servi en http. C'est la même raison qui fait
 * charger les `.wasm` de Brave par XHR (`xhr-compile-async-wasm-plugin`).
 */
function loadArrayBuffer (url: string): Promise<ArrayBuffer> {
  return new Promise((resolve, reject) => {
    const request = new XMLHttpRequest()
    request.open('GET', url)
    request.responseType = 'arraybuffer'
    request.onload = () => request.status === 200
      ? resolve(request.response as ArrayBuffer)
      : reject(new Error(`${url}: ${request.status}`))
    request.onerror = () => reject(new Error(`${url}: network error`))
    request.send()
  })
}

/**
 * L'extrait réel et sa version passée dans Sawtunaa, joués **en parallèle et
 * à la même position** : l'interrupteur ne relance rien, il change de canal.
 * Sans ça, la comparaison porterait sur deux instants différents du morceau.
 *
 * Web Audio plutôt que deux `<audio>` : les deux pistes partent sur la même
 * horloge, à l'échantillon près, et ne dérivent jamais l'une de l'autre.
 *
 * ⚠️ Rien ne démarre tout seul : le contexte audio n'est créé qu'au premier
 * geste (lecture ou mise sur ON), jamais à l'arrivée sur l'écran.
 */
class DualTrackPlayer {
  private context?: AudioContext
  private buffers?: [AudioBuffer, AudioBuffer]
  private gains?: [GainNode, GainNode]
  private sources: AudioBufferSourceNode[] = []
  private loading?: Promise<void>
  private startedAt = 0
  private offset = 0
  private musicRemoved = false
  playing = false

  get duration () {
    return this.buffers?.[0].duration ?? 0
  }

  private prepare () {
    this.loading = this.loading ?? (async () => {
      const context = new AudioContext()
      this.context = context
      const decode = async (url: string) =>
        context.decodeAudioData(await loadArrayBuffer(url))
      const [before, after] =
        await Promise.all([decode(media.audioBeforeUrl), decode(media.audioAfterUrl)])
      this.buffers = [before, after]
      this.gains = [context.createGain(), context.createGain()]
      this.gains.forEach(gain => gain.connect(context.destination))
      // ⚠️ L'état de l'interrupteur survit au chargement différé : il a pu
      // basculer pendant le décodage, c'est lui qui pose le canal.
      this.applyGains(true)
    })()
    return this.loading
  }

  private applyGains (immediate = false) {
    if (!this.gains || !this.context) return
    const [before, after] = this.gains
    const now = this.context.currentTime
    const targets: Array<[GainNode, number]> =
      [[before, this.musicRemoved ? 0 : 1], [after, this.musicRemoved ? 1 : 0]]
    for (const [gain, value] of targets) {
      gain.gain.cancelScheduledValues(now)
      if (immediate) {
        gain.gain.value = value
      } else {
        // Quelques millisecondes de rampe : sans elle, la bascule claque.
        gain.gain.setTargetAtTime(value, now, 0.012)
      }
    }
  }

  setMusicRemoved (removed: boolean) {
    this.musicRemoved = removed
    this.applyGains()
  }

  position () {
    if (!this.context || !this.duration) return 0
    if (!this.playing) return this.offset
    return (this.context.currentTime - this.startedAt) % this.duration
  }

  async play () {
    await this.prepare()
    const { context, buffers, gains } = this
    if (!context || !buffers || !gains || this.playing) return
    await context.resume()
    // Démarrage sur une base commune : lancées l'une après l'autre, les deux
    // pistes seraient décalées et la bascule s'entendrait comme un saut.
    const when = context.currentTime + 0.05
    this.sources = buffers.map((buffer, i) => {
      const source = context.createBufferSource()
      source.buffer = buffer
      source.loop = true
      source.connect(gains[i])
      source.start(when, this.offset)
      return source
    })
    this.startedAt = when - this.offset
    this.playing = true
  }

  pause () {
    if (!this.playing) return
    this.offset = this.position()
    this.sources.forEach(source => source.stop())
    this.sources = []
    this.playing = false
  }

  /** Déplacer la tête de lecture — sur les DEUX pistes. */
  async seek (fraction: number) {
    await this.prepare()
    const wasPlaying = this.playing
    this.pause()
    this.offset = Math.min(Math.max(0, fraction), 0.999) * this.duration
    if (wasPlaying) await this.play()
  }

  stop () {
    this.pause()
    this.offset = 0
  }

  dispose () {
    this.stop()
    this.context?.close().catch(() => {})
  }
}

export interface IntroAudio {
  isPlaying: boolean
  progress: number
  toggle: () => void
  play: () => void
  stop: () => void
  setMusicRemoved: (removed: boolean) => void
  setScrubbing: (scrubbing: boolean) => void
  seek: (fraction: number) => void
}

export function useIntroAudio (): IntroAudio {
  const player = React.useMemo(() => new DualTrackPlayer(), [])
  const [isPlaying, setIsPlaying] = React.useState(false)
  const [progress, setProgress] = React.useState(0)
  // Pendant qu'on déplace la tête de lecture, le rafraîchissement se tait :
  // sinon il repousse le curseur sous le pointeur et la barre saccade.
  const scrubbing = React.useRef(false)

  React.useEffect(() => () => player.dispose(), [player])

  React.useEffect(() => {
    if (!isPlaying) return
    let frame = 0
    let last = 0
    const tick = (now: number) => {
      if (now - last > 50 && !scrubbing.current && player.duration) {
        last = now
        setProgress(player.position() / player.duration)
      }
      frame = requestAnimationFrame(tick)
    }
    frame = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(frame)
  }, [isPlaying])

  const play = () => {
    player.play().then(() => setIsPlaying(player.playing)).catch(() => {})
  }
  const pause = () => {
    player.pause()
    setIsPlaying(false)
  }

  return {
    isPlaying,
    progress,
    toggle: () => (player.playing ? pause() : play()),
    play,
    stop: () => {
      player.stop()
      setIsPlaying(false)
      setProgress(0)
    },
    setMusicRemoved: removed => player.setMusicRemoved(removed),
    setScrubbing: value => { scrubbing.current = value },
    seek: fraction => {
      setProgress(fraction)
      player.seek(fraction).then(() => setIsPlaying(player.playing)).catch(() => {})
    }
  }
}

/**
 * Le son de l'ORDINATEUR, lu toutes les secondes : un Mac en sourdine joue
 * l'extrait sans qu'on entende rien, l'écran doit le dire plutôt que de laisser
 * croire à une panne. `available` faux (hors macOS pour l'instant) : la jauge
 * est masquée.
 */
export function useSystemVolume () {
  const [volume, setVolume] = React.useState<SystemVolume>({ available: false })
  const dragging = React.useRef(false)
  const pending = React.useRef<number | null>(null)

  React.useEffect(() => {
    let cancelled = false
    const refresh = () => {
      if (dragging.current) return
      getSystemVolume()
        .then(value => { if (!cancelled && !dragging.current) setVolume(value) })
        .catch(() => {})
    }
    refresh()
    const timer = window.setInterval(refresh, 1000)
    window.addEventListener('focus', refresh)
    return () => {
      cancelled = true
      window.clearInterval(timer)
      window.removeEventListener('focus', refresh)
    }
  }, [])

  const setLevel = (level: number) => {
    setVolume(v => ({ ...v, level, muted: level > 0 ? false : v.muted }))
    // Un réglage par image au plus : le curseur envoie bien plus d'évènements
    // que CoreAudio n'en a besoin.
    if (pending.current === null) {
      pending.current = requestAnimationFrame(() => {
        pending.current = null
      })
      setSystemVolume(level)
    }
  }

  const endDrag = (level: number) => {
    dragging.current = false
    setSystemVolume(level)
  }

  return {
    volume,
    setLevel,
    startDrag: () => { dragging.current = true },
    endDrag
  }
}
