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

  /// PTS (en ms média) de la dernière frame analysée, par `videoId` côté JS.
  /// Permet un échantillonnage 1 / s indépendant du framerate du `<video>`.
  /// Sur main thread (handler delivery) — pas de lock nécessaire.
  /// Pivot V2 (2026-05-17) : VTDecompressionSession + VP9 est bloqué par
  /// un entitlement Apple privé ⇒ on récupère les pixels rendus côté JS via
  /// `canvas.drawImage(video)` puis on bridge en JPEG.
  private var lastAnalyzedAtByVideo: [Int: Int64] = [:]
  private let analyzeIntervalMs: Int64 = 1000

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
      lastAnalyzedAtByVideo.removeAll()
      log.info("page_reset url=\(data, privacy: .public)")

    case "videoFrame":
      // data = "<videoId>|<ct_ms>|<w>|<h>|<base64Jpeg>"
      // Le base64 peut être gros (10+ KB) → on évite toute opération inutile
      // sur le data string en main thread (split est O(N)). On récupère
      // l'en-tête en cherchant les pipes à la main, puis on extrait le b64
      // en slice de String.
      var pipePositions: [String.Index] = []
      pipePositions.reserveCapacity(4)
      var idx = data.startIndex
      while pipePositions.count < 4, let next = data[idx...].firstIndex(of: "|") {
        pipePositions.append(next)
        idx = data.index(after: next)
      }
      guard pipePositions.count == 4 else {
        log.error("videoFrame parse failed (no 4 pipes)")
        return
      }
      let v1Start = data.startIndex
      let v1End = pipePositions[0]
      let v2Start = data.index(after: pipePositions[0])
      let v2End = pipePositions[1]
      let v3Start = data.index(after: pipePositions[1])
      let v3End = pipePositions[2]
      let v4Start = data.index(after: pipePositions[2])
      let v4End = pipePositions[3]
      let v5Start = data.index(after: pipePositions[3])
      guard let videoId = Int(data[v1Start..<v1End]),
        let ctMs = Int64(data[v2Start..<v2End]),
        let w = Int(data[v3Start..<v3End]),
        let h = Int(data[v4Start..<v4End])
      else {
        log.error("videoFrame header parse failed")
        return
      }
      // Skip si la dernière analyse pour ce videoId est trop récente. On
      // pose `.max` à l'enqueue pour que les frames qui arrivent pendant
      // l'analyse soient drop, puis on remet le PTS réel à la fin. Garantit
      // une seule Task en vol par <video> et évite l'accumulation.
      //
      // ⚠️ Ne *jamais* utiliser `?? Int64.min` ici : `ctMs - Int64.min`
      // overflow Int64 et Swift trappe via precondition (EXC_BREAKPOINT,
      // crashes 2026-05-17 19:21 / 19:36). On guarde explicitement le cas
      // "1ère frame pour ce videoId" par if-let.
      if let last = lastAnalyzedAtByVideo[videoId] {
        if last == .max { return }
        if ctMs - last < analyzeIntervalMs { return }
      }
      lastAnalyzedAtByVideo[videoId] = .max
      let b64 = String(data[v5Start...])
      let typeErasedTab: any TabState = tab
      Task.detached { [weak self] in
        await self?.processVideoFrame(
          videoId: videoId, ctMs: ctMs, width: w, height: h, b64: b64,
          tab: typeErasedTab
        )
      }

    default:
      log.info("unknown_action=\(action, privacy: .public)")
    }
  }

  // MARK: - Video frame processing (pivot D)

  /// Décompresse un JPEG capturé par JS (`canvas.drawImage(video)`), invoque
  /// `BasarunaaPipeline.analyze`. V3 ajoutera le retour des polygones de
  /// blur au JS pour overlay.
  private func processVideoFrame(
    videoId: Int, ctMs: Int64, width: Int, height: Int, b64: String,
    tab: any TabState
  ) async {
    let start = Date()
    defer {
      // Toujours réouvrir le slot pour ce videoId : on remet `ctMs` réel
      // pour que les frames suivantes soient throttlées par `analyzeIntervalMs`.
      Task { @MainActor [weak self] in
        self?.lastAnalyzedAtByVideo[videoId] = ctMs
      }
    }
    guard let jpegData = Data(base64Encoded: b64) else {
      log.error("videoFrame base64 decode failed videoId=\(videoId, privacy: .public)")
      return
    }
    guard let uiImage = UIImage(data: jpegData), let cgImage = uiImage.cgImage else {
      log.error(
        "videoFrame jpeg decode failed videoId=\(videoId, privacy: .public) bytes=\(jpegData.count, privacy: .public)"
      )
      return
    }
    do {
      let result = try await BasarunaaPipeline.shared.analyze(image: cgImage)
      let elapsedMs = Date().timeIntervalSince(start) * 1000
      log.info(
        """
        video_analyzed videoId=\(videoId, privacy: .public) ct_ms=\(ctMs, privacy: .public) \
        w=\(width, privacy: .public) h=\(height, privacy: .public) \
        persons=\(result.persons.count, privacy: .public) nsfw=\(result.isNsfw, privacy: .public) \
        elapsed=\(String(format: "%.0f", elapsedMs), privacy: .public)ms
        """
      )
      _ = tab  // V3 utilisera tab pour pousser les polygones à JS
    } catch {
      log.error(
        "videoFrame analyze failed videoId=\(videoId, privacy: .public): \(String(describing: error), privacy: .public)"
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
