// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation

/// Helpers for cropping face patches for the genderage classifier.
///
/// PoC simplification: we use an axis-aligned square crop centered on the face
/// bbox (or on the eyes/nose centroid if keypoints are reliable). The full
/// affine-alignment used in the macOS WebGPU pipeline can come later; for the
/// PoC, a square crop is sufficient to validate that CoreML + the InsightFace
/// model produce sensible gender labels on device.
enum FaceAlign {
  /// Build a square crop rect that fully contains the face bbox and is clamped
  /// to the image bounds.
  static func squareCropRect(
    around faceBbox: CGRect,
    keypoints: [(point: CGPoint, confidence: Double)],
    imageSize: CGSize
  ) -> CGRect {
    // Center the square on the face bbox center, or on the average of the
    // 5 face keypoints when they're confident enough.
    var center = CGPoint(x: faceBbox.midX, y: faceBbox.midY)
    if keypoints.count >= 5 {
      let head = Array(keypoints.prefix(5))
      let strong = head.filter { $0.confidence > 0.4 }
      if strong.count >= 3 {
        let avgX = strong.map { $0.point.x }.reduce(0, +) / CGFloat(strong.count)
        let avgY = strong.map { $0.point.y }.reduce(0, +) / CGFloat(strong.count)
        center = CGPoint(x: avgX, y: avgY)
      }
    }

    // Square side ~ 1.4× max(faceBbox.w, faceBbox.h) — enough to include
    // forehead + chin if the bbox tightly hugs the eyes/nose.
    let side = max(faceBbox.width, faceBbox.height) * 1.4
    var rect = CGRect(
      x: center.x - side / 2,
      y: center.y - side / 2,
      width: side,
      height: side
    )
    // Clamp to image bounds.
    rect = rect.intersection(CGRect(origin: .zero, size: imageSize))
    return rect
  }
}
