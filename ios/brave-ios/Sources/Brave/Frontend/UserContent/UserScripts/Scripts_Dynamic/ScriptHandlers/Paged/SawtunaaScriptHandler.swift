// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences
import Sawtunaa
import Shared
import Web
import WebKit

protocol SawtunaaScriptHandlerDelegate: AnyObject {
  func sawtunaaDidActivate(tab: (any TabState)?)
  func sawtunaaDidDeactivate(tab: (any TabState)?)
}

class SawtunaaScriptHandler: TabContentScript {

  weak var delegate: SawtunaaScriptHandlerDelegate?
  private var audioPlayer: SawtunaaAudioPlayer?
  private var isActive = false

  static let scriptName = "SawtunaaScript"
  static let scriptId = UUID().uuidString
  static let messageHandlerName = "\(scriptName)_\(messageUUID)"
  static let scriptSandbox: WKContentWorld = .page

  static let userScript: WKUserScript? = {
    // Load Opus decoder bundle first
    guard let opusSource = loadUserScript(named: "SawtunaaOpusDecoderBundle") else {
      return nil
    }
    guard var script = loadUserScript(named: scriptName) else {
      return nil
    }

    // Prepend Opus decoder (must be available before MSE interception)
    script = opusSource + "\n" + script

    return WKUserScript(
      source: secureScript(
        handlerName: messageHandlerName,
        securityToken: scriptId,
        script: script
      ),
      injectionTime: .atDocumentStart,
      forMainFrameOnly: true,
      in: scriptSandbox
    )
  }()

  init() {
    SawtunaaMetric.reset()
    SawtunaaMetric.emit("handler_init", [:])
    // Eager: create player + load NSNet2 model immediately, before any chunk arrives.
    // Avoids dropping early chunks during the model load latency.
    ensureAudioPlayer()
  }

  // MARK: - Lifecycle

  private func ensureAudioPlayer() {
    guard audioPlayer == nil else { return }
    SawtunaaMetric.emit("handler_create_player", [:])
    let player = SawtunaaAudioPlayer()

    if let modelPath = SawtunaaResources.nsnet2ModelPath {
      player.loadModel(path: modelPath)
    } else {
      SawtunaaMetric.emit("handler_model_not_found", [:])
    }

    audioPlayer = player
  }

  // MARK: - TabContentScript

  func tab(
    _ tab: some TabState,
    receivedScriptMessage message: WKScriptMessage,
    replyHandler: @escaping (Any?, String?) -> Void
  ) {
    defer { replyHandler(nil, nil) }

    if !verifyMessage(message: message) {
      return
    }

    guard let body = message.body as? [String: Any],
      let action = body["action"] as? String
    else {
      return
    }

    let data = body["data"] as? String ?? ""

    switch action {
    case "metric":
      // JS-side structured metric: forward as-is to stdout with [METRIC] prefix
      print("[METRIC] \(data)")

    case "log":
      // Plain text log from JS
      SawtunaaMetric.emit("js_log", ["msg": data])

    case "preprocess":
      ensureAudioPlayer()
      handlePreprocess(data: data)

    case "playAt":
      if let ms = Double(data) {
        if !isActive {
          isActive = true
          SawtunaaMetric.emit("handler_activated", ["first_video_ms": Int(ms)])
          delegate?.sawtunaaDidActivate(tab: tab)
        }
        audioPlayer?.playChunksUpTo(ms)
      } else {
        SawtunaaMetric.emit("handler_playat_invalid", ["data": data])
      }

    case "clearChunks":
      audioPlayer?.clearChunks()
      isActive = false
      SawtunaaMetric.emit("handler_clear_chunks", [:])

    case "seekTo":
      if let toMs = Double(data) {
        audioPlayer?.seekTo(toMs: toMs)
      }

    case "evictRange":
      // data = "startMs|endMs"
      let parts = data.split(separator: "|", maxSplits: 1)
      if parts.count == 2,
        let s = Double(parts[0]),
        let e = Double(parts[1])
      {
        audioPlayer?.evictRange(startMs: s, endMs: e)
      }

    case "syncRanges":
      // data = "start1|end1,start2|end2,..."
      let ranges: [(start: Double, end: Double)] = data.split(separator: ",").compactMap {
        rangeStr in
        let parts = rangeStr.split(separator: "|", maxSplits: 1)
        if parts.count == 2,
          let s = Double(parts[0]),
          let e = Double(parts[1])
        {
          return (start: s, end: e)
        }
        return nil
      }
      if !ranges.isEmpty {
        audioPlayer?.cleanOutsideBuffered(ranges: ranges)
      }

    case "pauseAudio":
      audioPlayer?.pausePlayback()

    case "resumeAudio":
      audioPlayer?.resumePlayback()

    default:
      SawtunaaMetric.emit("handler_unknown_action", ["action": action])
    }
  }

  // MARK: - Message Handling

  private func handlePreprocess(data: String) {
    // Format: "timestampMs|base64encodedFloat32Binary"
    guard let pipeIdx = data.firstIndex(of: "|") else { return }
    let tsStr = data[data.startIndex..<pipeIdx]
    let b64Str = data[data.index(after: pipeIdx)...]

    guard let timestampMs = Double(tsStr),
      timestampMs.isFinite,
      timestampMs >= 0,
      timestampMs < 24 * 3600 * 1000,  // < 24h, reject EBML parser overflows
      let rawData = Data(base64Encoded: String(b64Str))
    else {
      SawtunaaMetric.emit("preprocess_invalid_ts", ["raw": String(tsStr)])
      return
    }

    let floats = rawData.withUnsafeBytes { ptr -> [Float] in
      let bound = ptr.bindMemory(to: Float.self)
      return Array(bound)
    }

    audioPlayer?.preprocessChunk(samples: floats, timestampMs: timestampMs)
  }

  deinit {
    SawtunaaMetric.emit("handler_deinit", [:])
    audioPlayer?.stop()
  }
}
