// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Basarunaa
import Foundation
import OSLog
import Preferences
import Shared
import UIKit
import Web
import WebKit

protocol BasarunaaScriptHandlerDelegate: AnyObject {
  func basarunaaDidActivate(tab: (any TabState)?)
  func basarunaaDidApplyBlur(tab: (any TabState)?, imageCount: Int)
}

/// Decision returned to the JS after ML analysis.
private enum BlurDecision: String {
  case keep      // keep the default blur (target person detected, or analysis failed)
  case remove    // remove the default blur (no target detected)
}

/// V1 (étape A) : pas de ML. Le script JS injecté applique un `filter: blur()`
/// CSS sur toutes les `<img>` au pageload, et observe les images chargées
/// dynamiquement via `MutationObserver`. Ce handler gère uniquement le
/// lifecycle (page reset, métriques) en attendant le couplage ML de l'étape B.
class BasarunaaScriptHandler: TabContentScript {

  weak var delegate: BasarunaaScriptHandlerDelegate?
  private let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa.Handler")
  private var isActive = false

  /// Serial queue qui sérialise tout le traitement vidéo (base64 decode,
  /// demuxer feed, mutation de `videoSources`). Indispensable car
  /// `tab(message:replyHandler:)` est livré sur le main thread par WebKit ;
  /// faire le parsing EBML inline bloquerait le main → WebKit watchdog tue
  /// le process (cf. crash V2.b 2026-05-17, pattern parallèle au pipeline
  /// preprocessQueue de Sawtunaa).
  private let videoQueue = DispatchQueue(
    label: "com.devndin.browther.basarunaa.video", qos: .userInitiated)

  /// Lifetime state for one MSE video SourceBuffer wrapped on the JS side.
  /// V2.a : bridge bytes validé (canal JS→Swift restitue l'intégralité).
  /// V2.b : demuxer WebM streaming branché ⇒ on extrait les frames VP9 +
  ///        PTS. V2.c branchera VTDecompressionSession pour décoder.
  private struct VideoSourceState {
    let mime: String
    let demuxer: WebMDemuxer
    var totalBytes: Int = 0
    var chunkCount: Int = 0
    var frameCount: Int = 0
    var keyframeCount: Int = 0
    let createdAt: Date = Date()
  }
  private var videoSources: [Int: VideoSourceState] = [:]

  static let scriptName = "BasarunaaScript"
  static let scriptId = UUID().uuidString
  static let messageHandlerName = "\(scriptName)_\(messageUUID)"
  static let scriptSandbox: WKContentWorld = .page

  static let userScript: WKUserScript? = {
    guard let script = loadUserScript(named: scriptName) else { return nil }
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
    log.info("handler_init")
  }

  func tab(
    _ tab: some TabState,
    receivedScriptMessage message: WKScriptMessage,
    replyHandler: @escaping (Any?, String?) -> Void
  ) {
    defer { replyHandler(nil, nil) }

    if !verifyMessage(message: message) { return }

    guard let body = message.body as? [String: Any],
      let action = body["action"] as? String
    else { return }

    let data = body["data"] as? String ?? ""

    switch action {
    case "metric":
      log.info("[METRIC] \(data, privacy: .public)")

    case "log":
      log.info("[JS] \(data, privacy: .public)")

    case "scriptReady":
      if !isActive {
        isActive = true
        delegate?.basarunaaDidActivate(tab: tab)
      }
      log.info("script_ready url=\(data, privacy: .public)")

    case "blurApplied":
      // data = "<initialImageCount>"
      let count = Int(data) ?? 0
      delegate?.basarunaaDidApplyBlur(tab: tab, imageCount: count)
      log.info("blur_applied count=\(count, privacy: .public)")

    case "analyzeImage":
      // data = "<id>|<base64Jpeg>"
      guard let pipe = data.firstIndex(of: "|") else { return }
      let idStr = String(data[..<pipe])
      let b64 = String(data[data.index(after: pipe)...])
      guard let id = Int(idStr) else { return }
      let typeErasedTab: any TabState = tab
      Task.detached { [weak self] in
        await self?.processImage(id: id, base64: b64, tab: typeErasedTab)
      }

    case "pageReset":
      isActive = false
      videoQueue.async { [weak self] in
        self?.videoSources.removeAll()
      }
      log.info("page_reset url=\(data, privacy: .public)")

    case "videoSourceAdded":
      // data = "<sbId>|<mime>"
      let parts = data.split(separator: "|", maxSplits: 1)
      guard parts.count == 2, let sbId = Int(parts[0]) else {
        log.error("videoSourceAdded parse failed: \(data, privacy: .public)")
        return
      }
      let mime = String(parts[1])
      let weakLog = self.log
      videoQueue.async { [weak self] in
        let demuxer = WebMDemuxer(label: "sb\(sbId)")
        self?.videoSources[sbId] = VideoSourceState(mime: mime, demuxer: demuxer)
        weakLog.info("video_source_added sbId=\(sbId, privacy: .public) mime=\(mime, privacy: .public)")
      }

    case "videoSegment":
      // data = "<sbId>|<seq>|<ct_ms>|<base64>"
      // Le parsing du préfixe est rapide ; on délègue le base64 decode + le
      // demuxer feed à la videoQueue pour ne pas bloquer le main thread.
      let parts = data.split(separator: "|", maxSplits: 3)
      guard parts.count == 4,
        let sbId = Int(parts[0]),
        let seq = Int(parts[1]),
        let ctMs = Int(parts[2])
      else {
        log.error("videoSegment parse failed (parts=\(data.split(separator: "|").count, privacy: .public))")
        return
      }
      let b64 = String(parts[3])
      videoQueue.async { [weak self] in
        self?.processVideoSegment(sbId: sbId, seq: seq, ctMs: ctMs, b64: b64)
      }

    default:
      log.info("unknown_action=\(action, privacy: .public)")
    }
  }

  // MARK: - Video segment processing (videoQueue)

  /// Decode + demuxer feed un segment vidéo MSE. **Exclusivement appelé sur
  /// `videoQueue`** — `videoSources` n'a pas de protection multi-thread.
  private func processVideoSegment(sbId: Int, seq: Int, ctMs: Int, b64: String) {
    guard let bytes = Data(base64Encoded: b64) else {
      log.error("videoSegment base64 decode failed sbId=\(sbId, privacy: .public) seq=\(seq, privacy: .public)")
      return
    }
    guard var state = videoSources[sbId] else {
      log.error("videoSegment unknown sbId=\(sbId, privacy: .public)")
      return
    }
    state.totalBytes += bytes.count
    state.chunkCount += 1

    // Pousse au demuxer, récupère les frames VP9 nouvellement complètes.
    // Log clairsemé pour éviter la pression I/O (1ères 5 + 1 / 120 ≈ 4 s
    // à 30 fps).
    let frames = state.demuxer.feed(bytes)
    for frame in frames {
      state.frameCount += 1
      if frame.isKeyframe { state.keyframeCount += 1 }
      if state.frameCount <= 5 || state.frameCount % 120 == 0 {
        log.info(
          """
          webm_frame sbId=\(sbId, privacy: .public) n=\(state.frameCount, privacy: .public) \
          pts_ms=\(frame.ptsMs, privacy: .public) key=\(frame.isKeyframe, privacy: .public) \
          size=\(frame.data.count, privacy: .public)
          """
        )
      }
    }
    videoSources[sbId] = state

    // Log segment cumul : 5 premiers chunks + 1 / 50.
    if state.chunkCount <= 5 || state.chunkCount % 50 == 0 {
      log.info(
        """
        video_segment sbId=\(sbId, privacy: .public) seq=\(seq, privacy: .public) \
        chunks=\(state.chunkCount, privacy: .public) size=\(bytes.count, privacy: .public) \
        total=\(state.totalBytes, privacy: .public) frames=\(state.frameCount, privacy: .public) \
        key=\(state.keyframeCount, privacy: .public) ct_ms=\(ctMs, privacy: .public)
        """
      )
    }
  }

  // MARK: - ML coupling

  private func processImage(id: Int, base64: String, tab: any TabState) async {
    let start = Date()
    guard let imageData = Data(base64Encoded: base64),
      let uiImage = UIImage(data: imageData),
      let cgImage = uiImage.cgImage
    else {
      log.error("analyze[\(id, privacy: .public)] failed to decode base64")
      await reply(tab: tab, id: id, decision: .keep, persons: [], shouldBlurFlags: [], debugMode: "none", elapsedMs: 0)
      return
    }

    do {
      let result = try await BasarunaaPipeline.shared.analyze(image: cgImage)
      let mode = Preferences.Basarunaa.effectiveMode
      let debugMode = Preferences.Basarunaa.debugMode.value
      let isDebug = debugMode == "boxes" || debugMode == "debug"

      // Persons the active mode would normally blur. Reused in debug mode
      // as the per-person `shouldBlur` metadata so the overlay shows the
      // same blur the user would see in production (macOS POC parity).
      let (modeDecision, modePersonsToBlur) = decide(from: result.persons, mode: mode)

      let decision: BlurDecision
      let personsPayload: [DetectedPerson]
      let shouldBlurFlags: [Bool]
      if isDebug {
        // Debug overlay (POC parity): keep the per-person blur that the
        // active mode would apply, draw bboxes/labels on top. We send
        // *every* detected person plus a per-person `shouldBlur` flag —
        // JS composites blur first, overlay on top.
        decision = result.persons.isEmpty ? .remove : .keep
        personsPayload = result.persons
        let blurredBboxes = Set(modePersonsToBlur.map { bboxKey($0.bbox) })
        shouldBlurFlags = result.persons.map { blurredBboxes.contains(bboxKey($0.bbox)) }
      } else if result.isNsfw {
        // NSFW short-circuit: full-image blur regardless of mode. No per-person
        // payload — JS keeps the default full-image blur in place.
        decision = .keep
        personsPayload = []
        shouldBlurFlags = []
      } else {
        decision = modeDecision
        personsPayload = modePersonsToBlur
        shouldBlurFlags = Array(repeating: true, count: modePersonsToBlur.count)
      }
      let elapsedMs = Date().timeIntervalSince(start) * 1000
      log.info(
        """
        analyze[\(id, privacy: .public)] nsfw=\(result.isNsfw, privacy: .public) \
        persons=\(result.persons.count, privacy: .public) toBlur=\(modePersonsToBlur.count, privacy: .public) \
        mode=\(mode, privacy: .public) debug=\(debugMode, privacy: .public) → \(decision.rawValue, privacy: .public) \
        (\(String(format: "%.0f", elapsedMs), privacy: .public)ms)
        """
      )
      await reply(
        tab: tab,
        id: id,
        decision: decision,
        persons: personsPayload,
        shouldBlurFlags: shouldBlurFlags,
        debugMode: debugMode,
        elapsedMs: elapsedMs
      )

      // Phase 2 (POC parity) — fire NSFW check in the background. Only
      // notify JS when the result is positive ; the per-person blur is
      // already applied and that's the right default on safe images.
      let weakLog = self.log
      Task.detached { [weak tab] in
        do {
          let nsfwResult = try await BasarunaaPipeline.shared.checkNsfw(image: cgImage)
          if nsfwResult.isNsfw, let tab {
            await Self.applyNsfwOverlay(
              tab: tab,
              id: id,
              score: nsfwResult.score ?? 1.0,
              log: weakLog
            )
          }
        } catch {
          weakLog.error("checkNsfw[\(id, privacy: .public)] failed: \(String(describing: error), privacy: .public)")
        }
      }
    } catch {
      log.error("analyze[\(id, privacy: .public)] failed: \(String(describing: error), privacy: .public)")
      await reply(tab: tab, id: id, decision: .keep, persons: [], shouldBlurFlags: [], debugMode: "none", elapsedMs: 0)
    }
  }

  /// Phase 2 notification — fires `window.__basarunaaApplyNsfw(id, score)`
  /// on the page so the JS can replace the per-person blur with a full
  /// image blur (or any UI it wants). Called only when NSFW is positive.
  @MainActor
  private static func applyNsfwOverlay(
    tab: any TabState,
    id: Int,
    score: Double,
    log: Logger
  ) async {
    do {
      _ = try await tab.evaluateJavaScript(
        functionName: "window.__basarunaaApplyNsfw",
        args: [id, score],
        contentWorld: BasarunaaScriptHandler.scriptSandbox
      )
    } catch {
      log.error(
        "applyNsfwOverlay failed for id=\(id, privacy: .public): \(String(describing: error), privacy: .public)"
      )
    }
  }

  /// Stable string key for a person's body bbox — used to match persons
  /// across `decide()` output and the full detected list when building the
  /// per-person `shouldBlur` flags in debug mode.
  private func bboxKey(_ rect: CGRect) -> String {
    "\(rect.minX),\(rect.minY),\(rect.maxX),\(rect.maxY)"
  }

  /// Decision policy + which persons trigger the blur (POC modes).
  ///
  /// - `blur-all`    : every detected person is blurred (bbox + keypoints
  ///                   sent so JS composites a per-person mask).
  /// - `blur-male`   : only persons confidently classified as male are
  ///                   blurred. Unknown gender stays visible.
  /// - `blur-female` : female-classified persons, plus those with
  ///                   `gender == nil` (POC's "safer default to keep" — body
  ///                   detected but face too small/blurry / classification
  ///                   below the `gender-certainty` threshold).
  private func decide(
    from persons: [DetectedPerson],
    mode: String
  ) -> (BlurDecision, [DetectedPerson]) {
    if persons.isEmpty { return (.remove, []) }
    let toBlur: [DetectedPerson]
    switch mode {
    case "blur-all":
      toBlur = persons
    case "blur-male":
      toBlur = persons.filter { $0.gender == .male }
    case "blur-female", _:
      toBlur = persons.filter { p in
        if p.gender == nil { return true }      // safer default to keep
        return p.gender == .female
      }
    }
    return toBlur.isEmpty ? (.remove, []) : (.keep, toBlur)
  }

  @MainActor
  private func reply(
    tab: any TabState,
    id: Int,
    decision: BlurDecision,
    persons: [DetectedPerson],
    shouldBlurFlags: [Bool],
    debugMode: String,
    elapsedMs: Double
  ) async {
    do {
      let serialized = serialize(persons: persons, shouldBlurFlags: shouldBlurFlags)
      _ = try await tab.evaluateJavaScript(
        functionName: "window.__basarunaaApply",
        args: [id, decision.rawValue, serialized, debugMode, elapsedMs],
        contentWorld: Self.scriptSandbox
      )
    } catch {
      log.error(
        "evaluateJavaScript failed for id=\(id, privacy: .public): \(String(describing: error), privacy: .public)"
      )
    }
  }

  /// Compact representation for the JS side. Sends per-person :
  /// - `bbox` `[x1, y1, x2, y2]` (POC convention)
  /// - `keypoints` 17 COCO points as `[x, y, conf]` (so JS rebuilds the
  ///   body polygon mask à la POC macOS `buildBodyPolygon`)
  /// - `faceBbox` (if any)
  /// - `gender` + `genderConfidence` (if classified)
  /// - `bodyConfidence` (YOLO score)
  /// - `shouldBlur` — set in debug mode for the persons the active mode
  ///   would normally blur, so JS composites the blur and draws the
  ///   overlay on top (POC parity).
  private func serialize(persons: [DetectedPerson], shouldBlurFlags: [Bool]) -> [[String: Any]] {
    persons.enumerated().map { (idx, p) in
      let x1 = p.bbox.minX
      let y1 = p.bbox.minY
      let x2 = p.bbox.maxX
      let y2 = p.bbox.maxY
      let kps = p.keypoints.map { kp -> [Double] in
        [kp.point.x, kp.point.y, kp.confidence]
      }
      var dict: [String: Any] = [
        "bbox": [x1, y1, x2, y2] as [Double],
        "keypoints": kps,
        "bodyConfidence": p.bodyConfidence,
        "shouldBlur": idx < shouldBlurFlags.count ? shouldBlurFlags[idx] : true,
        "isSyntheticBody": p.isSyntheticBody,
        "classifierUsed": p.classifierUsed,
      ]
      if let face = p.faceBbox {
        dict["faceBbox"] = [face.minX, face.minY, face.maxX, face.maxY] as [Double]
      }
      if let g = p.gender {
        dict["gender"] = g.rawValue
      }
      if let gc = p.genderConfidence {
        dict["genderConfidence"] = gc
      }
      if let fp = p.faceProb {
        dict["facePFemale"] = fp.female
        dict["facePMale"] = fp.male
      }
      if let bp = p.bodyProb {
        dict["bodyPFemale"] = bp.female
        dict["bodyPMale"] = bp.male
      }
      if let img = p.faceCropImage, let dataUrl = encodeCGImagePNG(img) {
        dict["faceCropDataUrl"] = dataUrl
      }
      if let img = p.bodyCropImage, let dataUrl = encodeCGImagePNG(img) {
        dict["bodyCropDataUrl"] = dataUrl
      }
      return dict
    }
  }

  /// Encode a CGImage as a `data:image/png;base64,...` URL. Returns nil
  /// if encoding fails. Used to ship the debug crops to the JS overlay.
  private func encodeCGImagePNG(_ image: CGImage) -> String? {
    let uiImage = UIImage(cgImage: image)
    guard let data = uiImage.pngData() else { return nil }
    return "data:image/png;base64,\(data.base64EncodedString())"
  }

  deinit {
    log.info("handler_deinit")
  }
}
