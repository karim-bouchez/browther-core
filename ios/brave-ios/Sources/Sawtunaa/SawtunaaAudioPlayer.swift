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
  // Cache of processed chunks, mirroring the contents of YouTube's MSE
  // SourceBuffer. Chunks are kept after being scheduled so we can re-play
  // them on seek without depending on YouTube to re-deliver via appendBuffer.
  // Sorted by timestampMs.
  private var audioCache: [(timestampMs: Double, durationMs: Double, buffer: AVAudioPCMBuffer)] =
    []
  private var preprocessCount = 0
  private var isPausedFlag = false
  // Anchors used to compute audio playback position in source time
  private var anchorAudioSampleTime: AVAudioFramePosition?
  private var anchorSourceMs: Double = 0
  private var lastVideoUpToMs: Double = 0
  private var playedChunkCount = 0
  private var skippedChunkCount = 0
  private var trimmedChunkCount = 0
  private var gapFillCount = 0
  private var firstChunkPlayedAt: Int?  // session-relative ms
  // Tracks the source-time end of the last scheduled buffer (in ms relative
  // to the source timeline). Used to detect timestamp gaps between
  // consecutive chunks and fill them with silence so audio stays in sync.
  private var lastScheduledEndMs: Double = 0
  // Cursor in the audio cache: only chunks with timestampMs > this value are
  // eligible for scheduling. Strictly increasing per chunk to prevent the
  // same chunk from being re-scheduled (esp. for chunks shorter than the gap
  // tolerance, which would re-match against a duration-based cursor).
  private var scheduledCursorTsMs: Double = -1
  // Epoch counter: incremented on every clearChunks (page reset / new video).
  // preprocessChunk captures the current epoch when enqueued and the result
  // is dropped if the epoch has changed by the time NSNet2 finishes — this
  // avoids inserting stale chunks from a previous page into the fresh cache.
  private var epoch: UInt64 = 0

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
        let audioSrcMs = self.currentAudioSourceMs()
        let videoSrcMs = self.lastVideoUpToMs - 100
        let driftMs: Int = audioSrcMs.map { Int(videoSrcMs - $0) } ?? -99999

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

        SawtunaaMetric.emit(
          "engine_state",
          [
            "engine_running": self.engine.isRunning,
            "player_playing": self.playerNode.isPlaying,
            "cache_size": self.audioCache.count,
            "cache_first_ts": cacheFirstTs,
            "cache_last_end": cacheLastEnd,
            "cache_holes": holes,
            "cache_hole_ms": holeMs,
            "audio_queued_ms": queuedMs,
            "audio_src_ms": audioSrcMs.map { Int($0) } ?? -1,
            "video_src_ms": Int(videoSrcMs),
            "drift_ms": driftMs,
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
  /// Not directly queryable on AVAudioPlayerNode without tracking scheduled samples manually.
  private func estimateQueuedAudioMs() -> Int { -1 }

  /// Anchor the audio playback timeline against a source-time origin.
  /// Used to compute the source-time position of the audio currently coming
  /// out of the speakers, and thus measure drift vs video.currentTime.
  private func anchorPlayback(sourceMs: Double) {
    guard anchorAudioSampleTime == nil else { return }
    guard let lastRender = playerNode.lastRenderTime,
      let playerTime = playerNode.playerTime(forNodeTime: lastRender)
    else { return }
    // Use playerTime (player-relative samples), not nodeTime (output-device samples).
    anchorAudioSampleTime = playerTime.sampleTime
    anchorSourceMs = sourceMs
  }

  /// Compute the source-time position of audio currently being rendered.
  /// Returns nil if the playback hasn't been anchored yet.
  private func currentAudioSourceMs() -> Double? {
    guard let anchor = anchorAudioSampleTime,
      let lastRender = playerNode.lastRenderTime,
      let playerTime = playerNode.playerTime(forNodeTime: lastRender)
    else { return nil }
    let elapsedSamples = playerTime.sampleTime - anchor
    return anchorSourceMs + Double(elapsedSamples) / 48.0
  }

  // MARK: - Pre-processing pipeline

  /// Pre-process a mono PCM chunk through NSNet2 on a serial background queue.
  /// The result is stored for later playback via `playChunksUpTo`.
  /// While paused, drop incoming chunks: the player node keeps its existing
  /// queue (~5s of audio thanks to lookahead cap), so on resume the audio is
  /// already in sync with the video position. Newer chunks would only push
  /// the player ahead of video time when it resumes.
  public func preprocessChunk(samples: [Float], timestampMs: Double) {
    if isPausedFlag {
      SawtunaaMetric.emit(
        "preprocess_drop_paused", ["chunk_ts": Int(timestampMs)])
      return
    }
    let receivedAt = CFAbsoluteTimeGetCurrent()
    let chunkEpoch = epoch
    SawtunaaMetric.emit(
      "chunk_preprocess_start",
      [
        "chunk_ts": Int(timestampMs),
        "samples": samples.count,
        "epoch": Int(chunkEpoch),
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
      let durationMs = Double(processed.count) / 48.0
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
        let entry = (timestampMs: timestampMs, durationMs: durationMs, buffer: buffer)
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
            "nsnet2_ms": nsnet2Ms,
            "total_ms": totalMs,
            "frames": processed.count,
            "cache_size": self.audioCache.count,
            "preprocess_idx": self.preprocessCount,
          ])
      }
    }
  }

  /// Play pre-processed chunks, keeping audio in sync with video time.
  ///
  /// Strategy:
  /// - **Lookahead cap** (5s): only schedule chunks whose timestamp is within
  ///   the next ~5s of video time. Prevents the player queue from accumulating
  ///   way ahead of video — which would cause the audio to play through and
  ///   then go silent during YouTube's burst gaps, then resume out of sync.
  /// - **Skip too-old chunks**: any chunk whose end is >200ms behind video.
  /// - **Trim partially-old chunks**: if a chunk starts before video time,
  ///   skip the early samples to resync.
  /// - **Fill timestamp gaps with silence**: if YouTube emits non-contiguous
  ///   chunks, insert silence so audio doesn't drift ahead of video.
  private static let lookaheadMs: Double = 5000

  public func playChunksUpTo(_ upToMs: Double) {
    if !isRunning {
      start()
      guard isRunning else {
        SawtunaaMetric.emit("play_chunks_engine_failed", ["upTo_ms": Int(upToMs)])
        return
      }
    }

    lastVideoUpToMs = upToMs

    // Cursor-based scheduling over the persistent audio cache:
    // a chunk is a candidate if timestampMs > scheduledCursorTsMs (strict).
    // After scheduling, scheduledCursorTsMs is set to that chunk's ts so it
    // can't be picked again. On seek, the cursor is reset so the cache is
    // re-traversed from the seek target.
    while let nextIdx = audioCache.firstIndex(where: {
      $0.timestampMs > scheduledCursorTsMs
    }) {
      let next = audioCache[nextIdx]
      let nextTs = next.timestampMs
      let nextEnd = nextTs + next.durationMs

      // Wait if next chunk is too far in the future (lookahead cap).
      if nextTs > upToMs + Self.lookaheadMs {
        return
      }

      let isFirstChunk = (playedChunkCount == 0)

      // First chunk silence-lead: if the chunk is in the future (init/seek),
      // insert silence to align audio_start with video.currentTime.
      if isFirstChunk && nextTs > upToMs + 100 {
        let silentMs = nextTs - upToMs
        if silentMs > 2000 {
          return  // too far ahead, wait
        }
        let silentFrames = Int(silentMs * 48)
        if silentFrames > 0,
          let silence = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(silentFrames))
        {
          silence.frameLength = AVAudioFrameCount(silentFrames)
          playerNode.scheduleBuffer(silence)
          anchorPlayback(sourceMs: upToMs)
          lastScheduledEndMs = nextTs
          SawtunaaMetric.emit(
            "first_chunk_silence_lead",
            ["silent_ms": Int(silentMs), "video_ms": Int(upToMs), "next_ts": Int(nextTs)])
          // Fall through to schedule the chunk in this same iteration
        }
      }

      // Skip if entirely in the past — advance cursor without removing from cache
      if nextEnd < upToMs - 200 {
        skippedChunkCount += 1
        SawtunaaMetric.emit(
          "chunk_skip_old",
          [
            "chunk_ts": Int(nextTs),
            "video_ms": Int(upToMs),
            "lag_ms": Int(upToMs - nextEnd),
          ])
        scheduledCursorTsMs = nextTs  // advance cursor past this chunk
        continue
      }

      // Trim if starts significantly before video time
      if nextTs < upToMs - 100 {
        let skipMs = upToMs - nextTs
        let skipSamples = Int(skipMs * 48)
        let totalFrames = Int(next.buffer.frameLength)
        if skipSamples > 0 && skipSamples < totalFrames,
          let trimmed = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames - skipSamples))
        {
          let remaining = totalFrames - skipSamples
          trimmed.frameLength = AVAudioFrameCount(remaining)
          let src = next.buffer.floatChannelData![0]
          let dst = trimmed.floatChannelData![0]
          for i in 0..<remaining { dst[i] = src[skipSamples + i] }
          playerNode.scheduleBuffer(trimmed)
          playedChunkCount += 1
          trimmedChunkCount += 1
          lastScheduledEndMs = nextEnd
          scheduledCursorTsMs = nextTs
          if firstChunkPlayedAt == nil {
            firstChunkPlayedAt = Int(CFAbsoluteTimeGetCurrent() * 1000)
            anchorPlayback(sourceMs: upToMs)
            SawtunaaMetric.emit(
              "first_chunk_played",
              [
                "chunk_ts": Int(nextTs),
                "video_ms": Int(upToMs),
                "trimmed": true,
                "skip_ms": Int(skipMs),
              ])
          } else {
            SawtunaaMetric.emit(
              "chunk_play_trim",
              [
                "chunk_ts": Int(nextTs),
                "video_ms": Int(upToMs),
                "skip_ms": Int(skipMs),
              ])
          }
          continue
        }
      }

      // Fill timestamp gap with silence (only after first chunk)
      if playedChunkCount > 0 {
        let gapMs = nextTs - lastScheduledEndMs
        if gapMs > 30 && gapMs < 30 * 1000 {
          let silenceFrames = Int(gapMs * 48)
          if let silence = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(silenceFrames))
          {
            silence.frameLength = AVAudioFrameCount(silenceFrames)
            playerNode.scheduleBuffer(silence)
            gapFillCount += 1
            SawtunaaMetric.emit(
              "gap_fill",
              [
                "gap_ms": Int(gapMs),
                "next_ts": Int(nextTs),
                "last_end_ms": Int(lastScheduledEndMs),
                "fill_count": gapFillCount,
              ])
            lastScheduledEndMs = nextTs
          }
        }
      }

      // Schedule the chunk (full)
      playerNode.scheduleBuffer(next.buffer)
      playedChunkCount += 1
      lastScheduledEndMs = nextEnd
      scheduledCursorTsMs = nextTs
      if firstChunkPlayedAt == nil {
        firstChunkPlayedAt = Int(CFAbsoluteTimeGetCurrent() * 1000)
        anchorPlayback(sourceMs: nextTs)
        SawtunaaMetric.emit(
          "first_chunk_played",
          [
            "chunk_ts": Int(nextTs),
            "video_ms": Int(upToMs),
            "trimmed": false,
          ])
      } else {
        SawtunaaMetric.emit(
          "chunk_play_full",
          [
            "chunk_ts": Int(nextTs),
            "video_ms": Int(upToMs),
            "frames": next.buffer.frameLength,
            "play_idx": playedChunkCount,
          ])
      }
    }
  }

  public func pausePlayback() {
    guard isRunning else { return }
    playerNode.pause()
    isPausedFlag = true
    SawtunaaMetric.emit("pause_audio", [:])
  }

  public func resumePlayback() {
    guard isRunning else { return }
    isPausedFlag = false
    // PlayerNode resumes its existing queue (still in sync with video time
    // since we dropped incoming chunks during pause and didn't add new ones).
    playerNode.play()
    SawtunaaMetric.emit("resume_audio", [:])
  }

  /// Full reset: drop the entire audio cache and reset all state.
  /// Used on init segment (new video / page reload), NOT on seek (use seekTo).
  public func clearChunks() {
    let prev = audioCache.count
    epoch &+= 1  // invalidate any in-flight preprocess from a prior session
    audioCache.removeAll()
    if isRunning {
      playerNode.stop()
      playerNode.play()
    }
    preprocessCount = 0
    playedChunkCount = 0
    skippedChunkCount = 0
    trimmedChunkCount = 0
    gapFillCount = 0
    lastScheduledEndMs = 0
    scheduledCursorTsMs = -1
    firstChunkPlayedAt = nil
    anchorAudioSampleTime = nil
    anchorSourceMs = 0
    isPausedFlag = false
    lastVideoUpToMs = 0
    preprocessQueue.async { [weak self] in
      self?.nsnet2?.reset()
    }
    SawtunaaMetric.emit(
      "clear_chunks",
      ["dropped_cache": prev, "epoch": Int(epoch)])
  }

  /// Seek to a new video position. Keeps the audio cache (so we can re-play
  /// chunks already processed for the seek target if YouTube doesn't re-deliver
  /// them via appendBuffer). Flushes the player node and resets the playback
  /// state so the next playChunksUpTo treats it as a fresh start.
  public func seekTo(toMs: Double) {
    if isRunning {
      playerNode.stop()
      playerNode.play()
    }
    // Reset playback state but keep the cache
    playedChunkCount = 0
    skippedChunkCount = 0
    trimmedChunkCount = 0
    gapFillCount = 0
    firstChunkPlayedAt = nil
    anchorAudioSampleTime = nil
    anchorSourceMs = 0
    // Position cursors just before toMs so chunks at toMs+ become candidates
    lastScheduledEndMs = max(0, toMs - 100)
    scheduledCursorTsMs = max(-1, toMs - 1)
    // Reset NSNet2 state (the GRU continuity is broken anyway by the seek)
    preprocessQueue.async { [weak self] in
      self?.nsnet2?.reset()
    }
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
