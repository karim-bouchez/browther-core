// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CoreML
import Foundation
import OSLog
import Preferences

/// Genre 3 classes du modèle single-shot gender-v2n (aligné `core/gender.ts`
/// `GenderClass` : male=0, female=1, child=2). rawValue = chaîne envoyée au JS.
public enum Gender: String, Sendable {
  case male
  case female
  case child
}

/// Person produite par le pipeline single-shot gender-v2n. PUR EXTRACTEUR :
/// aucune décision de flou ici (pas de seuil/downgrade). La policy vit dans
/// `core/policy.ts`, appliquée côté bundle webkit TS à partir de `gender` +
/// `genderConfidence`.
public struct DetectedPerson: @unchecked Sendable {
  /// Body bbox en coords image originale.
  public let bbox: CGRect
  /// Face bbox dérivée des keypoints 0..4 (nez/yeux/oreilles), ou nil.
  public let faceBbox: CGRect?
  /// 17 keypoints COCO.
  public let keypoints: [(point: CGPoint, confidence: Double)]
  /// Genre = classe argmax du modèle (brut, non seuillé).
  public let gender: Gender
  /// Confiance = score de la classe gagnante (sert de genderConfidence ET de
  /// score de détection — un seul score en single-shot).
  public let genderConfidence: Double
}

public struct BasarunaaResult: Sendable {
  public let persons: [DetectedPerson]
  public let totalLatencyMs: Double
  public let poseLatencyMs: Double
  public let classifyLatencyMs: Double
  public let imageSize: CGSize
  /// True si le classifieur NSFW plein-cadre (Marqo) a flaggé l'image.
  public let isNsfw: Bool
  /// Softmax NSFW Marqo (0..1), ou nil si non exécuté.
  public let nsfwScore: Double?
}

/// Sentinel NanoDet léger — bboxes seules, ni genre ni keypoints. Utilisé par le
/// pipeline vidéo two-tier pour smooth-tracker entre deux analyses lourdes.
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

/// Pipeline Basarunaa iOS — **single-shot gender-v2n** (migration 2026-07-13,
/// cf. `private/docs/BASARUNAA_MOBILE_GENDER_V2N.md`). Une inférence CoreML
/// donne persons + genre 3 classes + keypoints. La cascade historique (YOLO
/// pose + YOLOv8n-face + genderage InsightFace + PPLCNet + matching + synth
/// bodies) est retirée. NSFW (Marqo + NudeNet) et sentinel (NanoDet) restent.
public actor BasarunaaPipeline {
  public static let shared = BasarunaaPipeline()

  private let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa")

  private var detector: GenderV2nPoseDetector?
  private var nsfwClassifier: NSFWClassifier?
  private var nudeNetDetector: NudeNetDetector?
  /// Sentinel vidéo chargé à la demande (image-only callers ne le paient pas).
  private var sentinelDetector: NanoDetSentinelDetector?

  private init() {}

  public func warmup() async {
    do {
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
      _ = try loadDetectorIfNeeded()
      _ = try loadNsfwIfNeeded()
      _ = try loadSentinelIfNeeded()
      log.info("warmup done")
    } catch {
      log.error("warmup failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// Phase 0 — sentinel NanoDet léger (~5-20ms). Pas de genre, pas de NSFW.
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

  /// Phase 2 — NSFW (Marqo + NudeNet). À lancer en parallèle d'`analyze`.
  public func checkNsfw(image: CGImage) async throws -> (
    isNsfw: Bool, score: Double?, latencyMs: Double, nudeClasses: [String]
  ) {
    let (nsfwClassifier, nudeNetDetector) = try loadNsfwIfNeeded()
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
    let nudeClasses = nudeDetections.compactMap { d -> String? in
      guard let cls = NudeNetClass(rawValue: d.classIdx) else { return nil }
      return String(describing: cls)
    }
    if isNsfw {
      let trigger =
        marqoIsNsfw
        ? "marqo=\(String(format: "%.2f", nsfwScore ?? 0))"
        : "nudenet_exposed"
      log.info(
        "checkNsfw POSITIVE: \(trigger, privacy: .public) (\(String(format: "%.1f", latencyMs), privacy: .public)ms)"
      )
    } else {
      log.info("checkNsfw negative (\(String(format: "%.1f", latencyMs), privacy: .public)ms)")
    }
    return (isNsfw: isNsfw, score: nsfwScore, latencyMs: latencyMs, nudeClasses: nudeClasses)
  }

  /// Phase 1 — détection single-shot gender-v2n. Renvoie ASAP toutes les
  /// persons BRUTES (genre 3 classes + conf + keypoints), SANS décision de flou.
  public func analyze(image: CGImage) async throws -> BasarunaaResult {
    let bodyThreshold = Preferences.Basarunaa.confBody.value
    let detector = try loadDetectorIfNeeded()
    let imageSize = CGSize(width: image.width, height: image.height)
    let start = Date()

    let raws = try detector.detect(image: image, scoreThreshold: bodyThreshold)
    let persons = raws.map { r -> DetectedPerson in
      DetectedPerson(
        bbox: CGRect(
          x: r.bbox[0], y: r.bbox[1],
          width: r.bbox[2] - r.bbox[0], height: r.bbox[3] - r.bbox[1]),
        faceBbox: r.faceBbox.map {
          CGRect(x: $0[0], y: $0[1], width: $0[2] - $0[0], height: $0[3] - $0[1])
        },
        keypoints: r.keypoints.map { (point: CGPoint(x: $0.x, y: $0.y), confidence: $0.confidence) },
        gender: Self.gender(from: r.genderClass),
        genderConfidence: r.confidence
      )
    }

    let totalLatencyMs = Date().timeIntervalSince(start) * 1000
    log.info(
      "analyze done: persons=\(persons.count, privacy: .public) total=\(String(format: "%.1f", totalLatencyMs), privacy: .public)ms (single-shot gender-v2n)"
    )
    for (i, p) in persons.enumerated() {
      log.info(
        "[\(i, privacy: .public)] bbox=\(p.bbox.debugDescription, privacy: .public) → \(p.gender.rawValue, privacy: .public)@\(String(format: "%.2f", p.genderConfidence), privacy: .public)"
      )
    }

    return BasarunaaResult(
      persons: persons,
      totalLatencyMs: totalLatencyMs,
      poseLatencyMs: totalLatencyMs,
      classifyLatencyMs: 0,
      imageSize: imageSize,
      isNsfw: false,
      nsfwScore: nil
    )
  }

  private static func gender(from cls: GenderV2nClass) -> Gender {
    switch cls {
    case .male: return .male
    case .female: return .female
    case .child: return .child
    }
  }

  // MARK: - Loading

  private func loadDetectorIfNeeded() throws -> GenderV2nPoseDetector {
    if let detector { return detector }
    let newDetector = try GenderV2nPoseDetector()
    self.detector = newDetector
    return newDetector
  }

  private func loadNsfwIfNeeded() throws -> (NSFWClassifier, NudeNetDetector) {
    if let nsfwClassifier, let nudeNetDetector {
      return (nsfwClassifier, nudeNetDetector)
    }
    let newNsfw = try NSFWClassifier()
    let newNudeNet = try NudeNetDetector()
    self.nsfwClassifier = newNsfw
    self.nudeNetDetector = newNudeNet
    return (newNsfw, newNudeNet)
  }

  private func loadSentinelIfNeeded() throws -> NanoDetSentinelDetector {
    if let sentinelDetector { return sentinelDetector }
    let newSentinel = try NanoDetSentinelDetector()
    self.sentinelDetector = newSentinel
    return newSentinel
  }
}
