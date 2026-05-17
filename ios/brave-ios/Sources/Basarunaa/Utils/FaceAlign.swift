// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation
import UIKit

/// Face alignment for the InsightFace genderage classifier.
///
/// Port fidèle de `private/extensions/basarunaa/src/utils/face_align.js`
/// du POC macOS. La rotation pour aligner les yeux horizontalement est
/// **critique** pour la classification — sans elle, le simple crop carré
/// confond systématiquement la mère et le fils sur la photo TF1
/// famille-repas (iOS softmax inversés vs macOS, 2026-05-16).
enum FaceAlign {

  /// Render a 96×96 BGRA face crop aligned à la POC. When two eye keypoints
  /// are confident, rotate the source so the eyes are horizontal, then crop
  /// a square centered on the face bbox at `side = max(w,h) × 1.1`. When
  /// keypoints are unusable, fall back to a 1.3× axis-aligned crop centered
  /// on the bbox (matches `_cropFromBbox` POC).
  ///
  /// Returns a `CGImage` of `outputSize × outputSize` (default 96×96).
  static func alignedFaceCrop(
    image: CGImage,
    faceBbox: CGRect,
    keypoints: [(point: CGPoint, confidence: Double)],
    outputSize: Int = 96
  ) -> CGImage? {
    // POC kp index → COCO mapping: 1 = left_eye, 2 = right_eye.
    let leftEye: (point: CGPoint, confidence: Double)? =
      keypoints.indices.contains(1) ? keypoints[1] : nil
    let rightEye: (point: CGPoint, confidence: Double)? =
      keypoints.indices.contains(2) ? keypoints[2] : nil

    let useRotation: Bool = {
      guard let le = leftEye, let re = rightEye else { return false }
      guard le.confidence > 0.3, re.confidence > 0.3 else { return false }
      let dx = re.point.x - le.point.x
      let dy = re.point.y - le.point.y
      let eyeDist = (dx * dx + dy * dy).squareRoot()
      if eyeDist < 5 { return false }
      let faceW = max(faceBbox.width, faceBbox.height)
      if faceW < 35 { return false }
      return true
    }()

    let outSize = CGFloat(outputSize)

    if useRotation, let le = leftEye, let re = rightEye {
      // Order eyes by image x so the angle is the actual head tilt
      // (range ~[-90°, +90°]) regardless of whether YOLO11n-pose returns
      // COCO anatomical-left/right (sujet) or image-left/right. Without
      // this, a face-camera person triggers `atan2(0, -dx) ≈ 180°` and the
      // crop renders upside-down → softmax biases everyone to female.
      let (leftPt, rightPt) = le.point.x <= re.point.x
        ? (le.point, re.point)
        : (re.point, le.point)
      let angle = atan2(rightPt.y - leftPt.y, rightPt.x - leftPt.x)
      let cx = faceBbox.midX
      let cy = faceBbox.midY
      let faceSize = max(faceBbox.width, faceBbox.height) * 1.1
      let scale = outSize / faceSize
      return renderAffine(
        image: image,
        outSize: outputSize,
        angle: angle,
        scale: scale,
        cx: cx,
        cy: cy
      )
    }

    // Fallback : crop carré axis-aligned (POC `_cropFromBbox`, padding 15%).
    let imageSize = CGSize(width: image.width, height: image.height)
    let cropRect = squareCropRect(around: faceBbox, imageSize: imageSize)
    guard cropRect.width > 4, cropRect.height > 4 else { return nil }
    guard let cropped = image.cropping(to: cropRect) else { return nil }
    // Resize the cropped patch into the same kind of BGRA buffer the
    // rotation path produces so downstream code (CVPixelBuffer creation)
    // is uniform.
    return renderResize(image: cropped, outSize: outputSize)
  }

  /// Pure-bbox square crop (no rotation, no keypoint usage). Kept as a
  /// helper for the fallback path and for diagnostic callers.
  static func squareCropRect(
    around faceBbox: CGRect,
    imageSize: CGSize
  ) -> CGRect {
    let center = CGPoint(x: faceBbox.midX, y: faceBbox.midY)
    let side = max(faceBbox.width, faceBbox.height) * 1.3
    var rect = CGRect(
      x: center.x - side / 2,
      y: center.y - side / 2,
      width: side,
      height: side
    )
    rect = rect.intersection(CGRect(origin: .zero, size: imageSize))
    return rect
  }

  // MARK: - Internals

  /// Apply transforms mirroring the POC web
  /// (`translate(out/2) → rotate(-angle) → scale → translate(-cx, -cy)`),
  /// draw the source image, return the resulting CGImage.
  ///
  /// Use `UIGraphicsImageRenderer` + `UIImage.draw(at:)` so we get a
  /// UIKit-style top-left coord system and orientation-correct drawing
  /// automatically — every previous attempt mixing raw `CGContext` flips
  /// + transforms ended up with the face misplaced or upside-down in the
  /// 96×96 buffer (debug strip showed torso instead of face,
  /// 2026-05-16). The UIKit renderer matches Canvas2D semantics directly,
  /// so the transforms compose like the POC JS.
  private static func renderAffine(
    image: CGImage,
    outSize: Int,
    angle: CGFloat,
    scale: CGFloat,
    cx: CGFloat,
    cy: CGFloat
  ) -> CGImage? {
    let size = CGSize(width: outSize, height: outSize)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1   // 1 pixel per point — we want exact 96×96 pixels
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let uiImage = UIImage(cgImage: image)
    let rendered = renderer.image { ctx in
      let cgCtx = ctx.cgContext
      let half = CGFloat(outSize) / 2.0
      cgCtx.translateBy(x: half, y: half)
      cgCtx.rotate(by: -angle)
      cgCtx.scaleBy(x: scale, y: scale)
      cgCtx.translateBy(x: -cx, y: -cy)
      // UIImage.draw uses the UIKit coord system (top-left) and respects
      // the current CGContext transforms — no Y-flip arithmetic needed.
      uiImage.draw(at: .zero)
    }
    return rendered.cgImage
  }

  /// Plain resize of an already-cropped patch into a fresh BGRA buffer
  /// (fallback path when rotation conditions aren't met). Uses the same
  /// UIGraphicsImageRenderer plumbing for orientation consistency.
  private static func renderResize(image: CGImage, outSize: Int) -> CGImage? {
    let size = CGSize(width: outSize, height: outSize)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let uiImage = UIImage(cgImage: image)
    let rendered = renderer.image { _ in
      uiImage.draw(in: CGRect(origin: .zero, size: size))
    }
    return rendered.cgImage
  }
}
