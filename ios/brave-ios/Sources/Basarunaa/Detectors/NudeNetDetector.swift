// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CoreML
import Foundation
import OSLog

/// 18 NudeNet body-part classes (POC `src/classifiers/nsfw.js` ordering).
enum NudeNetClass: Int, CaseIterable, Sendable {
  case femaleGenitaliaCovered = 0
  case faceFemale = 1
  case buttocksExposed = 2
  case femaleBreastExposed = 3
  case femaleGenitaliaExposed = 4
  case maleBreastExposed = 5
  case anusExposed = 6
  case feetExposed = 7
  case bellyCovered = 8
  case feetCovered = 9
  case armpitsCovered = 10
  case armpitsExposed = 11
  case faceMale = 12
  case bellyExposed = 13
  case maleGenitaliaExposed = 14
  case anusCovered = 15
  case femaleBreastCovered = 16
  case buttocksCovered = 17

  /// Classes that always trigger NSFW blur (visible explicit content).
  static let alwaysFlagged: Set<NudeNetClass> = [
    .buttocksExposed, .femaleBreastExposed, .femaleGenitaliaExposed,
    .maleBreastExposed, .anusExposed, .maleGenitaliaExposed,
  ]

  /// Classes that flag NSFW only when Marqo also suspects (score > 0.3).
  /// Too many false positives on t-shirts, pants, etc. otherwise.
  static let flaggedWithMarqoSuspicion: Set<NudeNetClass> = [
    .femaleGenitaliaCovered, .femaleBreastCovered, .buttocksCovered,
  ]
}

struct NudeNetDetection: Sendable {
  let classIdx: Int
  let confidence: Double
}

/// NudeNet 320×320 body-part detector. YOLO-style output `[1, 22, 2100]` :
/// channels 0-3 = bbox (cx, cy, w, h) in letterboxed 320 space, 4-21 = 18 class
/// sigmoid scores. We don't need bbox precision here (only "is the class
/// present anywhere?"), so we keep the max-score detection per proposal and
/// filter by threshold.
final class NudeNetDetector {
  static let inputSize: CGFloat = 320
  static let numClasses = 18
  static let confidenceThreshold: Double = 0.3

  private let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa.NudeNet")
  private let model: MLModel
  private let outputName: String

  init() throws {
    guard let url = Bundle.module.url(forResource: "NudeNet", withExtension: "mlmodelc") else {
      throw BasarunaaError.modelLoadFailed("NudeNet.mlmodelc not found in bundle")
    }
    let config = MLModelConfiguration()
    config.computeUnits = .all
    self.model = try MLModel(contentsOf: url, configuration: config)
    guard let firstOutput = self.model.modelDescription.outputDescriptionsByName.keys.sorted().first else {
      throw BasarunaaError.modelLoadFailed("NudeNet: no output found")
    }
    self.outputName = firstOutput
    log.info("loaded NudeNet, output=\(firstOutput, privacy: .public)")
  }

  /// Returns the set of detections whose confidence exceeds the threshold.
  /// Bbox coords are dropped (we only care about class presence for NSFW).
  func detect(image: CGImage) throws -> [NudeNetDetection] {
    let letterboxed = Letterbox.fit(image: image, to: Self.inputSize, padding: 128)
    guard let pixelBuffer = letterboxed.pixelBuffer else {
      throw BasarunaaError.invalidImage
    }
    let input = try MLDictionaryFeatureProvider(dictionary: ["image": pixelBuffer])
    let output = try model.prediction(from: input)
    guard let tensor = output.featureValue(for: outputName)?.multiArrayValue else {
      throw BasarunaaError.inferenceFailed("NudeNet output missing")
    }
    return postprocess(tensor: tensor)
  }

  private func postprocess(tensor: MLMultiArray) -> [NudeNetDetection] {
    let shape = tensor.shape.map { $0.intValue }
    // Expected: [1, 22, 2100]  (4 bbox + 18 classes)
    guard shape.count == 3, shape[0] == 1 else {
      log.error("unexpected NudeNet output shape: \(shape, privacy: .public)")
      return []
    }
    let strides = tensor.strides.map { $0.intValue }
    let layoutIsCHW = (shape[1] == 4 + Self.numClasses)
    let numChannels = layoutIsCHW ? shape[1] : shape[2]
    let numProposals = layoutIsCHW ? shape[2] : shape[1]
    guard numChannels == 4 + Self.numClasses else {
      log.error("unexpected NudeNet channel count: \(numChannels, privacy: .public)")
      return []
    }
    let channelStride = layoutIsCHW ? strides[1] : strides[2]
    let proposalStride = layoutIsCHW ? strides[2] : strides[1]

    let read: (Int) -> Float
    if tensor.dataType == .float16 {
      let p = tensor.dataPointer.bindMemory(to: Float16.self, capacity: tensor.count)
      read = { Float(p[$0]) }
    } else {
      let p = tensor.dataPointer.bindMemory(to: Float.self, capacity: tensor.count)
      read = { p[$0] }
    }

    // For each proposal, take the class with the highest score. Keep only those
    // above the confidence threshold. NMS isn't needed — we don't use bboxes
    // and a single positive detection is enough to flag the image.
    var bestPerClass: [Int: Double] = [:]
    for i in 0..<numProposals {
      var bestClass = 0
      var bestScore: Float = 0
      for c in 0..<Self.numClasses {
        let channel = 4 + c
        let s = read(channel * channelStride + i * proposalStride)
        if s > bestScore {
          bestScore = s
          bestClass = c
        }
      }
      if Double(bestScore) >= Self.confidenceThreshold {
        let prev = bestPerClass[bestClass] ?? 0
        if Double(bestScore) > prev {
          bestPerClass[bestClass] = Double(bestScore)
        }
      }
    }
    return bestPerClass.map { NudeNetDetection(classIdx: $0.key, confidence: $0.value) }
  }
}
