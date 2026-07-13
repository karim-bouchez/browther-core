// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Basarunaa
import BrowtherAnalytics
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
  func basarunaaDidEnterFakeFullscreen(tab: (any TabState)?)
  func basarunaaDidExitFakeFullscreen(tab: (any TabState)?)
}

/// V1 (étape A) : pas de ML. Le script JS injecté applique un `filter: blur()`
/// CSS sur toutes les `<img>` au pageload, et observe les images chargées
/// dynamiquement via `MutationObserver`. Ce handler gère uniquement le
/// lifecycle (page reset, métriques) en attendant le couplage ML de l'étape B.
///
/// Migration gender-v2n (2026-07-13) : le natif est désormais un **PUR
/// EXTRACTEUR** (cf. `private/docs/BASARUNAA_MOBILE_GENDER_V2N.md`). Il envoie
/// TOUTES les persons détectées (genre 3 classes + conf brute + keypoints) +
/// les prefs (mode/certitude) au JS. La **décision de flou vit dans
/// `core/policy.ts`**, appliquée côté bundle webkit — plus de `decide()` natif.
class BasarunaaScriptHandler: TabContentScript {

  weak var delegate: BasarunaaScriptHandlerDelegate?
  private let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa.Handler")
  private static let staticLog = Logger(subsystem: "com.devndin.browther", category: "Basarunaa.Handler")
  private var isActive = false

  /// Pivot V2 (2026-05-17) : VTDecompressionSession + VP9 est bloqué par un
  /// entitlement Apple privé ⇒ on récupère les pixels rendus côté JS via
  /// `canvas.drawImage(video)` puis on bridge en JPEG.
  ///
  /// V4 (2026-05-20) : retrait du throttle natif sur `analyzeIntervalMs`. Le
  /// JS implémente le scheduling two-tier (sentinel + YOLO event-driven),
  /// le natif ne doit pas mordre par-dessus — sinon les sendings JS sont
  /// drop silencieusement et `yoloInFlightById` reste figé (= flou freezé).
  /// Pour la même raison, `processVideoFrame` notifie *toujours* le JS, même
  /// en cas d'erreur de décodage / d'analyse.

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

    case "statsBlurred":
      // data = "<count>" — le JS a décidé (core/policy) et floute N persons.
      // Compteur cumulatif "personnes floutées" de la NTP (parité Sawtunaa).
      let count = Int(data) ?? 0
      if count > 0 {
        BrowtherStatsReporter.shared.addPersonsBlurred(count)
      }

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
      log.info("page_reset url=\(data, privacy: .public)")

    case "fullscreenEnter":
      delegate?.basarunaaDidEnterFakeFullscreen(tab: tab)
      log.info("fake_fullscreen_enter")

    case "fullscreenExit":
      delegate?.basarunaaDidExitFakeFullscreen(tab: tab)
      log.info("fake_fullscreen_exit")

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
      // V4 : pas de throttle natif — le JS pilote sa propre cadence (1s en
      // tracking, 5s en safe + trigger sentinel). Tout drop natif sans
      // callback fige `yoloInFlightById` côté JS (= flou freezé).
      let b64 = String(data[v5Start...])
      let typeErasedTab: any TabState = tab
      Task.detached { [weak self] in
        await self?.processVideoFrame(
          videoId: videoId, ctMs: ctMs, width: w, height: h, b64: b64,
          tab: typeErasedTab
        )
      }

    case "videoSentinel":
      // data = "<videoId>|<ct_ms>|<w>|<h>|<base64Jpeg>"
      // Sentinel léger (NanoDet seul, ~5-20ms). Pas de throttle natif —
      // le JS pilote sa propre cadence (`SENTINEL_INTERVAL`, cooldown,
      // `sentinelInFlight` flag) en parité avec le POC macOS
      // `private/extensions/basarunaa/src/video/video_processor.js`.
      var sPipes: [String.Index] = []
      sPipes.reserveCapacity(4)
      var sIdx = data.startIndex
      while sPipes.count < 4, let next = data[sIdx...].firstIndex(of: "|") {
        sPipes.append(next)
        sIdx = data.index(after: next)
      }
      guard sPipes.count == 4 else {
        log.error("videoSentinel parse failed (no 4 pipes)")
        return
      }
      let sv1Start = data.startIndex
      let sv1End = sPipes[0]
      let sv2Start = data.index(after: sPipes[0])
      let sv2End = sPipes[1]
      let sv3Start = data.index(after: sPipes[1])
      let sv3End = sPipes[2]
      let sv4Start = data.index(after: sPipes[2])
      let sv4End = sPipes[3]
      let sv5Start = data.index(after: sPipes[3])
      guard let sVideoId = Int(data[sv1Start..<sv1End]),
        let sCtMs = Int64(data[sv2Start..<sv2End]),
        let sW = Int(data[sv3Start..<sv3End]),
        let sH = Int(data[sv4Start..<sv4End])
      else {
        log.error("videoSentinel header parse failed")
        return
      }
      let sB64 = String(data[sv5Start...])
      let sTab: any TabState = tab
      Task.detached { [weak self] in
        await self?.processVideoSentinel(
          videoId: sVideoId, ctMs: sCtMs, width: sW, height: sH, b64: sB64,
          tab: sTab
        )
      }

    default:
      log.info("unknown_action=\(action, privacy: .public)")
    }
  }

  // MARK: - Prefs envoyées au JS (la policy vit dans core/policy.ts)

  /// Payload prefs pour le JS : mode + seuil de certitude + filtre main-seule.
  /// iOS n'expose pas (encore) le toggle `min_skeleton` → `minSkeletonActive`
  /// = false (le filtre main-seule est skip, parité conservatrice).
  private func prefsPayload() -> [String: Any] {
    [
      "mode": Preferences.Basarunaa.effectiveMode,
      "genderCertainty": Preferences.Basarunaa.genderCertainty.value,
      "minSkeletonActive": false,
    ]
  }

  // MARK: - Video frame processing (pivot D)

  /// Décompresse un JPEG capturé par JS (`canvas.drawImage(video)`), invoque
  /// `BasarunaaPipeline.analyze` (single-shot gender-v2n) puis push TOUTES les
  /// persons + les prefs au JS overlay, qui applique la policy (core/policy).
  ///
  /// V4 (2026-05-20) : appelle TOUJOURS `__basarunaaApplyVideo` côté JS, même
  /// en cas d'erreur (persons vides). Sans ça, le JS reste figé sur
  /// `yoloInFlightById = true` et le scheduler arrête de fire des YOLO →
  /// flou freezé jusqu'au pageReset.
  private func processVideoFrame(
    videoId: Int, ctMs: Int64, width: Int, height: Int, b64: String,
    tab: any TabState
  ) async {
    let start = Date()
    var personsPayload: [[String: Any]] = []
    var isNsfw = false
    var personsCount = 0
    var poseLatencyMs: Double = 0
    var classifyLatencyMs: Double = 0
    var nudeClasses: [String] = []
    let debugMode = Preferences.Basarunaa.debugMode.value

    decode: do {
      guard let jpegData = Data(base64Encoded: b64) else {
        log.error("videoFrame base64 decode failed videoId=\(videoId, privacy: .public)")
        break decode
      }
      guard let uiImage = UIImage(data: jpegData), let cgImage = uiImage.cgImage else {
        log.error(
          "videoFrame jpeg decode failed videoId=\(videoId, privacy: .public) bytes=\(jpegData.count, privacy: .public)"
        )
        break decode
      }
      do {
        // Pipeline vidéo : `analyze` (persons + gender) + `checkNsfw` (Marqo +
        // NudeNet) en parallèle — sinon le branch `if isNsfw` côté JS ne fire
        // jamais (analyze() retourne toujours isNsfw=false par design).
        async let nsfwAsync = BasarunaaPipeline.shared.checkNsfw(image: cgImage)
        let result = try await BasarunaaPipeline.shared.analyze(image: cgImage)
        let nsfw = try? await nsfwAsync
        // PUR EXTRACTEUR : on envoie TOUTES les persons ; le JS (core/policy)
        // décide lesquelles flouter et remonte le compte via "statsBlurred".
        personsPayload = serialize(persons: result.persons)
        isNsfw = nsfw?.isNsfw ?? false
        personsCount = result.persons.count
        poseLatencyMs = result.poseLatencyMs
        classifyLatencyMs = result.classifyLatencyMs
        nudeClasses = nsfw?.nudeClasses ?? []
        // Capture mode — sauvegarde la frame raw + metadata pour dataset ML.
        if Preferences.Basarunaa.captureMode.value {
          Self.saveCapture(
            jpegData: jpegData,
            videoId: videoId,
            width: width,
            height: height,
            ctMs: ctMs,
            mode: Preferences.Basarunaa.effectiveMode,
            isNsfw: isNsfw,
            persons: result.persons,
            poseLatencyMs: result.poseLatencyMs,
            classifyLatencyMs: result.classifyLatencyMs
          )
        }
      } catch {
        log.error(
          "videoFrame analyze failed videoId=\(videoId, privacy: .public): \(String(describing: error), privacy: .public)"
        )
      }
    }

    let elapsedMs = Date().timeIntervalSince(start) * 1000
    log.info(
      """
      video_analyzed videoId=\(videoId, privacy: .public) ct_ms=\(ctMs, privacy: .public) \
      w=\(width, privacy: .public) h=\(height, privacy: .public) \
      persons=\(personsCount, privacy: .public) \
      nsfw=\(isNsfw, privacy: .public) elapsed=\(String(format: "%.0f", elapsedMs), privacy: .public)ms
      """
    )

    // ALWAYS notify the JS — even on error — to release `yoloInFlightById`.
    // Nouveau contrat : on envoie `persons` (toutes) + `prefs` au lieu de
    // `bboxes` — le JS calcule les régions à flouter via core/policy.
    let prefs = prefsPayload()
    do {
      _ = try await tab.evaluateJavaScript(
        functionName: "window.__basarunaaApplyVideo",
        args: [
          videoId, ctMs, width, height, personsPayload, isNsfw, debugMode,
          prefs,
          [
            "poseLatencyMs": poseLatencyMs,
            "classifyLatencyMs": classifyLatencyMs,
            "mode": Preferences.Basarunaa.effectiveMode,
            "nudeClasses": nudeClasses,
          ] as [String: Any],
        ],
        contentWorld: Self.scriptSandbox
      )
    } catch {
      log.error(
        "videoFrame evaluateJS failed videoId=\(videoId, privacy: .public): \(String(describing: error), privacy: .public)"
      )
    }
  }

  /// Sentinel léger (NanoDet seul) — appelé à ~100ms d'intervalle par le JS
  /// pour smooth-tracker les positions entre 2 analyses YOLO.
  ///
  /// V4 (2026-05-20) : appelle TOUJOURS `__basarunaaApplyVideoSentinel` côté
  /// JS, même en cas d'erreur (payload vide), pour éviter le freeze de
  /// `sentinelInFlightById`.
  private func processVideoSentinel(
    videoId: Int, ctMs: Int64, width: Int, height: Int, b64: String,
    tab: any TabState
  ) async {
    let start = Date()
    var payload: [[Double]] = []

    decode: do {
      guard let jpegData = Data(base64Encoded: b64) else {
        log.error("videoSentinel base64 decode failed videoId=\(videoId, privacy: .public)")
        break decode
      }
      guard let uiImage = UIImage(data: jpegData), let cgImage = uiImage.cgImage else {
        log.error(
          "videoSentinel jpeg decode failed videoId=\(videoId, privacy: .public) bytes=\(jpegData.count, privacy: .public)"
        )
        break decode
      }
      do {
        let result = try await BasarunaaPipeline.shared.sentinel(image: cgImage)
        payload = result.bboxes.map {
          [$0.bbox.minX, $0.bbox.minY, $0.bbox.maxX, $0.bbox.maxY, $0.confidence]
        }
        let elapsedMs = Date().timeIntervalSince(start) * 1000
        log.info(
          """
          video_sentinel videoId=\(videoId, privacy: .public) ct_ms=\(ctMs, privacy: .public) \
          w=\(width, privacy: .public) h=\(height, privacy: .public) \
          bboxes=\(result.bboxes.count, privacy: .public) \
          elapsed=\(String(format: "%.0f", elapsedMs), privacy: .public)ms
          """
        )
      } catch {
        log.error(
          "videoSentinel inference failed videoId=\(videoId, privacy: .public): \(String(describing: error), privacy: .public)"
        )
      }
    }

    do {
      _ = try await tab.evaluateJavaScript(
        functionName: "window.__basarunaaApplyVideoSentinel",
        args: [videoId, ctMs, width, height, payload],
        contentWorld: Self.scriptSandbox
      )
    } catch {
      log.error(
        "videoSentinel evaluateJS failed videoId=\(videoId, privacy: .public): \(String(describing: error), privacy: .public)"
      )
    }
  }

  // MARK: - ML coupling (image)

  private func processImage(id: Int, base64: String, tab: any TabState) async {
    let start = Date()
    guard let imageData = Data(base64Encoded: base64),
      let uiImage = UIImage(data: imageData),
      let cgImage = uiImage.cgImage
    else {
      log.error("analyze[\(id, privacy: .public)] failed to decode base64")
      await reply(tab: tab, id: id, persons: [], debugMode: "none", elapsedMs: 0)
      return
    }

    do {
      let result = try await BasarunaaPipeline.shared.analyze(image: cgImage)
      let debugMode = Preferences.Basarunaa.debugMode.value
      // PUR EXTRACTEUR : on envoie TOUTES les persons + prefs. Le JS
      // (core/policy) décide keep/remove et lesquelles flouter.
      let personsPayload = serialize(persons: result.persons)
      let elapsedMs = Date().timeIntervalSince(start) * 1000
      log.info(
        """
        analyze[\(id, privacy: .public)] persons=\(result.persons.count, privacy: .public) \
        debug=\(debugMode, privacy: .public) (\(String(format: "%.0f", elapsedMs), privacy: .public)ms)
        """
      )
      await reply(
        tab: tab,
        id: id,
        persons: personsPayload,
        debugMode: debugMode,
        elapsedMs: elapsedMs
      )

      // Phase 2 (POC parity) — fire NSFW check in the background. Only
      // notify JS when the result is positive.
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
      await reply(tab: tab, id: id, persons: [], debugMode: "none", elapsedMs: 0)
    }
  }

  /// Phase 2 notification — fires `window.__basarunaaApplyNsfw(id, score)`
  /// on the page so the JS can replace the per-person blur with a full
  /// image blur. Called only when NSFW is positive.
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

  @MainActor
  private func reply(
    tab: any TabState,
    id: Int,
    persons: [[String: Any]],
    debugMode: String,
    elapsedMs: Double
  ) async {
    do {
      _ = try await tab.evaluateJavaScript(
        functionName: "window.__basarunaaApply",
        args: [id, persons, prefsPayload(), debugMode, elapsedMs],
        contentWorld: Self.scriptSandbox
      )
    } catch {
      log.error(
        "evaluateJavaScript failed for id=\(id, privacy: .public): \(String(describing: error), privacy: .public)"
      )
    }
  }

  /// Représentation compacte pour le JS (pur extracteur, single-shot gender-v2n).
  /// Envoie par personne :
  /// - `bbox` `[x1, y1, x2, y2]`
  /// - `keypoints` 17 COCO points `[x, y, conf]` (JS rebuild le body-polygon)
  /// - `faceBbox` (si dérivée)
  /// - `gender` `'male' | 'female' | 'child'` (classe argmax brute)
  /// - `genderConfidence` (score de la classe = score de détection)
  private func serialize(persons: [DetectedPerson]) -> [[String: Any]] {
    persons.map { p in
      let kps = p.keypoints.map { kp -> [Double] in
        [kp.point.x, kp.point.y, kp.confidence]
      }
      var dict: [String: Any] = [
        "bbox": [p.bbox.minX, p.bbox.minY, p.bbox.maxX, p.bbox.maxY] as [Double],
        "keypoints": kps,
        "gender": p.gender.rawValue,
        "genderConfidence": p.genderConfidence,
      ]
      if let face = p.faceBbox {
        dict["faceBbox"] = [face.minX, face.minY, face.maxX, face.maxY] as [Double]
      }
      return dict
    }
  }

  deinit {
    log.info("handler_deinit")
  }

  /// Capture mode — sauvegarde une frame analysée dans `Documents/Basarunaa-capture/`.
  /// Crée 2 fichiers par capture : `{ts}-v{videoId}-raw.jpg` + `-meta.json`
  /// (mode, NSFW, bboxes, gender 3-classes, keypoints, latency). Dataset ML.
  private static func saveCapture(
    jpegData: Data,
    videoId: Int,
    width: Int,
    height: Int,
    ctMs: Int64,
    mode: String,
    isNsfw: Bool,
    persons: [DetectedPerson],
    poseLatencyMs: Double,
    classifyLatencyMs: Double
  ) {
    let fm = FileManager.default
    guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let dir = docs.appendingPathComponent("Basarunaa-capture", isDirectory: true)
    do {
      if !fm.fileExists(atPath: dir.path) {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      }
    } catch {
      staticLog.error("captureMode mkdir failed: \(String(describing: error), privacy: .public)")
      return
    }
    let ts = Int(Date().timeIntervalSince1970 * 1000)  // ms epoch
    let base = "\(ts)-v\(videoId)"
    let rawUrl = dir.appendingPathComponent("\(base)-raw.jpg")
    let metaUrl = dir.appendingPathComponent("\(base)-meta.json")
    do {
      try jpegData.write(to: rawUrl, options: .atomic)
    } catch {
      staticLog.error("captureMode raw write failed: \(String(describing: error), privacy: .public)")
      return
    }
    let personsMeta: [[String: Any]] = persons.map { p in
      var dict: [String: Any] = [
        "bbox": [p.bbox.minX, p.bbox.minY, p.bbox.maxX, p.bbox.maxY] as [Double],
        "gender": p.gender.rawValue,
        "genderConfidence": p.genderConfidence,
      ]
      if let f = p.faceBbox {
        dict["faceBbox"] = [f.minX, f.minY, f.maxX, f.maxY] as [Double]
      }
      dict["keypoints"] = p.keypoints.map { [$0.point.x, $0.point.y, $0.confidence] }
      return dict
    }
    let meta: [String: Any] = [
      "videoId": videoId,
      "ctMs": ctMs,
      "width": width,
      "height": height,
      "mode": mode,
      "isNsfw": isNsfw,
      "personsCount": persons.count,
      "poseLatencyMs": poseLatencyMs,
      "classifyLatencyMs": classifyLatencyMs,
      "persons": personsMeta,
    ]
    do {
      let json = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
      try json.write(to: metaUrl, options: .atomic)
    } catch {
      staticLog.error("captureMode meta write failed: \(String(describing: error), privacy: .public)")
    }
    staticLog.info("captureMode saved \(base, privacy: .public)")
  }
}
</content>
