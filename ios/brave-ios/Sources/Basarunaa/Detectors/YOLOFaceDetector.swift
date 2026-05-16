// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CoreML
import Foundation
import OSLog

/// Internal representation of a YOLOv8-face detection (one face).
struct RawFaceDetection {
  let faceBbox: CGRect
  let confidence: Double
  /// 5 keypoints réorganisés en convention COCO partielle pour matcher la
  /// face_align macOS : [0]=nose, [1]=left_eye, [2]=right_eye,
  /// [3]=left_mouth (à la place de left_ear), [4]=right_mouth.
  let keypoints: [(point: CGPoint, confidence: Double)]
  /// 5 landmarks dans l'ordre natif YOLOv8-face (utile pour InsightFace
  /// `norm_crop` 5-point) : 0=left_eye, 1=right_eye, 2=nose, 3=left_mouth,
  /// 4=right_mouth.
  let landmarks: [(point: CGPoint, confidence: Double)]
}

/// YOLOv8n-face detector running via CoreML on a 640×640 input.
///
/// Port direct du POC `private/extensions/basarunaa/src/detectors/yolo_face.js`.
/// 3 FPN heads (strides 8/16/32), output `[1, 80, H, W]` chacun où H=W=640/stride.
/// Channels: 64 (DFL: 4 distances × 16 bins) + 1 (conf) + 15 (5 landmarks × xyc).
final class YOLOFaceDetector {
  static let inputSize: CGFloat = 640
  static let strides: [Int] = [8, 16, 32]
  static let dflBins: Int = 16
  static let nmsIoUThreshold: Double = 0.4   // POC: 0.4
  static let confThresholdFallback: Double = 0.5  // POC: 0.5

  private let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa.YOLOFace")
  private let model: MLModel
  /// Output names ordered by descending grid size, i.e. strides 8, 16, 32.
  private let outputNamesByStride: [String]

  init() throws {
    guard let url = Bundle.module.url(forResource: "YOLOFace", withExtension: "mlmodelc") else {
      throw BasarunaaError.modelLoadFailed("YOLOFace.mlmodelc not found in bundle")
    }
    let config = MLModelConfiguration()
    config.computeUnits = .all
    self.model = try MLModel(contentsOf: url, configuration: config)

    // CoreML auto-renames numeric ONNX outputs to var_NNN. We don't know
    // which `var_*` corresponds to which stride, but we can sort the 3
    // outputs by grid size (largest = stride 8, smallest = stride 32).
    let descs = model.modelDescription.outputDescriptionsByName
    guard descs.count == 3 else {
      throw BasarunaaError.modelLoadFailed(
        "YOLOFace: expected 3 outputs, got \(descs.count)"
      )
    }
    var ordered: [(name: String, gridSize: Int)] = []
    for (name, desc) in descs {
      // Multi-array shape: [1, 80, H, W]. Use the last dim as grid size.
      guard let shape = desc.multiArrayConstraint?.shape, shape.count == 4 else {
        throw BasarunaaError.modelLoadFailed(
          "YOLOFace output \(name) has unexpected shape"
        )
      }
      ordered.append((name: name, gridSize: shape[3].intValue))
    }
    ordered.sort { $0.gridSize > $1.gridSize }  // 80, 40, 20
    self.outputNamesByStride = ordered.map { $0.name }
    log.info(
      "loaded YOLOFace, outputs (stride 8/16/32) = \(self.outputNamesByStride, privacy: .public)"
    )
  }

  /// Run inference and return faces in original image coords (post-NMS).
  func detect(image: CGImage, confThreshold: Double) throws -> [RawFaceDetection] {
    let originalSize = CGSize(width: image.width, height: image.height)

    // Same letterbox plumbing as YOLO11n-pose (640×640 gray-padded).
    let letterboxed = Letterbox.fit(image: image, to: Self.inputSize, padding: 128)
    guard let pixelBuffer = letterboxed.pixelBuffer else {
      throw BasarunaaError.invalidImage
    }

    let input = try MLDictionaryFeatureProvider(dictionary: ["image": pixelBuffer])
    let output = try model.prediction(from: input)

    let effectiveThr = confThreshold > 0 ? confThreshold : Self.confThresholdFallback
    var candidates: [RawFaceDetection] = []
    for (fpnIdx, outName) in outputNamesByStride.enumerated() {
      guard let arr = output.featureValue(for: outName)?.multiArrayValue else {
        log.error("YOLOFace output \(outName, privacy: .public) missing")
        continue
      }
      let stride = Self.strides[fpnIdx]
      candidates.append(contentsOf: decodeHead(
        tensor: arr,
        stride: stride,
        confThreshold: effectiveThr,
        letterbox: letterboxed,
        originalSize: originalSize
      ))
    }

    log.info(
      "YOLOFace candidates pre-NMS=\(candidates.count, privacy: .public) (conf>=\(String(format: "%.2f", effectiveThr), privacy: .public))"
    )

    // NMS — port du POC nms.js (greedy, sorted by confidence desc, `>` strict).
    let sorted = candidates.sorted { $0.confidence > $1.confidence }
    var kept: [RawFaceDetection] = []
    kept.reserveCapacity(sorted.count)
    for c in sorted {
      var suppressed = false
      for k in kept {
        if Self.iou(c.faceBbox, k.faceBbox) > Self.nmsIoUThreshold {
          suppressed = true
          break
        }
      }
      if !suppressed { kept.append(c) }
    }
    log.info("YOLOFace post-NMS=\(kept.count, privacy: .public)")
    return kept
  }

  // MARK: - DFL decode for one FPN head

  private func decodeHead(
    tensor: MLMultiArray,
    stride: Int,
    confThreshold: Double,
    letterbox: Letterbox.Result,
    originalSize: CGSize
  ) -> [RawFaceDetection] {
    let shape = tensor.shape.map { $0.intValue }
    let strides = tensor.strides.map { $0.intValue }
    guard shape.count == 4, shape[1] == 80 else {
      log.error("YOLOFace head unexpected shape \(shape, privacy: .public)")
      return []
    }
    let channels = shape[1]   // 80
    let gridH = shape[2]
    let gridW = shape[3]
    let cellCount = gridH * gridW
    _ = channels

    let chanStride = strides[1]   // typically gridH * gridW
    let rowStride = strides[2]    // gridW
    let colStride = strides[3]    // 1

    let read: (Int, Int, Int) -> Float
    if tensor.dataType == .float16 {
      let base = tensor.dataPointer.bindMemory(to: Float16.self, capacity: tensor.count)
      read = { ch, gy, gx in
        Float(base[ch * chanStride + gy * rowStride + gx * colStride])
      }
    } else {
      let base = tensor.dataPointer.bindMemory(to: Float.self, capacity: tensor.count)
      read = { ch, gy, gx in
        base[ch * chanStride + gy * rowStride + gx * colStride]
      }
    }

    var out: [RawFaceDetection] = []
    out.reserveCapacity(cellCount / 8)

    let strideD = Double(stride)
    for gy in 0..<gridH {
      for gx in 0..<gridW {
        // Channel 64 = raw logit confidence → sigmoid.
        let rawConf = Double(read(64, gy, gx))
        let conf = 1.0 / (1.0 + exp(-rawConf))
        if conf < confThreshold { continue }

        // Decode DFL : 4 distances × 16 bins, softmax + weighted sum.
        var dists = [Double](repeating: 0, count: 4)
        for d in 0..<4 {
          var vals = [Double](repeating: 0, count: Self.dflBins)
          var maxVal = -Double.infinity
          for b in 0..<Self.dflBins {
            let ch = d * Self.dflBins + b
            let v = Double(read(ch, gy, gx))
            vals[b] = v
            if v > maxVal { maxVal = v }
          }
          var sum = 0.0
          for b in 0..<Self.dflBins {
            vals[b] = exp(vals[b] - maxVal)
            sum += vals[b]
          }
          var dist = 0.0
          for b in 0..<Self.dflBins {
            dist += (vals[b] / sum) * Double(b)
          }
          dists[d] = dist
        }

        // Anchor centre dans le canvas letterboxé.
        let ax = (Double(gx) + 0.5) * strideD
        let ay = (Double(gy) + 0.5) * strideD

        let lx1 = ax - dists[0] * strideD
        let ly1 = ay - dists[1] * strideD
        let lx2 = ax + dists[2] * strideD
        let ly2 = ay + dists[3] * strideD

        // Map back to image coords via letterbox.unmap.
        let topLeft = letterbox.unmap(point: CGPoint(x: lx1, y: ly1))
        let botRight = letterbox.unmap(point: CGPoint(x: lx2, y: ly2))
        var x1 = max(0, Double(topLeft.x))
        var y1 = max(0, Double(topLeft.y))
        var x2 = min(Double(originalSize.width), Double(botRight.x))
        var y2 = min(Double(originalSize.height), Double(botRight.y))
        if x2 <= x1 || y2 <= y1 { continue }
        // Defensive clamp in case the model emits inverted distances.
        if x2 < x1 { swap(&x1, &x2) }
        if y2 < y1 { swap(&y1, &y2) }
        let bbox = CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)

        // Decode 5 landmarks (channels 65-79: each is [x, y, visible]).
        var landmarks: [(point: CGPoint, confidence: Double)] = []
        landmarks.reserveCapacity(5)
        for l in 0..<5 {
          let baseChannel = 65 + l * 3
          let lx = Double(read(baseChannel, gy, gx))
          let ly = Double(read(baseChannel + 1, gy, gx))
          let lv = Double(read(baseChannel + 2, gy, gx))
          let origLetterbox = CGPoint(
            x: lx * strideD + ax,
            y: ly * strideD + ay
          )
          let mapped = letterbox.unmap(point: origLetterbox)
          let visible = 1.0 / (1.0 + exp(-lv))
          landmarks.append((point: mapped, confidence: visible))
        }

        // Re-order to COCO-style (nose, left_eye, right_eye, left_mouth, right_mouth)
        // — pareil que le POC : `face_align.js` consomme kp[1]=left_eye, kp[2]=right_eye.
        let cocoKps: [(point: CGPoint, confidence: Double)] = [
          landmarks[2],   // nose
          landmarks[0],   // left_eye
          landmarks[1],   // right_eye
          landmarks[3],   // left_mouth (instead of left_ear)
          landmarks[4],   // right_mouth (instead of right_ear)
        ]

        out.append(RawFaceDetection(
          faceBbox: bbox,
          confidence: conf,
          keypoints: cocoKps,
          landmarks: landmarks
        ))
      }
    }
    return out
  }

  // MARK: - IoU helper (NMS uses faceBbox).

  private static func iou(_ a: CGRect, _ b: CGRect) -> Double {
    let inter = a.intersection(b)
    if inter.isNull || inter.isEmpty { return 0 }
    let interArea = Double(inter.width * inter.height)
    let union = Double(a.width * a.height + b.width * b.height) - interArea
    if union <= 0 { return 0 }
    return interArea / union
  }
}
