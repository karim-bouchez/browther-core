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

  /// Le script est injecté sur toutes les pages, Sawtunaa allumé ou non (en
  /// veille quand il est éteint) : sans lui en place avant que la page crée
  /// son MediaSource, l'allumer exigerait un rechargement, et la vidéo
  /// repartirait de 0. Deux variantes figées selon l'état AU CHARGEMENT
  /// (`$<sawtunaa_enabled>`) : une page chargée Sawtunaa allumé doit couper la
  /// musique dès la première image, sans attendre un aller-retour natif. Les
  /// bascules suivantes passent par `setEnabled(_:in:)`, en direct.
  /// `UserScriptManager.loadScripts` relit cette propriété à chaque injection.
  static var userScript: WKUserScript? {
    Preferences.Sawtunaa.enabled.value ? userScriptOn : userScriptOff
  }
  private static let userScriptOn = makeUserScript(enabled: true)
  private static let userScriptOff = makeUserScript(enabled: false)

  private static func makeUserScript(enabled: Bool) -> WKUserScript? {
    // Load Opus decoder bundle first
    guard let opusSource = loadUserScript(named: "SawtunaaOpusDecoderBundle") else {
      return nil
    }
    guard let script = loadUserScript(named: scriptName) else {
      return nil
    }

    // Prepend Opus decoder (must be available before MSE interception)
    let source =
      opusSource + "\n"
      + script.replacingOccurrences(
        of: "$<sawtunaa_enabled>", with: enabled ? "true" : "false")

    return WKUserScript(
      source: secureScript(
        handlerName: messageHandlerName,
        securityToken: scriptId,
        script: source
      ),
      injectionTime: .atDocumentStart,
      forMainFrameOnly: true,
      in: scriptSandbox
    )
  }

  /// Allume / éteint Sawtunaa sur la page DÉJÀ chargée, sans la recharger.
  @MainActor
  static func setEnabled(_ enabled: Bool, in tab: some TabState) {
    Task { @MainActor in
      _ = try? await tab.evaluateJavaScript(
        functionName: "window.__sawtunaaSetEnabled",
        args: [enabled],
        contentWorld: scriptSandbox
      )
    }
  }

  init() {
    SawtunaaMetric.reset()
    SawtunaaMetric.emit("handler_init", [:])
    // ⚠️ Ni lecteur ni modèle ici : ce handler existe sur CHAQUE onglet,
    // Sawtunaa allumé ou non, et le modèle NSNet2 pèse ~25 Mo. Avant le
    // 2026-10-01, il était chargé à la création de chaque onglet. Il l'est
    // désormais à la première activation de l'onglet (`activate`, envoyé par
    // le JS dès l'allumage, pendant que le décodeur Opus démarre), puis reste
    // chargé pour que les bascules suivantes soient immédiates.
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

    case "activate":
      // Allumage en direct ou page chargée allumée : on lance le chargement du
      // modèle en parallèle du décodage Opus côté JS.
      ensureAudioPlayer()
      SawtunaaMetric.emit("handler_live_activate", [:])

    case "deactivate":
      // Extinction en direct : le JS a déjà rendu le son à la vidéo. On vide
      // le lecteur et on arrête le moteur (libère la sortie audio) ; le modèle
      // reste chargé pour un rallumage immédiat.
      audioPlayer?.clearChunks()
      audioPlayer?.stop()
      if isActive {
        isActive = false
        delegate?.sawtunaaDidDeactivate(tab: tab)
      }
      SawtunaaMetric.emit("handler_live_deactivate", [:])

    case "preprocess":
      ensureAudioPlayer()
      handlePreprocess(data: data)

    case "playAt":
      // data = "videoMs|sentAtWallMs|playbackRate" (video.currentTime brut,
      // sans avance : la latence de sortie est compensée côté natif).
      let parts = data.split(separator: "|").map { Double($0) }
      if let ms = parts.first ?? nil {
        if !isActive {
          isActive = true
          SawtunaaMetric.emit("handler_activated", ["first_video_ms": Int(ms)])
          delegate?.sawtunaaDidActivate(tab: tab)
        }
        let sentAt = parts.count > 1 ? parts[1] : nil
        let rate = (parts.count > 2 ? parts[2] : nil) ?? 1
        audioPlayer?.playChunksUpTo(videoMs: ms, sentAtMs: sentAt, rate: rate > 0 ? rate : 1)
      } else {
        SawtunaaMetric.emit("handler_playat_invalid", ["data": data])
      }

    case "clearChunks":
      audioPlayer?.clearChunks()
      isActive = false
      SawtunaaMetric.emit("handler_clear_chunks", [:])

    case "pageReset":
      // JS context restart (page refresh, bfcache restore, pagehide).
      // The Swift handler is bound to the tab so its audioCache and
      // playerNode queue would otherwise survive the navigation, leading
      // to "double audio" (old chunks playing on top of the new page).
      let prevActive = isActive
      audioPlayer?.clearChunks()
      isActive = false
      SawtunaaMetric.emit(
        "handler_page_reset",
        ["url": data, "was_active": prevActive])

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
