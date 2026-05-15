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

public struct DetectedPerson: Sendable {
  /// Bounding box of the person/body in the *original image* coordinate space (pixels).
  public let bbox: CGRect
  /// Derived face bbox (from keypoints 0-4) in original image coords, if available.
  public let faceBbox: CGRect?
  /// 17 COCO keypoints `(x, y, conf)` in original image coords.
  public let keypoints: [(point: CGPoint, confidence: Double)]
  /// Pose detection confidence.
  public let bodyConfidence: Double
  /// Gender classification — only filled when a face was matched and classified.
  public let gender: Gender?
  /// Gender classification confidence (softmax probability of `gender`).
  public let genderConfidence: Double?
}

public struct BasarunaaResult: Sendable {
  public let persons: [DetectedPerson]
  public let totalLatencyMs: Double
  public let poseLatencyMs: Double
  public let classifyLatencyMs: Double
  public let imageSize: CGSize
  /// True if the full-image NSFW classifier (Marqo) flagged the image.
  /// When true, the image should be blurred regardless of the person pipeline.
  public let isNsfw: Bool
  /// Marqo NSFW softmax probability (0..1), or nil if the classifier wasn't run.
  public let nsfwScore: Double?
}

public enum BasarunaaError: Error {
  case modelLoadFailed(String)
  case inferenceFailed(String)
  case invalidImage
}

/// PoC orchestrator for Basarunaa iOS. Loads YOLO11n-pose + GenderAge once
/// (lazy, on first analyze) and runs them on demand.
public actor BasarunaaPipeline {
  public static let shared = BasarunaaPipeline()

  private let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa")

  private var pose: YOLOPoseDetector?
  private var classifier: GenderAgeClassifier?
  private var bodyClassifier: PPLCNetClassifier?
  private var nsfwClassifier: NSFWClassifier?

  private init() {}

  /// Eager-load both models off the main thread. Call early (e.g. when the
  /// Basarunaa feature is toggled on) to avoid a cold-start hit on first analyze.
  public func warmup() async {
    do {
      _ = try await loadModelsIfNeeded()
      log.info("warmup done")
    } catch {
      log.error("warmup failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// Analyze a CGImage end-to-end. Returns detected persons with optional gender.
  /// Thresholds are read from `Preferences.Basarunaa.{face,body}Threshold`.
  public func analyze(image: CGImage) async throws -> BasarunaaResult {
    let bodyThreshold = Preferences.Basarunaa.bodyThreshold.value
    let faceThreshold = Preferences.Basarunaa.faceThreshold.value

    let (pose, classifier, bodyClassifier, nsfwClassifier) = try await loadModelsIfNeeded()

    let imageSize = CGSize(width: image.width, height: image.height)
    let totalStart = Date()

    // 1) NSFW pre-check. If flagged, short-circuit: the caller forces `keep`
    //    regardless of person detection. We still log it but skip YOLO.
    let nsfwStart = Date()
    let nsfwResult = try? nsfwClassifier.classify(image: image)
    let nsfwLatencyMs = Date().timeIntervalSince(nsfwStart) * 1000
    if let nsfwResult, nsfwResult.isNsfw {
      let totalLatencyMs = Date().timeIntervalSince(totalStart) * 1000
      log.info(
        """
        analyze NSFW short-circuit: score=\(String(format: "%.2f", nsfwResult.score), privacy: .public) \
        imageSize=\(Int(imageSize.width), privacy: .public)x\(Int(imageSize.height), privacy: .public) \
        nsfw=\(String(format: "%.1f", nsfwLatencyMs), privacy: .public)ms \
        total=\(String(format: "%.1f", totalLatencyMs), privacy: .public)ms
        """
      )
      return BasarunaaResult(
        persons: [],
        totalLatencyMs: totalLatencyMs,
        poseLatencyMs: 0,
        classifyLatencyMs: nsfwLatencyMs,
        imageSize: imageSize,
        isNsfw: true,
        nsfwScore: nsfwResult.score
      )
    }

    let poseStart = Date()
    let rawPersons = try pose.detect(
      image: image,
      bodyScoreThreshold: bodyThreshold
    )
    let poseLatencyMs = Date().timeIntervalSince(poseStart) * 1000

    let classifyStart = Date()
    var results: [DetectedPerson] = []
    for raw in rawPersons {
      let fused = fuseGender(
        for: raw,
        image: image,
        faceClassifier: classifier,
        bodyClassifier: bodyClassifier,
        faceThreshold: faceThreshold
      )
      results.append(
        DetectedPerson(
          bbox: raw.bbox,
          faceBbox: raw.faceBbox,
          keypoints: raw.keypoints.map { (point: $0.point, confidence: $0.confidence) },
          bodyConfidence: raw.bodyConfidence,
          gender: fused.gender,
          genderConfidence: fused.confidence
        )
      )
    }
    let classifyLatencyMs = Date().timeIntervalSince(classifyStart) * 1000

    let totalLatencyMs = Date().timeIntervalSince(totalStart) * 1000
    log.info(
      """
      analyze done: persons=\(results.count, privacy: .public) \
      imageSize=\(Int(imageSize.width), privacy: .public)x\(Int(imageSize.height), privacy: .public) \
      pose=\(String(format: "%.1f", poseLatencyMs), privacy: .public)ms \
      classify=\(String(format: "%.1f", classifyLatencyMs), privacy: .public)ms \
      total=\(String(format: "%.1f", totalLatencyMs), privacy: .public)ms
      """
    )
    for (i, p) in results.enumerated() {
      let genderStr = p.gender.map { "\($0.rawValue)@\(String(format: "%.2f", p.genderConfidence ?? 0))" } ?? "n/a"
      log.info(
        """
        [\(i, privacy: .public)] bbox=\(p.bbox.debugDescription, privacy: .public) \
        body=\(String(format: "%.2f", p.bodyConfidence), privacy: .public) \
        face=\(p.faceBbox?.debugDescription ?? "nil", privacy: .public) \
        gender=\(genderStr, privacy: .public)
        """
      )
    }

    return BasarunaaResult(
      persons: results,
      totalLatencyMs: totalLatencyMs,
      poseLatencyMs: poseLatencyMs,
      classifyLatencyMs: classifyLatencyMs,
      imageSize: imageSize,
      isNsfw: false,
      nsfwScore: nsfwResult?.score
    )
  }

  private func loadModelsIfNeeded() async throws -> (
    YOLOPoseDetector, GenderAgeClassifier, PPLCNetClassifier, NSFWClassifier
  ) {
    if let pose, let classifier, let bodyClassifier, let nsfwClassifier {
      return (pose, classifier, bodyClassifier, nsfwClassifier)
    }
    let newPose = try YOLOPoseDetector()
    let newClassifier = try GenderAgeClassifier()
    let newBodyClassifier = try PPLCNetClassifier()
    let newNsfwClassifier = try NSFWClassifier()
    self.pose = newPose
    self.classifier = newClassifier
    self.bodyClassifier = newBodyClassifier
    self.nsfwClassifier = newNsfwClassifier
    return (newPose, newClassifier, newBodyClassifier, newNsfwClassifier)
  }

  // MARK: - Face / body fusion (POC strategy)
  //
  // From `private/extensions/basarunaa/src/pipeline.js`:
  //
  //   if matchedFace:
  //     hasLegs = any(keypoints[13..16].conf > 0.3)   // knees + ankles
  //     if not hasLegs:           result = face            // partial body, trust face
  //     elif faceGender != bodyGender
  //          and faceConf > 0.7 and bodyConf > 0.7:  result = face (conflicted)
  //     else:                     result = max(face, body) by confidence
  //   else:
  //     result = body (PPLCNet on the body bbox)

  private func fuseGender(
    for raw: RawPersonDetection,
    image: CGImage,
    faceClassifier: GenderAgeClassifier,
    bodyClassifier: PPLCNetClassifier,
    faceThreshold: Double
  ) -> (gender: Gender?, confidence: Double?) {
    let faceResult: GenderClassification?
    if let faceBbox = raw.faceBbox, raw.faceConfidence >= faceThreshold {
      faceResult = try? faceClassifier.classify(
        image: image,
        faceBbox: faceBbox,
        keypoints: raw.keypoints
      )
    } else {
      faceResult = nil
    }

    let hasLegs = (13...16).contains { idx in
      idx < raw.keypoints.count && raw.keypoints[idx].confidence > 0.3
    }
    // Skip the body classifier for partial bodies (no legs) — POC says trust
    // face alone in that case; it also saves a CoreML inference call.
    let bodyResult: GenderClassification?
    if hasLegs {
      bodyResult = try? bodyClassifier.classify(image: image, bodyBbox: raw.bbox)
    } else {
      bodyResult = nil
    }

    if let face = faceResult, let body = bodyResult {
      if face.gender != body.gender && face.confidence > 0.7 && body.confidence > 0.7 {
        // Confident conflict → prefer face (POC marks conflicted, used as analytics).
        return (face.gender, face.confidence)
      }
      // Agree or one is uncertain → pick the more confident.
      let winner = face.confidence >= body.confidence ? face : body
      return (winner.gender, winner.confidence)
    }
    if let face = faceResult { return (face.gender, face.confidence) }
    if let body = bodyResult { return (body.gender, body.confidence) }
    return (nil, nil)
  }
}
