// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CoreML
import Foundation
import OSLog
import Preferences

public enum Gender: String, Sendable {
  case male
  case female
}

/// Person produced by the pipeline. May come from a body detection (with or
/// without a matched face) or be entirely synthesised from an unmatched
/// face detection ("synth body").
public struct DetectedPerson: @unchecked Sendable {
  /// Body bounding box in original image coordinates (real OR synthesised
  /// from a face bbox when `isSyntheticBody == true`).
  public let bbox: CGRect
  /// Face bbox (from YOLOv8n-face when matched, or directly when synthetic).
  public let faceBbox: CGRect?
  /// 17 COCO keypoints from YOLO11n-pose (empty for synthetic bodies).
  public let keypoints: [(point: CGPoint, confidence: Double)]
  /// Pose detection confidence (or face detection confidence for synth bodies).
  public let bodyConfidence: Double
  /// Fused gender (face genderage / PPLCNet, possibly downgraded to nil if
  /// below the user's `gender-certainty` threshold).
  public let gender: Gender?
  /// Confidence of the winning classifier.
  public let genderConfidence: Double?
  /// True when this person was synthesised from an unmatched face detection.
  public let isSyntheticBody: Bool
  /// Short label of the classifier that won (matches the macOS POC labels :
  /// "insightface", "insightface (conflict)", "insightface (partial body)",
  /// "pplcnet (best)", "pplcnet (no face)", "pplcnet (synth body)",
  /// "insightface (synth body)").
  public let classifierUsed: String
  /// Per-classifier softmax (only populated when the pipeline runs in debug
  /// mode). nil when the classifier wasn't run for this person.
  public let faceProb: (female: Double, male: Double)?
  public let bodyProb: (female: Double, male: Double)?
  /// Exact 96×96 face crop fed to InsightFace genderage (debug only).
  public let faceCropImage: CGImage?
  /// Exact 192×256 body crop fed to PPLCNet (debug only).
  public let bodyCropImage: CGImage?
}

public struct BasarunaaResult: Sendable {
  public let persons: [DetectedPerson]
  public let totalLatencyMs: Double
  public let poseLatencyMs: Double
  public let classifyLatencyMs: Double
  public let imageSize: CGSize
  /// True if the full-image NSFW classifier (Marqo) flagged the image.
  public let isNsfw: Bool
  /// Marqo NSFW softmax probability (0..1), or nil if the classifier wasn't run.
  public let nsfwScore: Double?
}

/// Lightweight NanoDet sentinel result — bboxes only, no gender, no keypoints.
/// Used by the video two-tier pipeline to smooth-track persons between two
/// YOLO runs and to event-trigger a YOLO refresh when a new person enters
/// the frame.
public struct BasarunaaSentinelResult: Sendable {
  public let bboxes: [SentinelBbox]
  public let latencyMs: Double
  public let imageSize: CGSize
}

public enum BasarunaaError: Error {
  case modelLoadFailed(String)
  case inferenceFailed(String)
  case invalidImage
}

/// Internal per-person timing collector. The pipeline logs each value so we
/// can pinpoint hot spots vs the macOS POC.
private struct PersonTiming {
  var isSynth: Bool
  var totalMs: Double = 0
  /// Polygon build + rasterise on the body bbox.
  var bodyPolyMs: Double = 0
  /// PPLCNet pre-process + inference.
  var bodyClfMs: Double = 0
  /// InsightFace genderage pre-process + inference (when a face was matched
  /// / direct face on synth).
  var faceClfMs: Double = 0
}

/// End-to-end Basarunaa pipeline on iOS. Reproduces the macOS dual-detector
/// flow from `private/extensions/basarunaa/src/pipeline.js#_processDual` :
///
/// 1. NSFW short-circuit (Marqo + NudeNet) — if positive, no person work.
/// 2. Body detection (YOLO11n-pose) + face detection (YOLOv8n-face), run
///    sequentially.
/// 3. Greedy global match of faces ⇄ bodies by face-center→upper-body
///    distance, with the constraint that the face bbox lies inside the body.
/// 4. For each body:
///    - Compute body polygon mask from keypoints (`BodyPolygon`).
///    - Run PPLCNet on the masked body crop.
///    - If a face is matched: run InsightFace genderage on the aligned crop
///      and fuse with the body classifier (POC rules).
/// 5. For each unmatched face: build a synthetic body bbox (4× face width,
///    7× face height downward), run PPLCNet on that synth crop and
///    InsightFace on the face — keep the most confident result.
public actor BasarunaaPipeline {
  public static let shared = BasarunaaPipeline()

  private let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa")

  private var pose: YOLOPoseDetector?
  private var face: YOLOFaceDetector?
  private var classifier: GenderAgeClassifier?
  private var bodyClassifier: PPLCNetClassifier?
  private var nsfwClassifier: NSFWClassifier?
  private var nudeNetDetector: NudeNetDetector?
  /// Lazy-loaded video sentinel. Kept separate from `loadModelsIfNeeded` so
  /// image-only callers don't pay for a model they never use, and the existing
  /// 6-tuple return type isn't broken.
  private var sentinelDetector: NanoDetSentinelDetector?

  private init() {}

  public func warmup() async {
    do {
      // Log the compute devices CoreML has access to. iOS 17+ exposes
      // availableComputeDevices on MLModel — each device is .cpu, .gpu or
      // .neuralEngine. With computeUnits = .all (set on every model below)
      // CoreML routes each op to whichever device is fastest. A model that
      // contains an op not implemented on ANE will partially fall back to
      // GPU/CPU automatically.
      let devices = MLModel.availableComputeDevices
      let labels = devices.map { d -> String in
        switch d {
        case .cpu: return "cpu"
        case .gpu: return "gpu"
        case .neuralEngine: return "ane"
        @unknown default: return "unknown"
        }
      }
      log.info("CoreML compute devices: [\(labels.joined(separator: ", "), privacy: .public)]")
      _ = try await loadModelsIfNeeded()
      _ = try loadSentinelIfNeeded()
      log.info("warmup done")
    } catch {
      log.error("warmup failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// Phase 0 — lightweight NanoDet sentinel. ~5-20ms typical, no gender,
  /// no NSFW, no keypoints. The JS video loop calls this every ~100ms to
  /// track person positions between two heavy `analyze()` calls.
  public func sentinel(image: CGImage) async throws -> BasarunaaSentinelResult {
    let detector = try loadSentinelIfNeeded()
    let imageSize = CGSize(width: image.width, height: image.height)
    let start = Date()
    let bboxes = try detector.detect(image: image)
    let latencyMs = Date().timeIntervalSince(start) * 1000
    log.info(
      "sentinel done: bboxes=\(bboxes.count, privacy: .public) latency=\(String(format: "%.1f", latencyMs), privacy: .public)ms"
    )
    return BasarunaaSentinelResult(bboxes: bboxes, latencyMs: latencyMs, imageSize: imageSize)
  }

  /// Phase 2 — NSFW check. Run async background after `analyze()` returns.
  /// Returns (isNsfw, marqoScore, latencyMs). Matches macOS POC where NSFW
  /// is a LOW priority enqueue that fires a separate notification only if
  /// positive (cf. offscreen.js Phase 1 / Phase 2 split).
  public func checkNsfw(image: CGImage) async throws -> (isNsfw: Bool, score: Double?, latencyMs: Double) {
    let (_, _, _, _, nsfwClassifier, nudeNetDetector) = try await loadModelsIfNeeded()
    let nsfwStart = Date()
    let marqoResult = try? nsfwClassifier.classify(image: image)
    let nudeDetections = (try? nudeNetDetector.detect(image: image)) ?? []
    let exposedHit = nudeDetections.contains { d in
      guard let cls = NudeNetClass(rawValue: d.classIdx) else { return false }
      return NudeNetClass.alwaysFlagged.contains(cls)
    }
    let marqoIsNsfw = marqoResult?.isNsfw ?? false
    let nsfwScore = marqoResult?.score
    let latencyMs = Date().timeIntervalSince(nsfwStart) * 1000
    let isNsfw = marqoIsNsfw || exposedHit
    if isNsfw {
      let trigger = marqoIsNsfw
        ? "marqo=\(String(format: "%.2f", nsfwScore ?? 0))"
        : "nudenet_exposed"
      log.info(
        "checkNsfw POSITIVE: \(trigger, privacy: .public) (\(String(format: "%.1f", latencyMs), privacy: .public)ms)"
      )
    } else {
      log.info("checkNsfw negative (\(String(format: "%.1f", latencyMs), privacy: .public)ms)")
    }
    return (isNsfw: isNsfw, score: nsfwScore, latencyMs: latencyMs)
  }

  /// Phase 1 — person detection + gender classification. Returns ASAP so
  /// the JS side can apply per-person blur without waiting on NSFW. The
  /// caller is expected to fire `checkNsfw` in parallel and notify the JS
  /// separately when (and only if) the result is positive.
  public func analyze(image: CGImage) async throws -> BasarunaaResult {
    let bodyThreshold = Preferences.Basarunaa.confBody.value
    let faceThreshold = Preferences.Basarunaa.confFace.value
    let genderCertainty = Preferences.Basarunaa.genderCertainty.value
    let debugMode = Preferences.Basarunaa.debugMode.value
    let wantsCrops = debugMode == "debug"

    let (pose, face, classifier, bodyClassifier, _, _) =
      try await loadModelsIfNeeded()

    let imageSize = CGSize(width: image.width, height: image.height)
    let totalStart = Date()

    // 2) Body + face detection in parallel (best case: body on ANE, face
    // routed by CoreML to GPU — true concurrency. Worst case both queue on
    // ANE and serialize — no gain but no loss either).
    let detectStart = Date()
    async let bodiesAsync = Self.runBodyDetect(
      pose: pose, image: image, threshold: bodyThreshold
    )
    async let facesAsync = Self.runFaceDetect(
      face: face, image: image, threshold: faceThreshold
    )
    let bodyOut = try await bodiesAsync
    let faceOut = await facesAsync
    let bodies = bodyOut.result
    let faces = faceOut.result
    let bodyMs = bodyOut.latencyMs
    let faceMs = faceOut.latencyMs
    let poseLatencyMs = Date().timeIntervalSince(detectStart) * 1000

    // 3) Match faces ⇄ bodies (greedy by distance).
    let matchStart = Date()
    let matches = matchFacesToBodies(bodies: bodies, faces: faces)
    let matchMs = Date().timeIntervalSince(matchStart) * 1000

    // 4) Classify each body. Collect per-person timing via a stats array.
    let classifyStart = Date()
    var results: [DetectedPerson] = []
    var personTimings: [PersonTiming] = []

    for (bi, body) in bodies.enumerated() {
      let matched = matches[bi]
      let pStart = Date()
      var timing = PersonTiming(isSynth: false)
      let person = await classifyMatched(
        index: bi,
        body: body,
        matchedFace: matched,
        image: image,
        imageSize: imageSize,
        faceClassifier: classifier,
        bodyClassifier: bodyClassifier,
        faceThreshold: faceThreshold,
        genderCertainty: genderCertainty,
        wantsCrops: wantsCrops,
        timing: &timing
      )
      timing.totalMs = Date().timeIntervalSince(pStart) * 1000
      personTimings.append(timing)
      results.append(person)
    }

    // 5) Synthetic bodies for unmatched faces.
    let matchedFaceIndices = Set(matches.values.map { $0.0 })
    for (fi, faceDet) in faces.enumerated() {
      if matchedFaceIndices.contains(fi) { continue }
      let pStart = Date()
      var timing = PersonTiming(isSynth: true)
      let person = await classifyUnmatchedFace(
        face: faceDet,
        image: image,
        imageSize: imageSize,
        faceClassifier: classifier,
        bodyClassifier: bodyClassifier,
        genderCertainty: genderCertainty,
        wantsCrops: wantsCrops,
        timing: &timing
      )
      timing.totalMs = Date().timeIntervalSince(pStart) * 1000
      personTimings.append(timing)
      results.append(person)
    }

    let classifyLatencyMs = Date().timeIntervalSince(classifyStart) * 1000
    let totalLatencyMs = Date().timeIntervalSince(totalStart) * 1000

    log.info(
      """
      analyze done: persons=\(results.count, privacy: .public) \
      bodies=\(bodies.count, privacy: .public) faces=\(faces.count, privacy: .public) \
      synthBodies=\(faces.count - matchedFaceIndices.count, privacy: .public)
      detect=\(String(format: "%.1f", poseLatencyMs), privacy: .public)ms (body=\(String(format: "%.1f", bodyMs), privacy: .public) face=\(String(format: "%.1f", faceMs), privacy: .public)) \
      match=\(String(format: "%.1f", matchMs), privacy: .public)ms \
      classify=\(String(format: "%.1f", classifyLatencyMs), privacy: .public)ms \
      total=\(String(format: "%.1f", totalLatencyMs), privacy: .public)ms (NSFW Phase 2 async)
      """
    )
    for (i, t) in personTimings.enumerated() {
      log.info(
        "  perf[\(i, privacy: .public)]\(t.isSynth ? " synth" : "", privacy: .public): total=\(String(format: "%.1f", t.totalMs), privacy: .public) bodyPoly=\(String(format: "%.1f", t.bodyPolyMs), privacy: .public) bodyClf=\(String(format: "%.1f", t.bodyClfMs), privacy: .public) faceClf=\(String(format: "%.1f", t.faceClfMs), privacy: .public)"
      )
    }
    for (i, p) in results.enumerated() {
      let g = p.gender.map { "\($0.rawValue)@\(String(format: "%.2f", p.genderConfidence ?? 0))" } ?? "n/a"
      log.info(
        "[\(i, privacy: .public)] bbox=\(p.bbox.debugDescription, privacy: .public) body=\(String(format: "%.2f", p.bodyConfidence), privacy: .public) face=\(p.faceBbox?.debugDescription ?? "nil", privacy: .public) → \(g, privacy: .public) [\(p.classifierUsed, privacy: .public)]\(p.isSyntheticBody ? " SYNTH" : "", privacy: .public)"
      )
    }

    return BasarunaaResult(
      persons: results,
      totalLatencyMs: totalLatencyMs,
      poseLatencyMs: poseLatencyMs,
      classifyLatencyMs: classifyLatencyMs,
      imageSize: imageSize,
      isNsfw: false,
      nsfwScore: nil
    )
  }

  // MARK: - Loading

  private func loadModelsIfNeeded() async throws -> (
    YOLOPoseDetector, YOLOFaceDetector, GenderAgeClassifier,
    PPLCNetClassifier, NSFWClassifier, NudeNetDetector
  ) {
    if let pose, let face, let classifier, let bodyClassifier,
       let nsfwClassifier, let nudeNetDetector {
      return (pose, face, classifier, bodyClassifier, nsfwClassifier, nudeNetDetector)
    }
    let newPose = try YOLOPoseDetector()
    let newFace = try YOLOFaceDetector()
    let newClassifier = try GenderAgeClassifier()
    let newBodyClassifier = try PPLCNetClassifier()
    let newNsfwClassifier = try NSFWClassifier()
    let newNudeNetDetector = try NudeNetDetector()
    self.pose = newPose
    self.face = newFace
    self.classifier = newClassifier
    self.bodyClassifier = newBodyClassifier
    self.nsfwClassifier = newNsfwClassifier
    self.nudeNetDetector = newNudeNetDetector
    return (newPose, newFace, newClassifier, newBodyClassifier, newNsfwClassifier, newNudeNetDetector)
  }

  private func loadSentinelIfNeeded() throws -> NanoDetSentinelDetector {
    if let sentinelDetector { return sentinelDetector }
    let newSentinel = try NanoDetSentinelDetector()
    self.sentinelDetector = newSentinel
    return newSentinel
  }

  // MARK: - Face ⇄ body matching (port direct du POC _matchFacesToBodies)

  /// Greedy global match of faces to bodies by distance from face center to
  /// the body's upper-center (15% from the top). The face bbox must be
  /// fully inside the body bbox. Returns `[bodyIndex: (faceIndex, RawFaceDetection)]`.
  private func matchFacesToBodies(
    bodies: [RawPersonDetection],
    faces: [RawFaceDetection]
  ) -> [Int: (Int, RawFaceDetection)] {
    struct Pair { let bi: Int; let fi: Int; let dist: Double }
    var pairs: [Pair] = []
    for (bi, body) in bodies.enumerated() {
      let bx1 = Double(body.bbox.minX)
      let by1 = Double(body.bbox.minY)
      let bx2 = Double(body.bbox.maxX)
      let by2 = Double(body.bbox.maxY)
      let bCx = (bx1 + bx2) / 2
      let bFaceY = by1 + (by2 - by1) * 0.15

      for (fi, faceDet) in faces.enumerated() {
        let fx1 = Double(faceDet.faceBbox.minX)
        let fy1 = Double(faceDet.faceBbox.minY)
        let fx2 = Double(faceDet.faceBbox.maxX)
        let fy2 = Double(faceDet.faceBbox.maxY)
        // POC constraint: face bbox fully inside body bbox.
        if fx1 < bx1 || fy1 < by1 || fx2 > bx2 || fy2 > by2 { continue }
        let fcx = (fx1 + fx2) / 2
        let fcy = (fy1 + fy2) / 2
        let dx = fcx - bCx
        let dy = fcy - bFaceY
        let dist = (dx * dx + dy * dy).squareRoot()
        pairs.append(Pair(bi: bi, fi: fi, dist: dist))
      }
    }
    pairs.sort { $0.dist < $1.dist }

    var matches: [Int: (Int, RawFaceDetection)] = [:]
    var usedBodies = Set<Int>()
    var usedFaces = Set<Int>()
    for p in pairs {
      if usedBodies.contains(p.bi) || usedFaces.contains(p.fi) { continue }
      matches[p.bi] = (p.fi, faces[p.fi])
      usedBodies.insert(p.bi)
      usedFaces.insert(p.fi)
    }
    return matches
  }

  // MARK: - Classification for matched bodies

  private func classifyMatched(
    index: Int,
    body: RawPersonDetection,
    matchedFace: (Int, RawFaceDetection)?,
    image: CGImage,
    imageSize: CGSize,
    faceClassifier: GenderAgeClassifier,
    bodyClassifier: PPLCNetClassifier,
    faceThreshold: Double,
    genderCertainty: Double,
    wantsCrops: Bool,
    timing: inout PersonTiming
  ) async -> DetectedPerson {
    // Body polygon for PPLCNet — rasterization happens inside the
    // classifier, directly into the 192×256 buffer space (~30ms saved
    // vs full-image mask + per-pixel coord remap, 2026-05-17).
    let polyStart = Date()
    let poly = BodyPolygon.buildPolygon(
      keypoints: body.keypoints,
      bbox: body.bbox,
      imageSize: imageSize
    )
    let bodyPolygonPoints: [CGPoint]? = poly.isBodyShaped ? poly.points : nil
    timing.bodyPolyMs = Date().timeIntervalSince(polyStart) * 1000

    // Body + face classify in parallel (per person). PPLCNet (192×256) is
    // heavier than InsightFace genderage (96×96) — running them concurrently
    // gives CoreML a chance to schedule genderage on the GPU while PPLCNet
    // occupies the ANE. Worst case: ANE serialization — no loss.
    let bodyBbox = body.bbox
    let faceBboxOpt = matchedFace?.1.faceBbox
    let faceKpsOpt = matchedFace?.1.keypoints
    let clfStart = Date()
    async let bodyAsync = Self.runBodyClassify(
      classifier: bodyClassifier,
      image: image,
      bbox: bodyBbox,
      polygonPoints: bodyPolygonPoints,
      wantsCrop: wantsCrops
    )
    async let faceAsync = Self.runFaceClassifyOpt(
      classifier: faceClassifier,
      image: image,
      faceBbox: faceBboxOpt,
      keypoints: faceKpsOpt,
      wantsCrop: wantsCrops
    )
    let bodyOut = await bodyAsync
    let faceOut = await faceAsync
    _ = clfStart
    timing.bodyClfMs = bodyOut.latencyMs
    timing.faceClfMs = faceOut.latencyMs
    let bodyResult = bodyOut.result
    let faceResult: GenderClassification? = faceOut.result

    // Has-legs check uses the body keypoints (13..16 = knees + ankles).
    let hasLegs = (13...16).contains { idx in
      idx < body.keypoints.count && body.keypoints[idx].confidence > 0.3
    }

    var winnerGender: Gender? = nil
    var winnerConf: Double? = nil
    var classifierUsed: String = "pplcnet"

    if matchedFace != nil {

      if let face = faceResult {
        if !hasLegs {
          // Partial body (cropped / seated) → trust face, body unreliable.
          winnerGender = face.gender
          winnerConf = face.confidence
          classifierUsed = "insightface (partial body)"
        } else if let body = bodyResult,
                  face.gender != body.gender,
                  face.confidence > 0.7,
                  body.confidence > 0.7 {
          // Strong conflict — pick face.
          winnerGender = face.gender
          winnerConf = face.confidence
          classifierUsed = "insightface (conflict)"
        } else if let body = bodyResult, face.confidence < body.confidence {
          winnerGender = body.gender
          winnerConf = body.confidence
          classifierUsed = "pplcnet (best)"
        } else {
          winnerGender = face.gender
          winnerConf = face.confidence
          classifierUsed = "insightface"
        }
      } else if let body = bodyResult {
        winnerGender = body.gender
        winnerConf = body.confidence
        classifierUsed = "pplcnet (align fail)"
      }
    } else {
      // No face → body only.
      if let body = bodyResult {
        winnerGender = body.gender
        winnerConf = body.confidence
        classifierUsed = "pplcnet (no face)"
      }
    }

    // Downgrade weak classifications to nil so `blur-female` falls back to
    // its safer-default-to-keep behaviour.
    let trustedGender: Gender?
    if let g = winnerGender, let c = winnerConf, c >= genderCertainty {
      trustedGender = g
    } else {
      trustedGender = nil
    }

    return DetectedPerson(
      bbox: body.bbox,
      faceBbox: matchedFace?.1.faceBbox ?? body.faceBbox,
      keypoints: body.keypoints,
      bodyConfidence: body.bodyConfidence,
      gender: trustedGender,
      genderConfidence: winnerConf,
      isSyntheticBody: false,
      classifierUsed: classifierUsed,
      faceProb: faceResult.map { (female: $0.pFemale, male: $0.pMale) },
      bodyProb: bodyResult.map { (female: $0.pFemale, male: $0.pMale) },
      faceCropImage: faceResult?.cropImage,
      bodyCropImage: bodyResult?.cropImage
    )
  }

  // MARK: - Synthetic body for unmatched face

  private func classifyUnmatchedFace(
    face: RawFaceDetection,
    image: CGImage,
    imageSize: CGSize,
    faceClassifier: GenderAgeClassifier,
    bodyClassifier: PPLCNetClassifier,
    genderCertainty: Double,
    wantsCrops: Bool,
    timing: inout PersonTiming
  ) async -> DetectedPerson {
    // POC formula: 4× face width, 7× face height downward from face top.
    let fb = face.faceBbox
    let faceW = Double(fb.width)
    let faceH = Double(fb.height)
    let fx1 = Double(fb.minX)
    let fy1 = Double(fb.minY)
    let bodyCx = fx1 + faceW / 2
    let bodyW = faceW * 4
    let synthX1 = max(0, bodyCx - bodyW / 2)
    let synthY1 = max(0, fy1 - faceH * 0.3)
    let synthX2 = min(Double(imageSize.width), bodyCx + bodyW / 2)
    let synthY2 = min(Double(imageSize.height), fy1 + faceH * 7)
    let synthBbox = CGRect(
      x: synthX1,
      y: synthY1,
      width: max(0, synthX2 - synthX1),
      height: max(0, synthY2 - synthY1)
    )

    // POC: no body keypoints for synth → no mask, no polygon gray-out.
    // Body (PPLCNet) + face (InsightFace) in parallel — same gain pattern
    // as classifyMatched.
    async let synthBodyAsync = Self.runBodyClassify(
      classifier: bodyClassifier,
      image: image,
      bbox: synthBbox,
      polygonPoints: nil,
      wantsCrop: wantsCrops
    )
    async let faceAsync = Self.runFaceClassifyOpt(
      classifier: faceClassifier,
      image: image,
      faceBbox: fb,
      keypoints: face.keypoints,
      wantsCrop: wantsCrops
    )
    let synthBodyOut = await synthBodyAsync
    let faceOut = await faceAsync
    timing.bodyClfMs = synthBodyOut.latencyMs
    timing.faceClfMs = faceOut.latencyMs
    let synthBodyResult = synthBodyOut.result
    let faceResult = faceOut.result

    var winnerGender: Gender? = nil
    var winnerConf: Double? = nil
    var classifierUsed = "unmatched face"

    if let f = faceResult, let b = synthBodyResult {
      if b.confidence > f.confidence {
        winnerGender = b.gender
        winnerConf = b.confidence
        classifierUsed = "pplcnet (synth body)"
      } else {
        winnerGender = f.gender
        winnerConf = f.confidence
        classifierUsed = "insightface (synth body)"
      }
    } else if let f = faceResult {
      winnerGender = f.gender
      winnerConf = f.confidence
      classifierUsed = "insightface (synth body)"
    } else if let b = synthBodyResult {
      winnerGender = b.gender
      winnerConf = b.confidence
      classifierUsed = "pplcnet (synth body)"
    }

    let trustedGender: Gender?
    if let g = winnerGender, let c = winnerConf, c >= genderCertainty {
      trustedGender = g
    } else {
      trustedGender = nil
    }

    return DetectedPerson(
      bbox: synthBbox,
      faceBbox: fb,
      keypoints: [],   // POC: synth body has no body keypoints
      bodyConfidence: face.confidence,
      gender: trustedGender,
      genderConfidence: winnerConf,
      isSyntheticBody: true,
      classifierUsed: classifierUsed,
      faceProb: faceResult.map { (female: $0.pFemale, male: $0.pMale) },
      bodyProb: synthBodyResult.map { (female: $0.pFemale, male: $0.pMale) },
      faceCropImage: faceResult?.cropImage,
      bodyCropImage: synthBodyResult?.cropImage
    )
  }

  // MARK: - Parallel helpers (nonisolated, run in cooperative pool)

  /// Wrap `pose.detect` so it can run via `async let` outside actor isolation.
  /// MLModel is documented as thread-safe for `prediction(from:)`.
  private static func runBodyDetect(
    pose: YOLOPoseDetector,
    image: CGImage,
    threshold: Double
  ) async throws -> (result: [RawPersonDetection], latencyMs: Double) {
    let start = Date()
    let result = try pose.detect(image: image, bodyScoreThreshold: threshold)
    return (result, Date().timeIntervalSince(start) * 1000)
  }

  private static func runFaceDetect(
    face: YOLOFaceDetector,
    image: CGImage,
    threshold: Double
  ) async -> (result: [RawFaceDetection], latencyMs: Double) {
    let start = Date()
    let result = (try? face.detect(image: image, confThreshold: threshold)) ?? []
    return (result, Date().timeIntervalSince(start) * 1000)
  }

  private static func runBodyClassify(
    classifier: PPLCNetClassifier,
    image: CGImage,
    bbox: CGRect,
    polygonPoints: [CGPoint]?,
    wantsCrop: Bool
  ) async -> (result: GenderClassification?, latencyMs: Double) {
    let start = Date()
    let result = (try? classifier.classify(
      image: image,
      bodyBbox: bbox,
      bodyPolygonPoints: polygonPoints,
      wantsCropImage: wantsCrop
    )) ?? nil
    return (result, Date().timeIntervalSince(start) * 1000)
  }

  private static func runFaceClassifyOpt(
    classifier: GenderAgeClassifier,
    image: CGImage,
    faceBbox: CGRect?,
    keypoints: [(point: CGPoint, confidence: Double)]?,
    wantsCrop: Bool
  ) async -> (result: GenderClassification?, latencyMs: Double) {
    let start = Date()
    guard let bbox = faceBbox, let kps = keypoints else {
      return (nil, 0)
    }
    let result = (try? classifier.classify(
      image: image,
      faceBbox: bbox,
      keypoints: kps,
      wantsCropImage: wantsCrop
    )) ?? nil
    return (result, Date().timeIntervalSince(start) * 1000)
  }
}
