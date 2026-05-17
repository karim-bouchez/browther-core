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
final class PPLCNetClassifier: @unchecked Sendable {
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

  /// Crop the body region from `image` using `bodyBbox`, optionally gray-out
  /// pixels outside the body polygon mask (parity macOS
  /// `preprocessForClassification`), stretch to 192×256, run inference,
  /// decode the female attribute as a male/female classification.
  ///
  /// Pass `bodyPolygonPoints=nil` (synthetic body from face detector, no
  /// keypoints) to skip the masking step — POC uses the same fallback.
  /// The polygon is rasterized directly into the 192×256 buffer space
  /// (no per-pixel coord remap in the inner loop, 2026-05-17).
  func classify(
    image: CGImage,
    bodyBbox: CGRect,
    bodyPolygonPoints: [CGPoint]? = nil,
    wantsCropImage: Bool = false
  ) throws -> GenderClassification? {
    let imageSize = CGSize(width: image.width, height: image.height)
    let cropRect = bodyBbox.intersection(CGRect(origin: .zero, size: imageSize))
    guard cropRect.width > 8, cropRect.height > 8 else { return nil }
    guard let cropped = image.cropping(to: cropRect) else { return nil }

    // Render the crop into a BGRA CGContext with gray (#808080) background,
    // stretched to 192×256 like POC `preprocessForClassification`. CG gives
    // us pixel access so we can apply the polygon mask before handing the
    // buffer to CoreML.
    let outW = Int(Self.inputWidth)
    let outH = Int(Self.inputHeight)
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
      | CGImageAlphaInfo.noneSkipFirst.rawValue
    guard let ctx = CGContext(
      data: nil,
      width: outW,
      height: outH,
      bitsPerComponent: 8,
      bytesPerRow: outW * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: bitmapInfo
    ), let buf = ctx.data else {
      throw BasarunaaError.inferenceFailed("could not allocate 192x256 CGContext")
    }
    ctx.setFillColor(gray: 128.0 / 255.0, alpha: 1.0)
    ctx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))
    ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: outW, height: outH))

    if let points = bodyPolygonPoints, points.count >= 3 {
      let localMask = BodyPolygon.rasterizeForCrop(
        points: points,
        sourceBbox: cropRect,
        destWidth: outW,
        destHeight: outH
      )
      applyMaskGrayOut(
        contextData: buf,
        contextWidth: outW,
        contextHeight: outH,
        mask: localMask
      )
    }

    // Repack the BGRA bytes into a CVPixelBuffer (CoreML expects this format
    // with the `color_layout="RGB"` setting; it auto-swaps internally).
    var pixelBuffer: CVPixelBuffer?
    let attrs: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ]
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      outW, outH,
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &pixelBuffer
    )
    guard let pb = pixelBuffer else {
      throw BasarunaaError.inferenceFailed("could not allocate 192x256 pixel buffer")
    }
    CVPixelBufferLockBaseAddress(pb, [])
    if let dst = CVPixelBufferGetBaseAddress(pb) {
      let dstStride = CVPixelBufferGetBytesPerRow(pb)
      let srcStride = outW * 4
      if dstStride == srcStride {
        memcpy(dst, buf, outH * srcStride)
      } else {
        for row in 0..<outH {
          memcpy(
            dst.advanced(by: row * dstStride),
            buf.advanced(by: row * srcStride),
            srcStride
          )
        }
      }
    }
    CVPixelBufferUnlockBaseAddress(pb, [])

    let input = try MLDictionaryFeatureProvider(dictionary: ["image": pb])
    let output = try model.prediction(from: input)
    guard let array = output.featureValue(for: outputName)?.multiArrayValue else {
      throw BasarunaaError.inferenceFailed("PPLCNet output missing")
    }
    // Capture the exact 192×256 BGRA crop fed to CoreML (with mask
    // gray-out already applied) for the debug strip.
    let cropImage: CGImage? = wantsCropImage ? ctx.makeImage() : nil
    return decode(output: array, cropImage: cropImage)
  }

  /// Apply the polygon mask (already rasterized in 192×256 buffer space) to
  /// gray-out pixels outside the body silhouette (#808080). BGRA byte order
  /// → touch the first 3 bytes per pixel.
  private func applyMaskGrayOut(
    contextData: UnsafeMutableRawPointer,
    contextWidth: Int,
    contextHeight: Int,
    mask: BodyPolygon.Mask
  ) {
    let ptr = contextData.assumingMemoryBound(to: UInt8.self)
    let outW = contextWidth
    let outH = contextHeight
    mask.data.withUnsafeBufferPointer { mb in
      guard let mPtr = mb.baseAddress else { return }
      for py in 0..<outH {
        let rowOff = py * outW
        for px in 0..<outW {
          if mPtr[rowOff + px] == 0 {
            let off = (rowOff + px) * 4
            ptr[off] = 128
            ptr[off + 1] = 128
            ptr[off + 2] = 128
          }
        }
      }
    }
  }

  private func decode(output: MLMultiArray, cropImage: CGImage?) -> GenderClassification? {
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
      return GenderClassification(gender: .female, confidence: femaleProb, pFemale: femaleProb, pMale: maleProb, cropImage: cropImage)
    } else {
      return GenderClassification(gender: .male, confidence: maleProb, pFemale: femaleProb, pMale: maleProb, cropImage: cropImage)
    }
  }
}
