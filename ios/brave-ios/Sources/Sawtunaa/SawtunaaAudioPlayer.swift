// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AVFoundation
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
public class SawtunaaAudioPlayer {

  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private let format: AVAudioFormat
  private var isRunning = false
  private var nsnet2: NSNet2Processor?

  private let preprocessQueue = DispatchQueue(label: "nsnet2.preprocess", qos: .userInteractive)
  private var processedChunks: [(timestampMs: Double, buffer: AVAudioPCMBuffer)] = []
  private var preprocessCount = 0
  private var playedChunkCount = 0
  private var skippedChunkCount = 0
  private var trimmedChunkCount = 0
  private var firstChunkPlayedAt: Int?  // session-relative ms

  // Engine state polling
  private var stateTimer: Timer?

  public var isAvailable: Bool { nsnet2?.isAvailable ?? false }

  public init() {
    format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
    engine.attach(playerNode)
    engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    SawtunaaMetric.emit(
      "player_init",
      ["sample_rate": 48000, "channels": 1])
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
      let silence = [Float](repeating: 0, count: 48000)
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

  public func start() {
    guard !isRunning else { return }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)
      try engine.start()
      playerNode.play()
      isRunning = true
      SawtunaaMetric.emit(
        "engine_start",
        [
          "success": true,
          "nsnet2_available": self.nsnet2?.isAvailable ?? false,
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
        let queuedMs = self.estimateQueuedAudioMs()
        SawtunaaMetric.emit(
          "engine_state",
          [
            "engine_running": self.engine.isRunning,
            "player_playing": self.playerNode.isPlaying,
            "queue_depth": self.processedChunks.count,
            "audio_queued_ms": queuedMs,
            "played_total": self.playedChunkCount,
            "skipped_total": self.skippedChunkCount,
            "trimmed_total": self.trimmedChunkCount,
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

  /// Estimate audio milliseconds currently queued in playerNode (scheduled but not yet played).
  private func estimateQueuedAudioMs() -> Int {
    guard let lastRender = playerNode.lastRenderTime,
      let playerTime = playerNode.playerTime(forNodeTime: lastRender)
    else { return 0 }
    // playerTime.sampleTime increases as audio is consumed.
    // We can compute remaining queued as the difference between scheduled samples
    // and consumed samples. Without tracking scheduled, return -1 to indicate unknown.
    // Approximation: nothing can be queried directly. Return engine.isRunning as proxy.
    let _ = playerTime
    return -1  // not directly queryable on AVAudioPlayerNode
  }

  // MARK: - Pre-processing pipeline

  /// Pre-process a mono PCM chunk through NSNet2 on a serial background queue.
  /// The result is stored for later playback via `playChunksUpTo`.
  public func preprocessChunk(samples: [Float], timestampMs: Double) {
    let receivedAt = CFAbsoluteTimeGetCurrent()
    SawtunaaMetric.emit(
      "chunk_preprocess_start",
      [
        "chunk_ts": Int(timestampMs),
        "samples": samples.count,
      ])
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
      let t0 = CFAbsoluteTimeGetCurrent()
      let processed = nsnet2.process(samples)
      let nsnet2Ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)

      guard
        let buffer = AVAudioPCMBuffer(
          pcmFormat: self.format,
          frameCapacity: AVAudioFrameCount(processed.count)
        )
      else { return }
      buffer.frameLength = AVAudioFrameCount(processed.count)
      let ch0 = buffer.floatChannelData![0]
      for i in 0..<processed.count { ch0[i] = processed[i] }

      let totalMs = Int((CFAbsoluteTimeGetCurrent() - receivedAt) * 1000)
      DispatchQueue.main.async {
        self.processedChunks.append((timestampMs: timestampMs, buffer: buffer))
        self.preprocessCount += 1
        SawtunaaMetric.emit(
          "chunk_preprocess_done",
          [
            "chunk_ts": Int(timestampMs),
            "nsnet2_ms": nsnet2Ms,
            "total_ms": totalMs,
            "frames": processed.count,
            "queue_depth": self.processedChunks.count,
            "preprocess_idx": self.preprocessCount,
          ])
      }
    }
  }

  /// Play all pre-processed chunks whose timestamp <= upToMs.
  /// Trims chunks that start before upToMs to stay in sync with video.
  public func playChunksUpTo(_ upToMs: Double) {
    if !isRunning {
      start()
      guard isRunning else {
        SawtunaaMetric.emit("play_chunks_engine_failed", ["upTo_ms": Int(upToMs)])
        return
      }
    }

    let initialQueueDepth = processedChunks.count
    var playedThisCall = 0

    while !processedChunks.isEmpty && processedChunks[0].timestampMs <= upToMs {
      let chunk = processedChunks.removeFirst()
      let chunkDurationMs = Double(chunk.buffer.frameLength) / 48.0
      let chunkEndMs = chunk.timestampMs + chunkDurationMs

      // Skip chunks entirely in the past (ended > 200ms ago)
      if chunkEndMs < upToMs - 200 {
        skippedChunkCount += 1
        SawtunaaMetric.emit(
          "chunk_skip_old",
          [
            "chunk_ts": Int(chunk.timestampMs),
            "chunk_end_ms": Int(chunkEndMs),
            "video_ms": Int(upToMs),
            "lag_ms": Int(upToMs - chunkEndMs),
          ])
        continue
      }

      // Trim chunk if it starts significantly before current video time
      if chunk.timestampMs < upToMs - 100 {
        let skipMs = upToMs - chunk.timestampMs
        let skipSamples = Int(skipMs * 48)
        let totalFrames = Int(chunk.buffer.frameLength)
        if skipSamples > 0 && skipSamples < totalFrames {
          let remaining = totalFrames - skipSamples
          if let trimmed = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(remaining)
          ) {
            trimmed.frameLength = AVAudioFrameCount(remaining)
            let src = chunk.buffer.floatChannelData![0]
            let dst = trimmed.floatChannelData![0]
            for i in 0..<remaining { dst[i] = src[skipSamples + i] }
            playerNode.scheduleBuffer(trimmed)
            playedChunkCount += 1
            trimmedChunkCount += 1
            playedThisCall += 1
            SawtunaaMetric.emit(
              "chunk_play_trim",
              [
                "chunk_ts": Int(chunk.timestampMs),
                "video_ms": Int(upToMs),
                "skip_ms": Int(skipMs),
                "remaining_samples": remaining,
                "play_idx": playedChunkCount,
              ])
            if firstChunkPlayedAt == nil {
              firstChunkPlayedAt = Int(CFAbsoluteTimeGetCurrent() * 1000)
              SawtunaaMetric.emit(
                "first_chunk_played",
                [
                  "chunk_ts": Int(chunk.timestampMs),
                  "video_ms": Int(upToMs),
                  "trimmed": true,
                ])
            }
            continue
          }
        }
      }

      // Play full chunk
      playerNode.scheduleBuffer(chunk.buffer)
      playedChunkCount += 1
      playedThisCall += 1
      SawtunaaMetric.emit(
        "chunk_play_full",
        [
          "chunk_ts": Int(chunk.timestampMs),
          "video_ms": Int(upToMs),
          "frames": chunk.buffer.frameLength,
          "play_idx": playedChunkCount,
          "lag_ms": Int(upToMs - chunk.timestampMs),
        ])
      if firstChunkPlayedAt == nil {
        firstChunkPlayedAt = Int(CFAbsoluteTimeGetCurrent() * 1000)
        SawtunaaMetric.emit(
          "first_chunk_played",
          [
            "chunk_ts": Int(chunk.timestampMs),
            "video_ms": Int(upToMs),
            "trimmed": false,
          ])
      }
    }

    // Detect underrun: playAt called but nothing to play AND we've played before
    if playedThisCall == 0 && playedChunkCount > 0 && processedChunks.isEmpty {
      SawtunaaMetric.emit(
        "underrun",
        [
          "video_ms": Int(upToMs),
          "played_total": playedChunkCount,
        ])
    }

    let _ = initialQueueDepth
  }

  public func pausePlayback() {
    guard isRunning else { return }
    playerNode.pause()
    SawtunaaMetric.emit("pause_audio", [:])
  }

  public func resumePlayback() {
    guard isRunning else { return }
    playerNode.play()
    SawtunaaMetric.emit("resume_audio", [:])
  }

  /// Clear all pre-processed chunks and reset NSNet2 state (on seek or new video).
  public func clearChunks() {
    let prev = processedChunks.count
    processedChunks.removeAll()
    preprocessCount = 0
    playedChunkCount = 0
    skippedChunkCount = 0
    trimmedChunkCount = 0
    firstChunkPlayedAt = nil
    preprocessQueue.async { [weak self] in
      self?.nsnet2?.reset()
    }
    SawtunaaMetric.emit("clear_chunks", ["dropped": prev])
  }
}
