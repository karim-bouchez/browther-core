// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AVFoundation
import BrowtherAnalytics
import Foundation

/// Provides the path to the NSNet2 ONNX model bundled with the Sawtunaa module.
public enum SawtunaaResources {
  public static var nsnet2ModelPath: String? {
    Bundle.module.path(forResource: "nsnet2-stateful", ofType: "onnx")
  }
}

/// Structured metric logger. Emits one JSON-line per event with relative timestamp.
/// Format: `[METRIC] {"t":1234,"event":"name","key":"value",...}`
/// Use `analyze_sawtunaa_metrics.py` to parse.
public enum SawtunaaMetric {
  // Session start time (CFAbsoluteTimeGetCurrent at first metric call)
  nonisolated(unsafe) private static var sessionStart: CFAbsoluteTime = 0
  nonisolated(unsafe) private static var sessionStarted = false
  private static let lock = NSLock()

  public static func reset() {
    lock.lock()
    sessionStart = CFAbsoluteTimeGetCurrent()
    sessionStarted = true
    lock.unlock()
  }

  public static func emit(_ event: String, _ kvs: [String: Any] = [:]) {
    lock.lock()
    if !sessionStarted {
      sessionStart = CFAbsoluteTimeGetCurrent()
      sessionStarted = true
    }
    let t = Int((CFAbsoluteTimeGetCurrent() - sessionStart) * 1000)
    lock.unlock()

    var dict: [String: Any] = ["t": t, "event": event]
    for (k, v) in kvs { dict[k] = v }
    if let data = try? JSONSerialization.data(withJSONObject: dict),
      let json = String(data: data, encoding: .utf8)
    {
      print("[METRIC] \(json)")
    }
  }
}

/// Audio player that processes PCM through NSNet2 (noise/music suppression) and plays via AVAudioEngine.
/// Designed for the MSE interception pipeline: JS decodes Opus -> sends PCM chunks -> Swift processes + plays.
///
/// ## Synchronisation (boucle fermée depuis le 2026-09-30)
///
/// Chaque bloc est posé à une **position explicite** de la timeline du
/// `playerNode` (`scheduleBuffer(_:at:)`) : un échantillon de la source à
/// `sourceMs` joue à `anchorSample + (sourceMs - anchorSourceMs) × 48`. Un trou
/// dans la source reste un trou, un underrun ne décale plus la suite, et la
/// position AUDIBLE de l'audio se calcule exactement (horloge du player +
/// `outputLatency`) pour la comparer à `video.currentTime` à chaque tick.
///
/// Avant, les blocs étaient enchaînés à l'aveugle (5 s d'avance) et la dérive
/// n'était que mesurée : toute vidéo qui calait (rebuffering, reprise après
/// pause, seek) décalait l'audio pour de bon — sur macOS l'audio EST l'horloge
/// du lecteur, d'où « ça marche sur Mac et pas sur iPhone ».
///
/// Le décalage est rattrapé par un **resync** (vidage du player + ré-ancrage
/// sur la vidéo, rejoué depuis le cache) : à chaque reprise (pause, vidéo qui
/// calait, seek) et quand la dérive mesurée dépasse `driftToleranceMs` de façon
/// soutenue.
public class SawtunaaAudioPlayer {

  // Construit au premier `start()` seulement (cf. `makeEngine()`).
  private var engine: AVAudioEngine?
  private let playerNode = AVAudioPlayerNode()
  private let format: AVAudioFormat
  private var isRunning = false
  private var nsnet2: NSNet2Processor?

  private let preprocessQueue = DispatchQueue(label: "nsnet2.preprocess", qos: .userInteractive)
  // Cache of processed chunks, mirroring the contents of YouTube's MSE
  // SourceBuffer. Chunks are kept after being scheduled so we can re-play
  // them on seek without depending on YouTube to re-deliver via appendBuffer.
  // Sorted by timestampMs.
  // `timestampMs` = horodatage du bloc ENVOYÉ par le JS (identité : dédup,
  // éviction, curseur). `startMs` = position source réelle du premier
  // échantillon RENDU : NSNet2 retient une fenêtre d'analyse (≤ 959 frames)
  // qu'il rend en tête du bloc suivant, donc la sortie commence un peu avant.
  private var audioCache:
    [(timestampMs: Double, startMs: Double, durationMs: Double, buffer: AVAudioPCMBuffer)] = []
  private var preprocessCount = 0
  // Frames entrées / sorties de NSNet2 depuis son dernier reset. Confinés à
  // `preprocessQueue` (comme `nsnet2.reset()`).
  private var processorFramesIn = 0
  private var processorFramesOut = 0
  // Browther: stats publiques anonymes — accumule samples traités pour reporter
  // 1 seconde dès qu'on dépasse le sampleRate (=48000), évite spam UserDefaults.
  private var statsAccumulatedSamples: Int = 0

  // ── Timeline du player ──
  // Échantillon du player (player time) qui porte la source `anchorSourceMs`.
  // nil = pas encore ancré (démarrage, après un resync) : rien n'est planifié.
  private var anchorSample: AVAudioFramePosition?
  private var anchorSourceMs: Double = 0
  // Fin (en échantillons player) du dernier bloc planifié : un bloc suivant
  // qui déborderait dessus est rogné, jamais superposé.
  private var lastScheduledEndSample: AVAudioFramePosition = 0
  // Cursor in the audio cache: only chunks with timestampMs > this value are
  // eligible for scheduling. Strictly increasing per chunk to prevent the
  // same chunk from being re-scheduled (esp. for chunks shorter than the gap
  // tolerance, which would re-match against a duration-based cursor).
  private var scheduledCursorTsMs: Double = -1
  // Le prochain tick doit vider le player et se ré-ancrer sur la vidéo.
  private var needsResync = false
  private var isPaused = false
  private var driftOverCount = 0
  private var lastResyncAt: CFAbsoluteTime = 0
  private var lastVideoNowMs: Double = 0
  private var lastDriftMs: Double?

  private var playedChunkCount = 0
  private var skippedChunkCount = 0
  private var trimmedChunkCount = 0
  private var resyncCount = 0
  // Epoch counter: incremented on every clearChunks (page reset / new video).
  // preprocessChunk captures the current epoch when enqueued and the result
  // is dropped if the epoch has changed by the time NSNet2 finishes — this
  // avoids inserting stale chunks from a previous page into the fresh cache.
  private var epoch: UInt64 = 0

  // Engine state polling
  private var stateTimer: Timer?
  private var configObserver: NSObjectProtocol?

  public var isAvailable: Bool { nsnet2?.isAvailable ?? false }

  /// Au-delà, l'audio est jugé désynchronisé. L'oreille repère un audio EN
  /// AVANCE dès ~45 ms et en retard vers ~125 ms (ITU-R BT.1359) : 80 ms reste
  /// sous le seuil perçu pour le retard, et le resync coûte un micro-trou,
  /// donc pas plus serré.
  private static let driftToleranceMs: Double = 80
  /// Nombre de ticks consécutifs (JS : 30 ms) hors tolérance avant resync —
  /// ~300 ms, pour ne pas réagir à la gigue d'un seul `currentTime`.
  private static let driftTicksBeforeResync = 10
  /// Garde-fou anti-emballement : un resync de dérive au plus par seconde.
  private static let minDriftResyncInterval: CFAbsoluteTime = 1.0

  public init() {
    // Stéréo depuis le 2026-08-29 : le JS envoie les deux canaux en planar et
    // NSNet2 applique le même masque à chacun (cf. NSNet2Processor). Avant, tout
    // était downmixé en mono et la scène stéréo s'effondrait sur chaque vidéo.
    format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    SawtunaaMetric.emit(
      "player_init",
      ["sample_rate": 48000, "channels": 2])
  }

  deinit {
    if let configObserver {
      NotificationCenter.default.removeObserver(configObserver)
    }
  }

  /// Load the NSNet2 ONNX model from a file path.
  /// After load, runs a warmup pass on 1s of silence to amortize the first-chunk
  /// processing spike (~1.2s observed). The processor's GRU states are then reset
  /// to a clean slate before real audio arrives.
  public func loadModel(path: String) {
    SawtunaaMetric.emit("model_load_start", ["path": path])
    let t0 = CFAbsoluteTimeGetCurrent()
    preprocessQueue.async { [weak self] in
      let processor = NSNet2Processor(modelPath: path)
      let loadMs = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)

      // Warmup: process 1s of silence to prime ONNX runtime, vDSP buffers, GRU states.
      let warmupT0 = CFAbsoluteTimeGetCurrent()
      let silence = [Float](repeating: 0, count: 48000 * 2)  // 1 s planar L+R
      _ = processor.process(silence)
      let warmupMs = Int((CFAbsoluteTimeGetCurrent() - warmupT0) * 1000)
      // Reset state so first real chunk starts from a clean slate
      processor.reset()

      DispatchQueue.main.async {
        self?.nsnet2 = processor
        SawtunaaMetric.emit(
          "model_load_done",
          [
            "available": processor.isAvailable,
            "load_ms": loadMs,
            "warmup_ms": warmupMs,
          ])
      }
    }
  }

  /// Le moteur n'existe qu'à partir du premier `start()`, c.-à-d. quand une
  /// vidéo passe réellement par le pipeline — et donc APRÈS le `setCategory`
  /// mixable. Le handler (et ce lecteur) est créé pour CHAQUE onglet, Sawtunaa
  /// allumé ou non : un `AVAudioEngine` câblé + `prepare()` dès l'init prenait
  /// la sortie audio sous la catégorie par défaut (`.soloAmbient`, non
  /// mixable), et iOS interrompait l'audio des autres apps — un PiP d'un autre
  /// navigateur se mettait en pause à l'ouverture de Browther (2026-09-21).
  private func makeEngine() -> AVAudioEngine {
    if let engine { return engine }
    let engine = AVAudioEngine()
    engine.attach(playerNode)
    engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    // Changement de sortie (écouteurs branchés, AirPods, appel…) : iOS ARRÊTE
    // le moteur, et la latence de sortie change. Sans ça, `isRunning` restait
    // vrai sur un moteur mort — silence jusqu'au rechargement de l'onglet.
    configObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.isRunning = false
      self.requestResync()
      SawtunaaMetric.emit("engine_config_change", [:])
    }
    self.engine = engine
    return engine
  }

  public func start() {
    guard !isRunning else { return }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)
      let engine = makeEngine()
      // engine.prepare() before start() guarantees the audio graph has
      // allocated all internal resources. Without this call, the playerNode
      // can report `lastRenderTime == nil` for several IO cycles after
      // start, and any scheduleBuffer in that window crashes with
      // 'player did not see an IO cycle'.
      engine.prepare()
      try engine.start()
      if !isPaused { playerNode.play() }
      isRunning = true
      SawtunaaMetric.emit(
        "engine_start",
        [
          "success": true,
          "nsnet2_available": self.nsnet2?.isAvailable ?? false,
          "output_latency_ms": Int(session.outputLatency * 1000),
          "io_buffer_ms": Int(session.ioBufferDuration * 1000),
        ])
      startStatePolling()
    } catch {
      SawtunaaMetric.emit(
        "engine_start",
        ["success": false, "error": error.localizedDescription])
    }
  }

  public func stop() {
    stopStatePolling()
    // Jamais démarré : pas de moteur, et `playerNode` n'est rattaché à rien.
    guard let engine else { return }
    playerNode.stop()
    engine.stop()
    isRunning = false
    SawtunaaMetric.emit("engine_stop", [:])
  }

  // MARK: - State polling

  private func startStatePolling() {
    stopStatePolling()
    DispatchQueue.main.async { [weak self] in
      self?.stateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
        [weak self] _ in
        guard let self = self else { return }
        // Detect holes in the cache: gaps between consecutive chunks > 100ms.
        // Useful to flag "missing audio" zones the user may experience as silence.
        var holes = 0
        var holeMs = 0
        var cacheFirstTs = -1
        var cacheLastEnd = -1
        if !self.audioCache.isEmpty {
          cacheFirstTs = Int(self.audioCache.first!.timestampMs)
          cacheLastEnd =
            Int(self.audioCache.last!.timestampMs + self.audioCache.last!.durationMs)
          for i in 1..<self.audioCache.count {
            let prevEnd = self.audioCache[i - 1].timestampMs
              + self.audioCache[i - 1].durationMs
            let gap = self.audioCache[i].timestampMs - prevEnd
            if gap > 100 {
              holes += 1
              holeMs += Int(gap)
            }
          }
        }

        // drift_ms > 0 : audio en retard sur l'image ; < 0 : en avance.
        let driftMs = self.lastDriftMs
        SawtunaaMetric.emit(
          "engine_state",
          [
            "engine_running": self.engine?.isRunning ?? false,
            "player_playing": self.playerNode.isPlaying,
            "cache_size": self.audioCache.count,
            "cache_first_ts": cacheFirstTs,
            "cache_last_end": cacheLastEnd,
            "cache_holes": holes,
            "cache_hole_ms": holeMs,
            "audio_src_ms": driftMs.map { Int(self.lastVideoNowMs - $0) } ?? -1,
            "video_src_ms": Int(self.lastVideoNowMs),
            "drift_ms": driftMs.map { Int($0) } ?? -99999,
            "played_total": self.playedChunkCount,
            "skipped_total": self.skippedChunkCount,
            "trimmed_total": self.trimmedChunkCount,
            "resync_total": self.resyncCount,
            "preprocessed_total": self.preprocessCount,
          ])
      }
    }
  }

  private func stopStatePolling() {
    DispatchQueue.main.async { [weak self] in
      self?.stateTimer?.invalidate()
      self?.stateTimer = nil
    }
  }

  // MARK: - Horloge audio

  /// Dernier cycle rendu par le player : échantillon (player time) et instant
  /// hôte où il sort de l'appareil (hors `outputLatency`). nil tant que le
  /// player n'a pas vu d'IO cycle depuis `play()`.
  private func lastRender() -> (sample: AVAudioFramePosition, hostSeconds: Double)? {
    guard let nodeTime = playerNode.lastRenderTime,
      nodeTime.isSampleTimeValid,
      let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
      playerTime.isSampleTimeValid
    else { return nil }
    let host =
      nodeTime.isHostTimeValid
      ? AVAudioTime.seconds(forHostTime: nodeTime.hostTime)
      : AVAudioTime.seconds(forHostTime: mach_absolute_time())
    return (playerTime.sampleTime, host)
  }

  private static func nowHostSeconds() -> Double {
    AVAudioTime.seconds(forHostTime: mach_absolute_time())
  }

  /// Position source (ms) de l'échantillon qu'on ENTEND en ce moment, latence
  /// de sortie comprise (haut-parleur ≈ 10-20 ms, Bluetooth ≈ 150-250 ms —
  /// c'est pourquoi on ne peut pas se contenter d'une avance fixe).
  private func audibleSourceMs() -> Double? {
    guard let anchorSample, let render = lastRender() else { return nil }
    let outputLatency = AVAudioSession.sharedInstance().outputLatency
    let sinceRenderMs = (Self.nowHostSeconds() - render.hostSeconds - outputLatency) * 1000
    return anchorSourceMs + Double(render.sample - anchorSample) / 48.0 + sinceRenderMs
  }

  // MARK: - Pre-processing pipeline

  /// Pre-process a stereo PCM chunk through NSNet2 on a serial background queue.
  /// `samples` is PLANAR: all of L, then all of R (`count == frames * 2`).
  /// The result is stored in the cache for later playback via `playChunksUpTo`.
  /// ⚠️ On traite AUSSI pendant la pause : YouTube continue de remplir son
  /// tampon MSE, et un bloc jeté ici ne revient jamais (trou de silence à la
  /// reprise). Le cache + le plafond d'avance empêchent déjà l'audio de
  /// prendre de l'avance — même correctif que sur Android.
  public func preprocessChunk(samples: [Float], timestampMs: Double) {
    let receivedAt = CFAbsoluteTimeGetCurrent()
    let chunkEpoch = epoch
    // No chunk_preprocess_start emit: chunk_preprocess_done arrives
    // shortly after with all the same info plus the result. Saves
    // ~1 log line per chunk (a third of all log volume).
    preprocessQueue.async { [weak self] in
      guard let self = self, let nsnet2 = self.nsnet2 else {
        SawtunaaMetric.emit(
          "chunk_preprocess_drop",
          [
            "chunk_ts": Int(timestampMs),
            "reason": "nsnet2_not_ready",
          ])
        return
      }
      // Early-exit: if a clearChunks/pageReset happened while this chunk
      // was waiting in the preprocess queue, abort BEFORE running NSNet2.
      // Otherwise we'd waste ~280ms processing a chunk we'll drop later
      // anyway — and 15+ chunks in flight at once × 280ms = ~5s of dead
      // audio after every reset (visible as `chunk_skip_old` cascade).
      if chunkEpoch != self.epoch {
        SawtunaaMetric.emit(
          "chunk_preprocess_drop",
          [
            "chunk_ts": Int(timestampMs),
            "reason": "stale_epoch_pre",
            "chunk_epoch": Int(chunkEpoch),
            "current_epoch": Int(self.epoch),
          ])
        return
      }
      let t0 = CFAbsoluteTimeGetCurrent()
      let channels = Int(self.format.channelCount)
      // Ce que NSNet2 retenait AVANT ce bloc sort en tête de sa sortie : la
      // sortie commence donc `retainedFrames` avant `timestampMs`.
      let retainedFrames = self.processorFramesIn - self.processorFramesOut
      // Planar in, planar out. ⚠️ `frames` peut être < ce qui a été envoyé :
      // NSNet2 retient jusqu'à une fenêtre d'analyse (latence STFT), comme sur
      // macOS — rien n'est perdu, c'est rendu au chunk suivant.
      let processed = nsnet2.process(samples)
      let nsnet2Ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
      let frames = processed.count / channels
      self.processorFramesIn += samples.count / channels
      self.processorFramesOut += frames
      guard frames > 0 else { return }
      let startMs = timestampMs - Double(retainedFrames) / 48.0

      // Browther: stats anonymes — chaque seconde filtrée compte. On compte des
      // FRAMES, pas des samples : sinon la stéréo doublerait les music_seconds.
      let sampleRateInt = Int(self.format.sampleRate)
      self.statsAccumulatedSamples += frames
      if self.statsAccumulatedSamples >= sampleRateInt {
        let secondsToReport = self.statsAccumulatedSamples / sampleRateInt
        self.statsAccumulatedSamples -= secondsToReport * sampleRateInt
        BrowtherStatsReporter.shared.addMusicSeconds(secondsToReport)
      }

      guard
        let buffer = AVAudioPCMBuffer(
          pcmFormat: self.format,
          frameCapacity: AVAudioFrameCount(frames)
        ),
        let channelData = buffer.floatChannelData
      else { return }
      buffer.frameLength = AVAudioFrameCount(frames)
      for ch in 0..<channels {
        let dst = channelData[ch]
        let base = ch * frames
        for i in 0..<frames { dst[i] = processed[base + i] }
      }

      let totalMs = Int((CFAbsoluteTimeGetCurrent() - receivedAt) * 1000)
      let durationMs = Double(frames) / 48.0
      DispatchQueue.main.async {
        // Drop the chunk if a clearChunks/pageReset happened between enqueue
        // and completion: it belongs to a stale session.
        if chunkEpoch != self.epoch {
          SawtunaaMetric.emit(
            "chunk_preprocess_drop",
            [
              "chunk_ts": Int(timestampMs),
              "reason": "stale_epoch",
              "chunk_epoch": Int(chunkEpoch),
              "current_epoch": Int(self.epoch),
            ])
          return
        }
        // Insert into cache, sorted by timestampMs (deduplicate if exists).
        let entry = (
          timestampMs: timestampMs, startMs: startMs, durationMs: durationMs, buffer: buffer
        )
        if let existingIdx = self.audioCache.firstIndex(where: { $0.timestampMs == timestampMs })
        {
          self.audioCache[existingIdx] = entry
        } else if let insertIdx = self.audioCache.firstIndex(where: {
          $0.timestampMs > timestampMs
        }) {
          self.audioCache.insert(entry, at: insertIdx)
        } else {
          self.audioCache.append(entry)
        }
        // Cap the cache size (LRU-ish): drop oldest if > 600 chunks (~10 min @ 1s/chunk)
        if self.audioCache.count > 600 {
          self.audioCache.removeFirst(self.audioCache.count - 600)
        }
        self.preprocessCount += 1
        SawtunaaMetric.emit(
          "chunk_preprocess_done",
          [
            "chunk_ts": Int(timestampMs),
            "start_ms": Int(startMs),
            "nsnet2_ms": nsnet2Ms,
            "total_ms": totalMs,
            "frames": frames,
            "cache_size": self.audioCache.count,
            "preprocess_idx": self.preprocessCount,
            "epoch": Int(chunkEpoch),
          ])
      }
    }
  }

  /// Remet NSNet2 à zéro (GRU + fenêtre STFT) et les compteurs qui situent sa
  /// sortie. Toujours sur `preprocessQueue`, dans l'ordre des blocs.
  private func resetProcessor() {
    preprocessQueue.async { [weak self] in
      guard let self else { return }
      self.nsnet2?.reset()
      self.processorFramesIn = 0
      self.processorFramesOut = 0
    }
  }

  // MARK: - Playback

  /// Planifier au plus 5 s d'avance : au-delà, un burst YouTube remplirait le
  /// player pour rien (le resync le viderait).
  private static let lookaheadMs: Double = 5000

  /// Tick du scheduler JS (toutes les 30 ms, vidéo en lecture ET qui avance).
  /// `videoMs` = `video.currentTime` relevé par le JS à l'instant `sentAtMs`
  /// (horloge murale, ms) ; on l'extrapole jusqu'à maintenant pour absorber le
  /// délai du message JS→natif.
  public func playChunksUpTo(videoMs: Double, sentAtMs: Double?, rate: Double) {
    if !isRunning {
      start()
      guard isRunning else {
        SawtunaaMetric.emit("play_chunks_engine_failed", ["video_ms": Int(videoMs)])
        return
      }
    }

    var videoNowMs = videoMs
    if let sentAtMs {
      let transitMs = Date().timeIntervalSince1970 * 1000 - sentAtMs
      // Horloges murales du même appareil : un écart hors [0, 500] = horloge
      // ajustée entre-temps, on l'ignore plutôt que de s'y fier.
      if transitMs > 0 && transitMs < 500 { videoNowMs += transitMs * rate }
    }
    lastVideoNowMs = videoNowMs

    // Un `playAt` n'est envoyé que si l'image avance : s'il arrive encore en
    // pause, c'est que le `resumeAudio` s'est perdu (le JS remet son état de
    // pause à zéro à chaque init segment, donc après chaque seek).
    if isPaused { resumePlayback() }

    if needsResync {
      resync(reason: pendingResyncReason)
    }

    // Ancrage : il faut que le player ait vu un IO cycle depuis `play()`
    // (sinon `scheduleBuffer` lève 'player did not see an IO cycle', une
    // NSException non rattrapable). Le tick suivant (30 ms) réessaie.
    if anchorSample == nil {
      guard let render = lastRender(), render.sample > 0 else {
        SawtunaaMetric.emit("play_chunks_no_io_cycle_yet", ["video_ms": Int(videoNowMs)])
        return
      }
      // L'échantillon `render.sample` sort à `render.hostSeconds + outputLatency` :
      // il doit porter la source que la vidéo affichera à cet instant.
      let outputLatency = AVAudioSession.sharedInstance().outputLatency
      let untilAudibleMs = (render.hostSeconds + outputLatency - Self.nowHostSeconds()) * 1000
      anchorSample = render.sample
      anchorSourceMs = videoNowMs + untilAudibleMs * rate
      lastScheduledEndSample = render.sample
      driftOverCount = 0
      SawtunaaMetric.emit(
        "anchor",
        [
          "video_ms": Int(videoNowMs),
          "anchor_source_ms": Int(anchorSourceMs),
          "output_latency_ms": Int(outputLatency * 1000),
        ])
    } else if let audible = audibleSourceMs() {
      checkDrift(videoNowMs: videoNowMs, audibleMs: audible)
      if anchorSample == nil { return }  // resync déclenché : ré-ancrage au prochain tick
    }

    scheduleFromCache(videoNowMs: videoNowMs)
  }

  private func checkDrift(videoNowMs: Double, audibleMs: Double) {
    let drift = videoNowMs - audibleMs
    lastDriftMs = drift
    guard abs(drift) > Self.driftToleranceMs else {
      driftOverCount = 0
      return
    }
    driftOverCount += 1
    guard driftOverCount >= Self.driftTicksBeforeResync,
      CFAbsoluteTimeGetCurrent() - lastResyncAt >= Self.minDriftResyncInterval
    else { return }
    SawtunaaMetric.emit(
      "drift_resync", ["drift_ms": Int(drift), "video_ms": Int(videoNowMs)])
    resync(reason: "drift")
  }

  /// Planifie, depuis le curseur, les blocs du cache qui tombent dans la
  /// fenêtre d'avance. Chaque bloc va à SA position sur la timeline du player ;
  /// ce qui est déjà passé (ou chevauche le bloc précédent) est rogné.
  private func scheduleFromCache(videoNowMs: Double) {
    guard let anchorSample, let render = lastRender() else { return }
    // Ne jamais planifier dans un cycle déjà rendu ou en cours de rendu :
    // 2 buffers IO + 10 ms de marge pour le temps passé ici sur le main thread.
    let ioFrames = AVAudioFramePosition(AVAudioSession.sharedInstance().ioBufferDuration * 48000)
    let earliestSample = render.sample + 2 * ioFrames + 480

    while let nextIdx = audioCache.firstIndex(where: { $0.timestampMs > scheduledCursorTsMs }) {
      let next = audioCache[nextIdx]
      if next.startMs > videoNowMs + Self.lookaheadMs { return }

      let startSample =
        anchorSample + AVAudioFramePosition(((next.startMs - anchorSourceMs) * 48).rounded())
      let totalFrames = AVAudioFramePosition(next.buffer.frameLength)
      let floorSample = max(earliestSample, lastScheduledEndSample)
      scheduledCursorTsMs = next.timestampMs

      if startSample + totalFrames <= floorSample {
        skippedChunkCount += 1
        SawtunaaMetric.emit(
          "chunk_skip_old",
          [
            "chunk_ts": Int(next.timestampMs),
            "video_ms": Int(videoNowMs),
            "lag_ms": Int(Double(floorSample - startSample - totalFrames) / 48.0),
          ])
        continue
      }

      let skipFrames = max(0, floorSample - startSample)
      let buffer: AVAudioPCMBuffer
      if skipFrames > 0 {
        guard let trimmed = trim(next.buffer, droppingFirst: Int(skipFrames)) else { continue }
        buffer = trimmed
        trimmedChunkCount += 1
      } else {
        buffer = next.buffer
      }
      let at = startSample + skipFrames
      playerNode.scheduleBuffer(
        buffer, at: AVAudioTime(sampleTime: at, atRate: 48000), options: [])
      lastScheduledEndSample = at + AVAudioFramePosition(buffer.frameLength)
      playedChunkCount += 1

      let event: String
      if playedChunkCount == 1 {
        event = "first_chunk_played"
      } else {
        event = skipFrames > 0 ? "chunk_play_trim" : "chunk_play_full"
      }
      SawtunaaMetric.emit(
        event,
        [
          "chunk_ts": Int(next.timestampMs),
          "video_ms": Int(videoNowMs),
          "trimmed": skipFrames > 0,
          "skip_ms": Int(Double(skipFrames) / 48.0),
          "play_idx": playedChunkCount,
        ])
    }
  }

  /// Copie de `buffer` sans ses `n` premières frames (tous les canaux).
  private func trim(_ buffer: AVAudioPCMBuffer, droppingFirst n: Int) -> AVAudioPCMBuffer? {
    let total = Int(buffer.frameLength)
    guard n < total,
      let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total - n)),
      let src = buffer.floatChannelData,
      let dst = out.floatChannelData
    else { return nil }
    let remaining = total - n
    out.frameLength = AVAudioFrameCount(remaining)
    // ⚠️ Tous les canaux, pas seulement le gauche : en stéréo, ne copier que
    // le canal 0 laissait le droit à zéro sur chaque chunk rogné.
    for ch in 0..<Int(format.channelCount) {
      for i in 0..<remaining { dst[ch][i] = src[ch][n + i] }
    }
    return out
  }

  private var pendingResyncReason = "resume"

  private func requestResync(reason: String = "config_change") {
    needsResync = true
    pendingResyncReason = reason
  }

  /// Vide le player et oublie l'ancrage : le prochain tick se ré-ancre sur la
  /// position vidéo du moment et rejoue depuis le cache (rien à re-traiter).
  private func resync(reason: String) {
    needsResync = false
    if isRunning {
      playerNode.stop()
      if !isPaused { playerNode.play() }
    }
    anchorSample = nil
    lastScheduledEndSample = 0
    // Un bloc fait ~1 s : tout ce qui démarre plus de 2 s avant la vidéo est
    // fini, inutile de le re-parcourir.
    scheduledCursorTsMs = max(-1, lastVideoNowMs - 2000)
    playedChunkCount = 0
    driftOverCount = 0
    lastDriftMs = nil
    lastResyncAt = CFAbsoluteTimeGetCurrent()
    resyncCount += 1
    SawtunaaMetric.emit("resync", ["reason": reason, "video_ms": Int(lastVideoNowMs)])
  }

  /// Vidéo en pause OU qui cale (rebuffering, seek en cours) : le JS coupe
  /// l'audio net pour qu'il ne file pas devant l'image.
  public func pausePlayback() {
    isPaused = true
    guard isRunning else { return }
    playerNode.pause()
    SawtunaaMetric.emit("pause_audio", [:])
  }

  /// La vidéo avance de nouveau. On ne reprend PAS la file telle quelle :
  /// l'image redémarre avec un temps de latence que l'audio n'a pas, et la
  /// pause a été détectée avec jusqu'à un tick de retard. On se ré-ancre.
  public func resumePlayback() {
    isPaused = false
    requestResync(reason: "resume")
    guard isRunning else { return }
    playerNode.play()
    SawtunaaMetric.emit("resume_audio", [:])
  }

  /// Full reset: drop the entire audio cache and reset all state.
  /// Used on init segment (new video / page reload), NOT on seek (use seekTo).
  public func clearChunks() {
    let prev = audioCache.count
    epoch &+= 1  // invalidate any in-flight preprocess from a prior session
    audioCache.removeAll()
    preprocessCount = 0
    skippedChunkCount = 0
    trimmedChunkCount = 0
    isPaused = false
    lastVideoNowMs = 0
    resync(reason: "clear")
    resetProcessor()
    SawtunaaMetric.emit(
      "clear_chunks",
      ["dropped_cache": prev, "epoch": Int(epoch)])
  }

  /// Seek to a new video position. Keeps the audio cache (so we can re-play
  /// chunks already processed for the seek target if YouTube doesn't re-deliver
  /// them via appendBuffer).
  public func seekTo(toMs: Double) {
    lastVideoNowMs = toMs
    skippedChunkCount = 0
    trimmedChunkCount = 0
    resync(reason: "seek")
    // Reset NSNet2 state (the GRU continuity is broken anyway by the seek)
    resetProcessor()
    let chunksAvailable = audioCache.filter {
      $0.timestampMs + $0.durationMs > toMs - 200
        && $0.timestampMs < toMs + Self.lookaheadMs
    }.count
    SawtunaaMetric.emit(
      "seek_to",
      ["target_ms": Int(toMs), "cache_size": audioCache.count, "available": chunksAvailable])
  }

  /// Evict chunks whose timestamp falls within [startMs, endMs). Mirrors a
  /// `SourceBuffer.remove(start, end)` call from YouTube.
  public func evictRange(startMs: Double, endMs: Double) {
    let before = audioCache.count
    audioCache.removeAll {
      $0.timestampMs >= startMs && $0.timestampMs < endMs
    }
    let removed = before - audioCache.count
    if removed > 0 {
      SawtunaaMetric.emit(
        "cache_evict_range",
        ["start_ms": Int(startMs), "end_ms": Int(endMs), "removed": removed])
    }
  }

  /// Drop cached chunks whose timestamp is not contained in any of the given
  /// ranges. Used to mirror the buffer state of YouTube's MSE SourceBuffer.
  public func cleanOutsideBuffered(ranges: [(start: Double, end: Double)]) {
    let before = audioCache.count
    audioCache.removeAll { chunk in
      !ranges.contains { range in
        chunk.timestampMs >= range.start && chunk.timestampMs < range.end
      }
    }
    let removed = before - audioCache.count
    if removed > 0 {
      SawtunaaMetric.emit(
        "cache_sync_cleanup",
        ["removed": removed, "kept": audioCache.count, "ranges": ranges.count])
    }
  }
}
