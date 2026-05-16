// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CoreML
import Foundation
import OSLog
import Vision

/// Internal representation of a YOLO-pose detection (one person).
struct RawPersonDetection {
  let bbox: CGRect
  let bodyConfidence: Double
  /// 17 COCO keypoints in original image pixel coords.
  let keypoints: [(point: CGPoint, confidence: Double)]
  /// Face bbox derived from keypoints 0-4 (nose, eyes, ears), in original image coords.
  let faceBbox: CGRect?
  /// Mean confidence over keypoints 0-4 — proxy for face visibility.
  let faceConfidence: Double
}

/// YOLO11n-pose detector running via Vision/CoreML on a 640×640 input.
/// Outputs a `[1, 56, N]` tensor: 4 (xywh) + 1 (objectness) + 51 (17 keypoints × x,y,conf).
final class YOLOPoseDetector {
  static let inputSize: CGFloat = 640
  static let numKeypoints = 17
  static let scoreThresholdFallback: Double = 0.25
  // macOS POC parity (yolo_pose.js + nms.js) — 0.5, pas 0.45. Un threshold
  // trop strict supprime des détections quand 2 personnes se chevauchent
  // (parent + enfant devant, photo TF1/famille-recomposee, 2026-05-16).
  static let nmsIoUThreshold: Double = 0.5

  private let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa.YOLO")
  private let model: MLModel
  private let outputName: String

  init() throws {
    guard let url = Bundle.module.url(forResource: "YOLO11nPose", withExtension: "mlmodelc") else {
      throw BasarunaaError.modelLoadFailed("YOLO11nPose.mlmodelc not found in bundle")
    }
    let config = MLModelConfiguration()
    config.computeUnits = .all
    self.model = try MLModel(contentsOf: url, configuration: config)
    // CoreML auto-renames numeric ONNX output names; pick the single output.
    guard let firstOutput = self.model.modelDescription.outputDescriptionsByName.keys.sorted().first else {
      throw BasarunaaError.modelLoadFailed("YOLO11nPose: no output found")
    }
    self.outputName = firstOutput
    log.info("loaded YOLO11nPose, output=\(firstOutput, privacy: .public)")
  }

  /// Run inference on a CGImage and return non-suppressed person detections in
  /// original image coordinate space.
  func detect(image: CGImage, bodyScoreThreshold: Double) throws -> [RawPersonDetection] {
    let originalSize = CGSize(width: image.width, height: image.height)

    // Letterbox the image into a 640×640 canvas with #808080 padding.
    let letterboxed = Letterbox.fit(image: image, to: Self.inputSize, padding: 128)
    guard let pixelBuffer = letterboxed.pixelBuffer else {
      throw BasarunaaError.invalidImage
    }

    let input = try MLDictionaryFeatureProvider(dictionary: ["image": pixelBuffer])
    let output = try model.prediction(from: input)
    guard let multiArray = output.featureValue(for: outputName)?.multiArrayValue else {
      throw BasarunaaError.inferenceFailed("YOLO output missing")
    }

    let detections = postprocess(
      tensor: multiArray,
      scoreThreshold: bodyScoreThreshold > 0 ? bodyScoreThreshold : Self.scoreThresholdFallback,
      letterbox: letterboxed,
      originalSize: originalSize
    )
    let suppressed = NMS.apply(
      detections: detections,
      iouThreshold: Self.nmsIoUThreshold
    )
    return suppressed
  }

  /// Decode the `[1, 56, N]` tensor into person detections and undo letterbox.
  private func postprocess(
    tensor: MLMultiArray,
    scoreThreshold: Double,
    letterbox: Letterbox.Result,
    originalSize: CGSize
  ) -> [RawPersonDetection] {
    let shape = tensor.shape.map { $0.intValue }
    let strides = tensor.strides.map { $0.intValue }
    log.info("YOLO output shape=\(shape, privacy: .public) strides=\(strides, privacy: .public) dtype=\(tensor.dataType.rawValue, privacy: .public)")

    // Expected: [1, 56, N] (Ultralytics YOLO export). If the layout is
    // [1, N, 56] instead (transposed), we'll detect and swap.
    guard shape.count == 3, shape[0] == 1 else {
      log.error("unexpected YOLO output shape: \(shape, privacy: .public)")
      return []
    }
    let layoutIsCHW = (shape[1] == 56)
    let numProposals = layoutIsCHW ? shape[2] : shape[1]
    let numChannels = layoutIsCHW ? shape[1] : shape[2]
    guard numChannels == 56 else {
      log.error("unexpected YOLO channel count: \(numChannels, privacy: .public)")
      return []
    }
    let channelStride = layoutIsCHW ? strides[1] : strides[2]
    let proposalStride = layoutIsCHW ? strides[2] : strides[1]
    log.info("layout=\(layoutIsCHW ? "CHW" : "HWC", privacy: .public) numProposals=\(numProposals, privacy: .public) chanStride=\(channelStride, privacy: .public) propStride=\(proposalStride, privacy: .public)")

    // CoreML returns the model in Float16 when `compute_precision=FLOAT16`.
    // Read with the correct width to avoid garbage values.
    let read: (Int) -> Float
    if tensor.dataType == .float16 {
      let p = tensor.dataPointer.bindMemory(to: Float16.self, capacity: tensor.count)
      read = { Float(p[$0]) }
    } else {
      let p = tensor.dataPointer.bindMemory(to: Float.self, capacity: tensor.count)
      read = { p[$0] }
    }

    // Group proposals into clusters (centres within 100px in image coords).
    // Helps see if a person YOLO detected on macOS is just below the iOS
    // confBody threshold or completely absent. One log line per cluster
    // avoids the OSLog ~1KB truncation.
    struct Cluster {
      var cx: Double
      var cy: Double
      var maxScore: Float
      var count: Int
    }
    var clusters: [Cluster] = []
    for i in 0..<numProposals {
      let s = read(4 * channelStride + i * proposalStride)
      if s < 0.20 { continue }
      let cx = Double(read(0 * channelStride + i * proposalStride))
      let cy = Double(read(1 * channelStride + i * proposalStride))
      let mapped = letterbox.unmap(point: CGPoint(x: cx, y: cy))
      let ix = Double(mapped.x)
      let iy = Double(mapped.y)
      var found = false
      for k in 0..<clusters.count {
        let dx = clusters[k].cx - ix
        let dy = clusters[k].cy - iy
        if dx * dx + dy * dy < 100 * 100 {
          if s > clusters[k].maxScore { clusters[k].maxScore = s }
          clusters[k].count += 1
          found = true
          break
        }
      }
      if !found {
        clusters.append(Cluster(cx: ix, cy: iy, maxScore: s, count: 1))
      }
    }
    clusters.sort { $0.maxScore > $1.maxScore }
    log.info(
      "YOLO clusters (≥0.20 score, threshold=\(scoreThreshold, privacy: .public)): \(clusters.count, privacy: .public) clusters"
    )
    for (rank, c) in clusters.enumerated() {
      log.info(
        "  cluster #\(rank, privacy: .public) max=\(String(format: "%.3f", c.maxScore), privacy: .public) center=(\(String(format: "%.0f", c.cx), privacy: .public),\(String(format: "%.0f", c.cy), privacy: .public)) count=\(c.count, privacy: .public)"
      )
    }
    let maxScore = clusters.first?.maxScore ?? 0
    log.info("max objectness=\(maxScore, privacy: .public)")

    var results: [RawPersonDetection] = []

    for i in 0..<numProposals {
      let scoreIdx = 4 * channelStride + i * proposalStride
      let score = Double(read(scoreIdx))
      if score < scoreThreshold { continue }

      let cx = Double(read(0 * channelStride + i * proposalStride))
      let cy = Double(read(1 * channelStride + i * proposalStride))
      let w = Double(read(2 * channelStride + i * proposalStride))
      let h = Double(read(3 * channelStride + i * proposalStride))

      let bboxLb = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
      let bbox = letterbox.unmap(rect: bboxLb)
      guard bbox.intersects(CGRect(origin: .zero, size: originalSize)) else { continue }

      var keypoints: [(point: CGPoint, confidence: Double)] = []
      keypoints.reserveCapacity(Self.numKeypoints)
      for k in 0..<Self.numKeypoints {
        let baseChannel = 5 + k * 3
        let kx = Double(read(baseChannel * channelStride + i * proposalStride))
        let ky = Double(read((baseChannel + 1) * channelStride + i * proposalStride))
        let kc = Double(read((baseChannel + 2) * channelStride + i * proposalStride))
        let mapped = letterbox.unmap(point: CGPoint(x: kx, y: ky))
        keypoints.append((point: mapped, confidence: kc))
      }

      let (faceBbox, faceConf) = deriveFaceBbox(from: keypoints)
      _ = numChannels

      results.append(
        RawPersonDetection(
          bbox: bbox,
          bodyConfidence: score,
          keypoints: keypoints,
          faceBbox: faceBbox,
          faceConfidence: faceConf
        )
      )
    }

    return results
  }

  private func deriveFaceBbox(
    from keypoints: [(point: CGPoint, confidence: Double)]
  ) -> (CGRect?, Double) {
    guard keypoints.count >= 5 else { return (nil, 0) }
    let faceKp = Array(keypoints[0..<5])
    let confidences = faceKp.map { $0.confidence }
    let meanConf = confidences.reduce(0, +) / Double(confidences.count)
    let valid = faceKp.filter { $0.confidence > 0.25 }
    guard valid.count >= 2 else { return (nil, meanConf) }

    let xs = valid.map { $0.point.x }
    let ys = valid.map { $0.point.y }
    let minX = xs.min() ?? 0
    let maxX = xs.max() ?? 0
    let minY = ys.min() ?? 0
    let maxY = ys.max() ?? 0
    let w = max(maxX - minX, 1)
    let h = max(maxY - minY, 1)
    // Pad the box around the keypoints to cover the whole face.
    let padX = w * 0.4
    let padY = h * 0.6
    let bbox = CGRect(
      x: minX - padX,
      y: minY - padY,
      width: w + 2 * padX,
      height: h + 2 * padY
    )
    return (bbox, meanConf)
  }
}
