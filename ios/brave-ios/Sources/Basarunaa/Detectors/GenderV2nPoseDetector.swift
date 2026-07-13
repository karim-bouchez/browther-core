// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CoreML
import Foundation
import OSLog

/// Détecteur single-shot gender-v2n (yolo11n-pose fine-tuné 3 classes
/// male/female/child + 17 kpts COCO) via CoreML. Une SEULE inférence remplace
/// toute la cascade (YOLO11n-pose + YOLOv8n-face + genderage + PPLCNet) : la
/// boîte porte directement le genre.
///
/// Sortie `[1, 58, N]` = 4 (xywh) + 3 (scores classe) + 51 (17 kpts × xyc).
/// Le DÉCODAGE (argmax classe, un-letterbox, faceBbox, NMS) vit dans le module
/// PUR `GenderV2nDecode` — validé contre le golden `tests/golden/gender-v2n/`.
/// Ce fichier ne fait que : letterbox → CoreML → accès MLMultiArray → decode.
final class GenderV2nPoseDetector: @unchecked Sendable {
  static let inputSize: CGFloat = 640
  static let scoreThresholdFallback = GenderV2nDecode.defaultConfThreshold
  static let nmsIoUThreshold = GenderV2nDecode.defaultIoUThreshold
  static let numChannels = 58  // 4 + 3 + 51

  private let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa.GenderV2n")
  private let model: MLModel
  private let outputName: String

  init() throws {
    guard let url = Bundle.module.url(forResource: "GenderV2nPose", withExtension: "mlmodelc")
    else {
      throw BasarunaaError.modelLoadFailed("GenderV2nPose.mlmodelc not found in bundle")
    }
    let config = MLModelConfiguration()
    config.computeUnits = .all
    self.model = try MLModel(contentsOf: url, configuration: config)
    guard
      let firstOutput = self.model.modelDescription.outputDescriptionsByName.keys.sorted().first
    else {
      throw BasarunaaError.modelLoadFailed("GenderV2nPose: no output found")
    }
    self.outputName = firstOutput
    log.info("loaded GenderV2nPose, output=\(firstOutput, privacy: .public)")
  }

  /// Détecte les persons dans l'espace image original. Renvoie les persons
  /// BRUTES (pur extracteur — aucune décision de flou : la policy vit dans
  /// `core/policy.ts`, appliquée côté bundle webkit TS).
  func detect(image: CGImage, scoreThreshold: Double) throws -> [GenderV2nPersonRaw] {
    let letterbox = Letterbox.fit(image: image, to: Self.inputSize, padding: 128)
    guard let pixelBuffer = letterbox.pixelBuffer else {
      throw BasarunaaError.invalidImage
    }

    let input = try MLDictionaryFeatureProvider(dictionary: ["image": pixelBuffer])
    let output = try model.prediction(from: input)
    guard let multiArray = output.featureValue(for: outputName)?.multiArrayValue else {
      throw BasarunaaError.inferenceFailed("GenderV2nPose output missing")
    }

    let shape = multiArray.shape.map { $0.intValue }
    let strides = multiArray.strides.map { $0.intValue }
    guard shape.count == 3, shape[0] == 1 else {
      log.error("unexpected output shape: \(shape, privacy: .public)")
      return []
    }
    // Ultralytics export = [1, 58, N] (CHW). CoreML peut transposer en [1, N, 58].
    let layoutIsCHW = (shape[1] == Self.numChannels)
    let numDet = layoutIsCHW ? shape[2] : shape[1]
    let numChan = layoutIsCHW ? shape[1] : shape[2]
    guard numChan == Self.numChannels else {
      log.error("unexpected channel count: \(numChan, privacy: .public)")
      return []
    }
    let channelStride = layoutIsCHW ? strides[1] : strides[2]
    let proposalStride = layoutIsCHW ? strides[2] : strides[1]

    // CoreML renvoie float16 quand compute_precision=FLOAT16 (notre cas).
    let read: (Int) -> Double
    if multiArray.dataType == .float16 {
      let p = multiArray.dataPointer.bindMemory(to: Float16.self, capacity: multiArray.count)
      read = { Double(p[$0]) }
    } else if multiArray.dataType == .float32 {
      let p = multiArray.dataPointer.bindMemory(to: Float.self, capacity: multiArray.count)
      read = { Double(p[$0]) }
    } else {
      let p = multiArray.dataPointer.bindMemory(to: Double.self, capacity: multiArray.count)
      read = { p[$0] }
    }

    let threshold = scoreThreshold > 0 ? scoreThreshold : Self.scoreThresholdFallback
    let persons = GenderV2nDecode.decode(
      numChannels: numChan,
      numDetections: numDet,
      scale: Double(letterbox.scale),
      padX: Double(letterbox.offset.x),
      padY: Double(letterbox.offset.y),
      srcWidth: Double(image.width),
      srcHeight: Double(image.height),
      confThreshold: threshold,
      iouThreshold: Self.nmsIoUThreshold,
      value: { channel, det in read(channel * channelStride + det * proposalStride) }
    )
    log.info("detect done: persons=\(persons.count, privacy: .public)")
    return persons
  }
}
