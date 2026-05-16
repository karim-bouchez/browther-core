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
      log.info("page_reset url=\(data, privacy: .public)")

    default:
      log.info("unknown_action=\(action, privacy: .public)")
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
      await reply(tab: tab, id: id, decision: .keep, persons: [])
      return
    }

    do {
      let result = try await BasarunaaPipeline.shared.analyze(image: cgImage)
      let mode = Preferences.Basarunaa.effectiveMode
      let decision: BlurDecision
      let personsToBlur: [DetectedPerson]
      if result.isNsfw {
        // NSFW short-circuit: full-image blur regardless of mode. No per-person
        // payload — JS keeps the default full-image blur in place.
        decision = .keep
        personsToBlur = []
      } else {
        let (d, persons) = decide(from: result.persons, mode: mode)
        decision = d
        personsToBlur = persons
      }
      let elapsedMs = Date().timeIntervalSince(start) * 1000
      log.info(
        """
        analyze[\(id, privacy: .public)] nsfw=\(result.isNsfw, privacy: .public) \
        persons=\(result.persons.count, privacy: .public) toBlur=\(personsToBlur.count, privacy: .public) \
        mode=\(mode, privacy: .public) → \(decision.rawValue, privacy: .public) \
        (\(String(format: "%.0f", elapsedMs), privacy: .public)ms)
        """
      )
      await reply(tab: tab, id: id, decision: decision, persons: personsToBlur)
    } catch {
      log.error("analyze[\(id, privacy: .public)] failed: \(String(describing: error), privacy: .public)")
      await reply(tab: tab, id: id, decision: .keep, persons: [])
    }
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
    persons: [DetectedPerson]
  ) async {
    do {
      let serialized = serialize(persons: persons)
      _ = try await tab.evaluateJavaScript(
        functionName: "window.__basarunaaApply",
        args: [id, decision.rawValue, serialized],
        contentWorld: Self.scriptSandbox
      )
    } catch {
      log.error(
        "evaluateJavaScript failed for id=\(id, privacy: .public): \(String(describing: error), privacy: .public)"
      )
    }
  }

  /// Compact representation for the JS side. We send the body bbox
  /// `[x1, y1, x2, y2]` (top-left + bottom-right, POC convention) and the 17
  /// COCO keypoints `[x, y, conf]` so JS can rebuild the body polygon mask
  /// exactly like the POC macOS pipeline (`buildBodyPolygon`).
  private func serialize(persons: [DetectedPerson]) -> [[String: Any]] {
    persons.map { p in
      let x1 = p.bbox.minX
      let y1 = p.bbox.minY
      let x2 = p.bbox.maxX
      let y2 = p.bbox.maxY
      let kps = p.keypoints.map { kp -> [Double] in
        [kp.point.x, kp.point.y, kp.confidence]
      }
      return [
        "bbox": [x1, y1, x2, y2] as [Double],
        "keypoints": kps,
      ]
    }
  }

  deinit {
    log.info("handler_deinit")
  }
}
