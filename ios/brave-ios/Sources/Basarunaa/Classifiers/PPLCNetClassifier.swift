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

/// PPLCNet pedestrian-attribute classifier — body-based gender fallback used
/// when the face crop is too small or unreliable for InsightFace (gender=nil).
///
/// Input  : 192W × 256H, RGB, ImageNet-normalised (baked into the model).
/// Output : `[1, 26]` sigmoid logits. Index 22 = Female probability.
final class PPLCNetClassifier {
  static let inputWidth: CGFloat = 192
  static let inputHeight: CGFloat = 256
  /// PULC pedestrian-attribute index for the "Female" attribute (sigmoid logit).
  static let femaleAttributeIndex = 22

  private let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa.PPLCNet")
  private let model: MLModel
  private let outputName: String

  init() throws {
    guard let url = Bundle.module.url(forResource: "PPLCNet", withExtension: "mlmodelc") else {
      throw BasarunaaError.modelLoadFailed("PPLCNet.mlmodelc not found in bundle")
    }
    let config = MLModelConfiguration()
    config.computeUnits = .all
    self.model = try MLModel(contentsOf: url, configuration: config)
    guard let firstOutput = self.model.modelDescription.outputDescriptionsByName.keys.sorted().first else {
      throw BasarunaaError.modelLoadFailed("PPLCNet: no output found")
    }
    self.outputName = firstOutput
    log.info("loaded PPLCNet, output=\(firstOutput, privacy: .public)")
  }

  /// Crop the body region from `image` using `bodyBbox` (no padding, direct
  /// stretch to 192×256 per the POC), run inference, decode the female
  /// attribute as a male/female classification.
  func classify(
    image: CGImage,
    bodyBbox: CGRect
  ) throws -> GenderClassification? {
    let imageSize = CGSize(width: image.width, height: image.height)
    let cropRect = bodyBbox.intersection(CGRect(origin: .zero, size: imageSize))
    guard cropRect.width > 8, cropRect.height > 8 else { return nil }
    guard let cropped = image.cropping(to: cropRect) else { return nil }

    // Resize 192×256 via CoreImage (stretch, no aspect preservation — POC behaviour).
    let ciImage = CIImage(cgImage: cropped)
    let scaleX = Self.inputWidth / CGFloat(cropped.width)
    let scaleY = Self.inputHeight / CGFloat(cropped.height)
    let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

    var pixelBuffer: CVPixelBuffer?
    let attrs: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ]
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(Self.inputWidth), Int(Self.inputHeight),
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &pixelBuffer
    )
    guard let buffer = pixelBuffer else {
      throw BasarunaaError.inferenceFailed("could not allocate 192x256 pixel buffer")
    }
    let context = CIContext(options: [.useSoftwareRenderer: false])
    let extent = CGRect(x: 0, y: 0, width: Self.inputWidth, height: Self.inputHeight)
    context.render(scaled, to: buffer, bounds: extent, colorSpace: CGColorSpaceCreateDeviceRGB())

    let input = try MLDictionaryFeatureProvider(dictionary: ["image": buffer])
    let output = try model.prediction(from: input)
    guard let array = output.featureValue(for: outputName)?.multiArrayValue else {
      throw BasarunaaError.inferenceFailed("PPLCNet output missing")
    }
    return decode(output: array)
  }

  private func decode(output: MLMultiArray) -> GenderClassification? {
    let count = output.count
    guard count > Self.femaleAttributeIndex else {
      log.error("PPLCNet output too small: \(count, privacy: .public)")
      return nil
    }
    let read: (Int) -> Float
    if output.dataType == .float16 {
      let p = output.dataPointer.bindMemory(to: Float16.self, capacity: count)
      read = { Float(p[$0]) }
    } else {
      let p = output.dataPointer.bindMemory(to: Float.self, capacity: count)
      read = { p[$0] }
    }
    let femaleProb = Double(read(Self.femaleAttributeIndex))
    let maleProb = 1.0 - femaleProb
    // The POC reports max(p, 1-p) as confidence (raw [0,1]).
    if femaleProb >= 0.5 {
      return GenderClassification(gender: .female, confidence: femaleProb, pFemale: femaleProb, pMale: maleProb)
    } else {
      return GenderClassification(gender: .male, confidence: maleProb, pFemale: femaleProb, pMale: maleProb)
    }
  }
}
