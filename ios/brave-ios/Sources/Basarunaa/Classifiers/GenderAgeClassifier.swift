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
  /// Raw softmax / sigmoid probabilities — kept so the pipeline can log
  /// the per-classifier signal even after picking a winner.
  let pFemale: Double
  let pMale: Double
  /// Crop image actually fed to the model (e.g. 96×96 BGRA for InsightFace,
  /// 192×256 for PPLCNet). Only set when the caller requests it via the
  /// `wantsCropImage` flag — used by the debug overlay to display the
  /// exact bytes the classifier saw.
  let cropImage: CGImage?
}

/// InsightFace genderage classifier (96×96 RGB raw [0,255]). The CoreML
/// model is converted with `color_layout="RGB"` (cf. convert-to-coreml.py).
/// We feed a `kCVPixelFormatType_32BGRA` pixel buffer ; CoreML reorders the
/// channels to RGB internally. The variant of `genderage.onnx` shipped here
/// was trained on RGB pixels (POC `normalization='raw'`) — using BGR would
/// flip the softmax on borderline faces.
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

  /// Crop a 96×96 face patch from `image` using `faceBbox` + keypoints and
  /// run gender classification. The crop is rotated to align the eyes
  /// horizontally à la POC (`alignFace.js`). When `wantsCropImage` is true,
  /// the returned `GenderClassification.cropImage` is the 96×96 BGRA bitmap
  /// fed to the model — used by the debug overlay strip.
  func classify(
    image: CGImage,
    faceBbox: CGRect,
    keypoints: [(point: CGPoint, confidence: Double)],
    wantsCropImage: Bool = false
  ) throws -> GenderClassification? {
    guard let aligned = FaceAlign.alignedFaceCrop(
      image: image,
      faceBbox: faceBbox,
      keypoints: keypoints,
      outputSize: Int(Self.inputSize)
    ) else { return nil }

    // Pack the BGRA bytes into a CVPixelBuffer — exactly what CoreML
    // expects for the model converted with `color_layout="BGR"`.
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
    let context = CIContext(options: [.useSoftwareRenderer: false])
    let extent = CGRect(x: 0, y: 0, width: Self.inputSize, height: Self.inputSize)
    context.render(
      CIImage(cgImage: aligned),
      to: buffer,
      bounds: extent,
      colorSpace: CGColorSpaceCreateDeviceRGB()
    )

    // Diagnostic — sample a centre pixel from the 96×96 buffer to check the
    // channel order (BGRA byte order is B,G,R,A — face skin should have
    // B<G<R for warm tones). Compared against the POC macOS pipeline on
    // the same image to confirm we're feeding the same bytes.
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    let centreB: UInt8, centreG: UInt8, centreR: UInt8
    if let base = CVPixelBufferGetBaseAddress(buffer) {
      let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
      let cx = Int(Self.inputSize) / 2
      let cy = Int(Self.inputSize) / 2
      let offset = cy * rowBytes + cx * 4
      let p = base.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
      centreB = p[0]; centreG = p[1]; centreR = p[2]
    } else {
      centreB = 0; centreG = 0; centreR = 0
    }
    CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
    // POC parity : the rotated aligned crop replaces the axis-aligned
    // squareCrop reported in previous logs. Log the *swapped* angle (the
    // value actually used for the rotation) — the raw atan2 returns ±180°
    // for face-camera people because COCO uses anatomical left/right.
    let kp1 = keypoints.indices.contains(1) ? keypoints[1] : (point: .zero, confidence: 0)
    let kp2 = keypoints.indices.contains(2) ? keypoints[2] : (point: .zero, confidence: 0)
    let (leftPt, rightPt) = kp1.point.x <= kp2.point.x ? (kp1.point, kp2.point) : (kp2.point, kp1.point)
    let eyeAngleDeg = atan2(rightPt.y - leftPt.y, rightPt.x - leftPt.x) * 180 / .pi
    let useRot = kp1.confidence > 0.3 && kp2.confidence > 0.3
    log.info(
      """
      face crop: imgRect=\(faceBbox.debugDescription, privacy: .public) \
      useRot=\(useRot, privacy: .public) eyeAngle=\(String(format: "%.1f", eyeAngleDeg), privacy: .public)° \
      eyeConfL=\(String(format: "%.2f", kp1.confidence), privacy: .public) \
      eyeConfR=\(String(format: "%.2f", kp2.confidence), privacy: .public) \
      centrePx(BGRA)=B\(centreB, privacy: .public)/G\(centreG, privacy: .public)/R\(centreR, privacy: .public)
      """
    )

    let input = try MLDictionaryFeatureProvider(dictionary: ["image": buffer])
    let output = try model.prediction(from: input)
    guard let array = output.featureValue(for: outputName)?.multiArrayValue else {
      throw BasarunaaError.inferenceFailed("GenderAge output missing")
    }
    return decode(output: array, cropImage: wantsCropImage ? aligned : nil)
  }

  /// InsightFace genderage output convention: first 2 values are gender logits
  /// (index 0 = female, index 1 = male), trailing values encode age. We apply
  /// softmax on the first 2 to get gender confidence.
  private func decode(output: MLMultiArray, cropImage: CGImage?) -> GenderClassification? {
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
      return GenderClassification(gender: .male, confidence: pMale, pFemale: pFemale, pMale: pMale, cropImage: cropImage)
    } else {
      return GenderClassification(gender: .female, confidence: pFemale, pFemale: pFemale, pMale: pMale, cropImage: cropImage)
    }
  }
}
