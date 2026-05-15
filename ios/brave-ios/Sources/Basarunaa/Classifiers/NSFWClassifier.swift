// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CoreImage
import CoreML
import Foundation
import OSLog
import UIKit

struct NSFWResult {
  /// True if `score >= threshold` — image should be blurred regardless of
  /// person detection.
  let isNsfw: Bool
  /// Softmax probability of the NSFW class (0..1).
  let score: Double
}

/// Marqo ViT-Tiny full-image NSFW classifier (384×384 RGB).
///
/// Input  : 384×384, RGB, normalized `(px/255 - 0.5) / 0.5` (i.e., [-1, 1])
///          — baked into the CoreML model via ImageType scale/bias.
/// Output : `[1, 2]` logits. Index 0 = NSFW, index 1 = SFW. Softmax → score.
final class NSFWClassifier {
  static let inputSize: CGFloat = 384
  static let defaultThreshold: Double = 0.5

  private let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa.NSFW")
  private let model: MLModel
  private let outputName: String

  init() throws {
    guard let url = Bundle.module.url(forResource: "NsfwMarqo", withExtension: "mlmodelc") else {
      throw BasarunaaError.modelLoadFailed("NsfwMarqo.mlmodelc not found in bundle")
    }
    let config = MLModelConfiguration()
    config.computeUnits = .all
    self.model = try MLModel(contentsOf: url, configuration: config)
    guard let firstOutput = self.model.modelDescription.outputDescriptionsByName.keys.sorted().first else {
      throw BasarunaaError.modelLoadFailed("NSFW: no output found")
    }
    self.outputName = firstOutput
    log.info("loaded NsfwMarqo, output=\(firstOutput, privacy: .public)")
  }

  /// Classify a full image as NSFW or SFW. The image is resized (stretched)
  /// to 384×384 — POC behaviour for Marqo ViT-Tiny (no letterbox needed for
  /// the classifier; spatial context is preserved enough at this resolution).
  func classify(image: CGImage, threshold: Double = NSFWClassifier.defaultThreshold) throws -> NSFWResult {
    let ciImage = CIImage(cgImage: image)
    let scaleX = Self.inputSize / CGFloat(image.width)
    let scaleY = Self.inputSize / CGFloat(image.height)
    let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

    var pixelBuffer: CVPixelBuffer?
    let attrs: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ]
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(Self.inputSize), Int(Self.inputSize),
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &pixelBuffer
    )
    guard let buffer = pixelBuffer else {
      throw BasarunaaError.inferenceFailed("could not allocate 384x384 pixel buffer")
    }
    let context = CIContext(options: [.useSoftwareRenderer: false])
    let extent = CGRect(x: 0, y: 0, width: Self.inputSize, height: Self.inputSize)
    context.render(scaled, to: buffer, bounds: extent, colorSpace: CGColorSpaceCreateDeviceRGB())

    let input = try MLDictionaryFeatureProvider(dictionary: ["image": buffer])
    let output = try model.prediction(from: input)
    guard let array = output.featureValue(for: outputName)?.multiArrayValue else {
      throw BasarunaaError.inferenceFailed("NSFW output missing")
    }
    return decode(output: array, threshold: threshold)
  }

  private func decode(output: MLMultiArray, threshold: Double) -> NSFWResult {
    let count = output.count
    let read: (Int) -> Float
    if output.dataType == .float16 {
      let p = output.dataPointer.bindMemory(to: Float16.self, capacity: count)
      read = { Float(p[$0]) }
    } else {
      let p = output.dataPointer.bindMemory(to: Float.self, capacity: count)
      read = { p[$0] }
    }
    let logitNsfw = Double(read(0))
    let logitSfw = Double(read(1))
    let maxLogit = max(logitNsfw, logitSfw)
    let eNsfw = exp(logitNsfw - maxLogit)
    let eSfw = exp(logitSfw - maxLogit)
    let score = eNsfw / (eNsfw + eSfw)
    return NSFWResult(isNsfw: score >= threshold, score: score)
  }
}
