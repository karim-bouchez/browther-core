// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CoreML
import Foundation
import OSLog

/// Lightweight bbox emitted by the NanoDet sentinel — no keypoints, no face,
/// no gender. Used to smooth-track person positions between two expensive
/// YOLO runs and to event-trigger a YOLO refresh when a new person enters
/// the frame.
public struct SentinelBbox: Sendable {
  public let bbox: CGRect
  public let confidence: Double
}

/// NanoDet-Plus-m 320 sentinel detector — anchor-free, 4 stride levels
/// `[8, 16, 32, 64]`. Output `[1, 2125, 112]` = 80 class scores (already
/// post-sigmoid in this export) + 32 bbox regression (4 × reg_max+1 = 4 × 8)
/// decoded via distribution focal loss.
///
/// Ported line-for-line from `private/extensions/basarunaa/src/detectors/nanodet.js`.
/// Do not "simplify" — see `private/extensions/basarunaa/CLAUDE.md` § règle d'or.
final class NanoDetSentinelDetector: @unchecked Sendable {
  static let inputSize: CGFloat = 320
  static let numClasses = 80
  static let personClassIndex = 0
  static let regMax = 7
  static let strides: [Int] = [8, 16, 32, 64]
  /// Per POC default (`nanodet.js` constructor) — sentinel is intentionally
  /// permissive vs YOLO's 0.25 body threshold; tracking smooths false-positives.
  static let confThresholdFallback: Double = 0.3
  static let iouThreshold: Double = 0.5
  static let minBoxSize: CGFloat = 8

  private struct GridCell {
    let x: Int
    let y: Int
    let stride: Int
  }

  private let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa.NanoDet")
  private let model: MLModel
  private let outputName: String
  private let grids: [GridCell]

  init() throws {
    guard let url = Bundle.module.url(forResource: "NanoDet", withExtension: "mlmodelc") else {
      throw BasarunaaError.modelLoadFailed("NanoDet.mlmodelc not found in bundle")
    }
    let config = MLModelConfiguration()
    config.computeUnits = .all
    self.model = try MLModel(contentsOf: url, configuration: config)
    guard let firstOutput = self.model.modelDescription.outputDescriptionsByName.keys.sorted().first else {
      throw BasarunaaError.modelLoadFailed("NanoDet: no output found")
    }
    self.outputName = firstOutput

    var built: [GridCell] = []
    let s = Int(Self.inputSize)
    for stride in Self.strides {
      let size = (s + stride - 1) / stride  // ceil
      for y in 0..<size {
        for x in 0..<size {
          built.append(GridCell(x: x, y: y, stride: stride))
        }
      }
    }
    self.grids = built
    log.info("loaded NanoDet, output=\(firstOutput, privacy: .public) grids=\(built.count, privacy: .public)")
  }

  /// Run inference and return non-suppressed person bboxes in the original
  /// image coordinate space. `confThreshold` mirrors the POC's per-call
  /// override; pass <= 0 to use the default.
  func detect(image: CGImage, confThreshold: Double = 0) throws -> [SentinelBbox] {
    let originalSize = CGSize(width: image.width, height: image.height)

    let letterboxed = Letterbox.fit(image: image, to: Self.inputSize, padding: 128)
    guard let pixelBuffer = letterboxed.pixelBuffer else {
      throw BasarunaaError.invalidImage
    }

    let input = try MLDictionaryFeatureProvider(dictionary: ["image": pixelBuffer])
    let output = try model.prediction(from: input)
    guard let multiArray = output.featureValue(for: outputName)?.multiArrayValue else {
      throw BasarunaaError.inferenceFailed("NanoDet output missing")
    }

    let threshold = confThreshold > 0 ? confThreshold : Self.confThresholdFallback
    let raw = postprocess(
      tensor: multiArray,
      scoreThreshold: threshold,
      letterbox: letterboxed,
      originalSize: originalSize
    )
    return nms(boxes: raw, iouThreshold: Self.iouThreshold)
  }

  /// Decode `[1, 2125, 112]` (or transposed `[1, 112, 2125]`) into person bboxes.
  /// Scores are class index 0; bbox uses distribution focal loss over the last 32
  /// channels (`4 × (regMax+1)`).
  private func postprocess(
    tensor: MLMultiArray,
    scoreThreshold: Double,
    letterbox: Letterbox.Result,
    originalSize: CGSize
  ) -> [SentinelBbox] {
    let shape = tensor.shape.map { $0.intValue }
    let strides = tensor.strides.map { $0.intValue }
    log.info("NanoDet output shape=\(shape, privacy: .public) strides=\(strides, privacy: .public) dtype=\(tensor.dataType.rawValue, privacy: .public)")

    guard shape.count == 3, shape[0] == 1 else {
      log.error("unexpected NanoDet output shape: \(shape, privacy: .public)")
      return []
    }
    let featLen = Self.numClasses + 4 * (Self.regMax + 1)  // 80 + 32 = 112
    let layoutIsCellMajor = (shape[1] == grids.count)
    let numCells = layoutIsCellMajor ? shape[1] : shape[2]
    let numChannels = layoutIsCellMajor ? shape[2] : shape[1]
    guard numChannels == featLen else {
      log.error("unexpected NanoDet channel count: \(numChannels, privacy: .public) (expected \(featLen, privacy: .public))")
      return []
    }
    let cellStride = layoutIsCellMajor ? strides[1] : strides[2]
    let channelStride = layoutIsCellMajor ? strides[2] : strides[1]

    let read: (Int) -> Float
    if tensor.dataType == .float16 {
      let p = tensor.dataPointer.bindMemory(to: Float16.self, capacity: tensor.count)
      read = { Float(p[$0]) }
    } else {
      let p = tensor.dataPointer.bindMemory(to: Float.self, capacity: tensor.count)
      read = { p[$0] }
    }

    let regLen = Self.regMax + 1
    let regBaseChannel = Self.numClasses
    let imageRect = CGRect(origin: .zero, size: originalSize)
    var results: [SentinelBbox] = []
    results.reserveCapacity(64)

    let cellCount = min(numCells, grids.count)
    for i in 0..<cellCount {
      let scoreIdx = i * cellStride + Self.personClassIndex * channelStride
      let score = Double(read(scoreIdx))
      if score < scoreThreshold { continue }

      var distances = [Double](repeating: 0, count: 4)
      for d in 0..<4 {
        let start = i * cellStride + (regBaseChannel + d * regLen) * channelStride

        var maxVal: Float = -.infinity
        for r in 0..<regLen {
          let v = read(start + r * channelStride)
          if v > maxVal { maxVal = v }
        }
        var sum: Float = 0
        var weighted: Float = 0
        for r in 0..<regLen {
          let e = expf(read(start + r * channelStride) - maxVal)
          sum += e
          weighted += e * Float(r)
        }
        distances[d] = sum > 0 ? Double(weighted / sum) : 0
      }

      let cell = grids[i]
      let st = Double(cell.stride)
      let cx = (Double(cell.x) + 0.5) * st
      let cy = (Double(cell.y) + 0.5) * st

      let mx1 = cx - distances[0] * st
      let my1 = cy - distances[1] * st
      let mx2 = cx + distances[2] * st
      let my2 = cy + distances[3] * st

      let lbRect = CGRect(x: mx1, y: my1, width: mx2 - mx1, height: my2 - my1)
      let mapped = letterbox.unmap(rect: lbRect)
      let clipped = mapped.intersection(imageRect)
      if clipped.isNull || clipped.isEmpty { continue }
      if clipped.width < Self.minBoxSize || clipped.height < Self.minBoxSize { continue }

      results.append(SentinelBbox(bbox: clipped, confidence: score))
    }

    log.info("NanoDet kept=\(results.count, privacy: .public) (threshold=\(scoreThreshold, privacy: .public))")
    return results
  }

  /// Greedy NMS on simple bbox+confidence tuples. Mirrors `utils/nms.js` POC.
  private func nms(boxes: [SentinelBbox], iouThreshold: Double) -> [SentinelBbox] {
    let sorted = boxes.sorted { $0.confidence > $1.confidence }
    var kept: [SentinelBbox] = []
    kept.reserveCapacity(sorted.count)
    for b in sorted {
      var suppressed = false
      for k in kept {
        if iou(b.bbox, k.bbox) > iouThreshold {
          suppressed = true
          break
        }
      }
      if !suppressed { kept.append(b) }
    }
    return kept
  }

  private func iou(_ a: CGRect, _ b: CGRect) -> Double {
    let inter = a.intersection(b)
    if inter.isNull || inter.isEmpty { return 0 }
    let interArea = Double(inter.width * inter.height)
    let unionArea = Double(a.width * a.height + b.width * b.height) - interArea
    return unionArea > 0 ? interArea / unionArea : 0
  }
}
