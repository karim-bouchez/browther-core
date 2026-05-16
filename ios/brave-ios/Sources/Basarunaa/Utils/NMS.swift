// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import OSLog

/// Standard greedy non-maximum suppression on person detections.
enum NMS {
  private static let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa.NMS")

  static func apply(
    detections: [RawPersonDetection],
    iouThreshold: Double
  ) -> [RawPersonDetection] {
    let sorted = detections.sorted { $0.bodyConfidence > $1.bodyConfidence }
    var kept: [RawPersonDetection] = []
    kept.reserveCapacity(sorted.count)
    log.info("input=\(sorted.count, privacy: .public) iouThr=\(iouThreshold, privacy: .public)")
    for det in sorted {
      var suppressed = false
      var maxIoU = 0.0
      var suppressedBy = -1
      for (idx, keptDet) in kept.enumerated() {
        let i = iou(det.bbox, keptDet.bbox)
        if i > maxIoU { maxIoU = i }
        if i > iouThreshold {
          suppressed = true
          suppressedBy = idx
          break
        }
      }
      if suppressed {
        log.info(
          "  reject score=\(String(format: "%.3f", det.bodyConfidence), privacy: .public) center=(\(String(format: "%.0f", det.bbox.midX), privacy: .public),\(String(format: "%.0f", det.bbox.midY), privacy: .public)) iouWithKept[\(suppressedBy, privacy: .public)]=\(String(format: "%.3f", maxIoU), privacy: .public)"
        )
      } else {
        log.info(
          "  keep   score=\(String(format: "%.3f", det.bodyConfidence), privacy: .public) center=(\(String(format: "%.0f", det.bbox.midX), privacy: .public),\(String(format: "%.0f", det.bbox.midY), privacy: .public)) maxIoUWithKept=\(String(format: "%.3f", maxIoU), privacy: .public)"
        )
        kept.append(det)
      }
    }
    log.info("output=\(kept.count, privacy: .public)")
    return kept
  }

  static func iou(_ a: CGRect, _ b: CGRect) -> Double {
    let inter = a.intersection(b)
    if inter.isNull || inter.isEmpty { return 0 }
    let interArea = Double(inter.width * inter.height)
    let union = Double(a.width * a.height + b.width * b.height) - interArea
    if union <= 0 { return 0 }
    return interArea / union
  }
}
