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

    let (pose, classifier) = try await loadModelsIfNeeded()

    let imageSize = CGSize(width: image.width, height: image.height)
    let totalStart = Date()

    let poseStart = Date()
    let rawPersons = try pose.detect(
      image: image,
      bodyScoreThreshold: bodyThreshold
    )
    let poseLatencyMs = Date().timeIntervalSince(poseStart) * 1000

    let classifyStart = Date()
    var results: [DetectedPerson] = []
    for raw in rawPersons {
      var gender: Gender?
      var genderConf: Double?
      if let faceBbox = raw.faceBbox, raw.faceConfidence >= faceThreshold {
        if let classification = try? classifier.classify(
          image: image,
          faceBbox: faceBbox,
          keypoints: raw.keypoints
        ) {
          gender = classification.gender
          genderConf = classification.confidence
        }
      }
      results.append(
        DetectedPerson(
          bbox: raw.bbox,
          faceBbox: raw.faceBbox,
          keypoints: raw.keypoints.map { (point: $0.point, confidence: $0.confidence) },
          bodyConfidence: raw.bodyConfidence,
          gender: gender,
          genderConfidence: genderConf
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
      imageSize: imageSize
    )
  }

  private func loadModelsIfNeeded() async throws -> (YOLOPoseDetector, GenderAgeClassifier) {
    if let pose, let classifier {
      return (pose, classifier)
    }
    let newPose = try YOLOPoseDetector()
    let newClassifier = try GenderAgeClassifier()
    self.pose = newPose
    self.classifier = newClassifier
    return (newPose, newClassifier)
  }
}
