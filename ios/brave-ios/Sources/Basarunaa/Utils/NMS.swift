// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation

/// Standard greedy non-maximum suppression on person detections.
enum NMS {
  static func apply(
    detections: [RawPersonDetection],
    iouThreshold: Double
  ) -> [RawPersonDetection] {
    let sorted = detections.sorted { $0.bodyConfidence > $1.bodyConfidence }
    var kept: [RawPersonDetection] = []
    kept.reserveCapacity(sorted.count)
    for det in sorted {
      var suppressed = false
      for keptDet in kept {
        if iou(det.bbox, keptDet.bbox) > iouThreshold {
          suppressed = true
          break
        }
      }
      if !suppressed { kept.append(det) }
    }
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
