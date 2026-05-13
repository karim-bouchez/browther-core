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

struct GenderClassification {
  let gender: Gender
  let confidence: Double
}

/// InsightFace genderage classifier (96×96 BGR raw). The CoreML model was
/// converted with `color_layout="BGR"` so we feed RGB pixels directly and the
/// model handles the channel swap internally.
final class GenderAgeClassifier {
  static let inputSize: CGFloat = 96

  private let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa.Gender")
  private let model: MLModel
  private let outputName: String

  init() throws {
    guard let url = Bundle.module.url(forResource: "GenderAge", withExtension: "mlmodelc") else {
      throw BasarunaaError.modelLoadFailed("GenderAge.mlmodelc not found in bundle")
    }
    let config = MLModelConfiguration()
    config.computeUnits = .all
    self.model = try MLModel(contentsOf: url, configuration: config)
    guard let firstOutput = self.model.modelDescription.outputDescriptionsByName.keys.sorted().first else {
      throw BasarunaaError.modelLoadFailed("GenderAge: no output found")
    }
    self.outputName = firstOutput
    log.info("loaded GenderAge, output=\(firstOutput, privacy: .public)")
  }

  /// Crop a 96×96 face patch from `image` using `faceBbox` and run gender
  /// classification. Uses a square crop centered on the face bbox.
  func classify(
    image: CGImage,
    faceBbox: CGRect,
    keypoints: [(point: CGPoint, confidence: Double)]
  ) throws -> GenderClassification? {
    let imageSize = CGSize(width: image.width, height: image.height)
    let cropRect = FaceAlign.squareCropRect(
      around: faceBbox,
      keypoints: keypoints,
      imageSize: imageSize
    )
    guard cropRect.width > 4, cropRect.height > 4 else { return nil }
    guard let cropped = image.cropping(to: cropRect) else { return nil }

    // Resize the crop to 96×96 via CoreImage.
    let ciImage = CIImage(cgImage: cropped)
    let scaleX = Self.inputSize / CGFloat(cropped.width)
    let scaleY = Self.inputSize / CGFloat(cropped.height)
    let scaled = ciImage.transformed(
      by: CGAffineTransform(scaleX: scaleX, y: scaleY)
    )

    let context = CIContext(options: [.useSoftwareRenderer: false])
    let extent = CGRect(x: 0, y: 0, width: Self.inputSize, height: Self.inputSize)
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
      throw BasarunaaError.inferenceFailed("could not allocate 96x96 pixel buffer")
    }
    context.render(scaled, to: buffer, bounds: extent, colorSpace: CGColorSpaceCreateDeviceRGB())

    let input = try MLDictionaryFeatureProvider(dictionary: ["image": buffer])
    let output = try model.prediction(from: input)
    guard let array = output.featureValue(for: outputName)?.multiArrayValue else {
      throw BasarunaaError.inferenceFailed("GenderAge output missing")
    }
    return decode(output: array)
  }

  /// InsightFace genderage output convention: first 2 values are gender logits
  /// (index 0 = female, index 1 = male), trailing values encode age. We apply
  /// softmax on the first 2 to get gender confidence.
  private func decode(output: MLMultiArray) -> GenderClassification? {
    let count = output.count
    guard count >= 2 else { return nil }
    let read: (Int) -> Float
    if output.dataType == .float16 {
      let p = output.dataPointer.bindMemory(to: Float16.self, capacity: count)
      read = { Float(p[$0]) }
    } else {
      let p = output.dataPointer.bindMemory(to: Float.self, capacity: count)
      read = { p[$0] }
    }
    let logitFemale = Double(read(0))
    let logitMale = Double(read(1))
    let maxLogit = max(logitFemale, logitMale)
    let eFemale = exp(logitFemale - maxLogit)
    let eMale = exp(logitMale - maxLogit)
    let sum = eFemale + eMale
    let pFemale = eFemale / sum
    let pMale = eMale / sum
    if pMale >= pFemale {
      return GenderClassification(gender: .male, confidence: pMale)
    } else {
      return GenderClassification(gender: .female, confidence: pFemale)
    }
  }
}
