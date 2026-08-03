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

public enum BasarunaaError: Error {
  case modelLoadFailed(String)
  case inferenceFailed(String)
  case invalidImage
}

/// Pipeline Basarunaa iOS — **single-shot gender-v2n** (migration 2026-07-13,
/// cf. `private/docs/BASARUNAA_MOBILE_GENDER_V2N.md`). Une inférence CoreML
/// donne persons + genre 3 classes + keypoints. La cascade historique (YOLO
/// pose + YOLOv8n-face + genderage InsightFace + PPLCNet + matching + synth
/// bodies) est retirée, ainsi que le sentinel NanoDet (2026-08-03 — le
/// pipeline vidéo est one-tier : gender-v2n à 250 ms est son propre tracker).
/// NSFW (Marqo + NudeNet) reste, gaté par la pref `nsfw_enabled` côté handler.
public actor BasarunaaPipeline {
  public static let shared = BasarunaaPipeline()

  private let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa")

  private var detector: GenderV2nPoseDetector?
  private var nsfwClassifier: NSFWClassifier?
  private var nudeNetDetector: NudeNetDetector?

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
      // On ne précharge QUE le détecteur (chemin chaud `analyze` — ~5s de compile
      // CoreML au 1er appel = le cold-start observé). NSFW (opt-in, OFF par défaut)
      // reste lazy : chargé à sa 1re demande réelle par checkNsfw(), pour ne pas
      // payer ni la mémoire ni le temps si inutile.
      _ = try loadDetectorIfNeeded()
      log.info("warmup done (detector)")
    } catch {
      log.error("warmup failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// Phase 2 — NSFW (Marqo + NudeNet). À lancer en parallèle d'`analyze`.
  public func checkNsfw(image: CGImage) async throws -> (
    isNsfw: Bool, score: Double?, latencyMs: Double, nudeClasses: [String]
  ) {
    let (nsfwClassifier, nudeNetDetector) = try loadNsfwIfNeeded()
    let nsfwStart = Date()
    let marqoResult = try? nsfwClassifier.classify(
      image: image, threshold: Preferences.Basarunaa.nsfwConf.value)
    let nudeDetections =
      (try? nudeNetDetector.detect(
        image: image, threshold: Preferences.Basarunaa.nudenetConf.value)) ?? []
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
}
