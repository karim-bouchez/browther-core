// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation

/// Body polygon construction + rasterisation, port direct du POC
/// `private/extensions/basarunaa/src/utils/body_polygon.js`. Utilisé par
/// `PPLCNetClassifier` pour gris-outer les pixels hors silhouette avant
/// inférence (parité macOS `preprocessForClassification`).
enum BodyPolygon {

  struct Polygon {
    let points: [CGPoint]
    let isBodyShaped: Bool
  }

  struct Mask {
    let data: [UInt8]   // 0 ou 1, taille width * height
    let width: Int
    let height: Int
  }

  // Constantes POC (1:1).
  private static let kpConfidence: Double = 0.3
  private static let bodyWidthFactor: Double = 0.55
  private static let handExtend: Double = 0.3
  private static let footExtend: Double = 0.08
  private static let edgeSnap: Double = 0.05
  // Indexées par index COCO (0..16).
  private static let regionScale: [Double] = [
    0.8, 0.8, 0.8, 0.8, 0.8,   // head 0-4
    1.0, 1.0,                  // shoulders 5-6
    0.7, 0.7,                  // elbows 7-8
    0.6, 0.6,                  // wrists 9-10
    1.1, 1.1,                  // hips 11-12
    0.8, 0.8,                  // knees 13-14
    0.7, 0.7,                  // ankles 15-16
  ]

  /// Build a body-shaped polygon from 17 COCO keypoints (port direct
  /// `buildBodyPolygon`). Retourne un fallback bbox-rect si pas assez de
  /// keypoints fiables.
  static func buildPolygon(
    keypoints: [(point: CGPoint, confidence: Double)]?,
    bbox: CGRect,
    imageSize: CGSize
  ) -> Polygon {
    guard let kps = keypoints else { return bboxFallback(bbox) }

    let bx1 = Double(bbox.minX)
    let by1 = Double(bbox.minY)
    let bx2 = Double(bbox.maxX)
    let by2 = Double(bbox.maxY)
    let bw = bx2 - bx1
    let bh = by2 - by1

    let confident = kps.enumerated().filter { _, kp in kp.confidence >= kpConfidence }
    if confident.count < 4 { return bboxFallback(bbox) }

    // Half-width depuis les épaules (kp 5/6), fallback bbox * 0.25.
    let leftSh = kps.count > 5 ? kps[5] : nil
    let rightSh = kps.count > 6 ? kps[6] : nil
    var halfWidth: Double
    if let l = leftSh, let r = rightSh, l.confidence >= kpConfidence, r.confidence >= kpConfidence {
      halfWidth = abs(Double(r.point.x) - Double(l.point.x)) * bodyWidthFactor
    } else {
      halfWidth = bw * 0.25
    }
    halfWidth = max(halfWidth, bw * 0.2)

    var widened: [CGPoint] = []
    widened.reserveCapacity(confident.count * 2 + 8)
    for (idx, kp) in confident {
      let scale = idx < regionScale.count ? regionScale[idx] : 0.8
      let w = halfWidth * scale
      let kx = Double(kp.point.x)
      let ky = Double(kp.point.y)
      widened.append(CGPoint(x: kx - w, y: ky))
      widened.append(CGPoint(x: kx + w, y: ky))
    }

    // Head padding (au-dessus du keypoint le plus haut parmi 0-4).
    let headKps = (0..<min(5, kps.count)).filter { kps[$0].confidence >= kpConfidence }
    if !headKps.isEmpty {
      let topY = headKps.map { Double(kps[$0].point.y) }.min() ?? 0
      let sumX = headKps.reduce(0.0) { $0 + Double(kps[$1].point.x) }
      let headCx = sumX / Double(headKps.count)
      let headPadY = max(halfWidth * 0.6, bh * 0.08)
      let headPadX = max(halfWidth * 0.9, bw * 0.25)
      widened.append(CGPoint(x: headCx - headPadX, y: topY - headPadY))
      widened.append(CGPoint(x: headCx + headPadX, y: topY - headPadY))
    }

    // Extension main (coude 7→poignet 9, et 8→10).
    extendHand(kps: kps, elbowIdx: 7, wristIdx: 9, halfWidth: halfWidth, out: &widened)
    extendHand(kps: kps, elbowIdx: 8, wristIdx: 10, halfWidth: halfWidth, out: &widened)

    // Extension pieds (ankles 15/16 vers le bas).
    let footPad = bh * footExtend
    for ankleIdx in [15, 16] {
      guard ankleIdx < kps.count else { continue }
      let ankle = kps[ankleIdx]
      if ankle.confidence >= kpConfidence {
        let w = halfWidth * 0.7  // POC: REGION_SCALE.ankle = 0.7
        let ax = Double(ankle.point.x)
        let ay = Double(ankle.point.y)
        widened.append(CGPoint(x: ax - w, y: ay + footPad))
        widened.append(CGPoint(x: ax + w, y: ay + footPad))
      }
    }

    // Convex hull + scale to bbox bounds + edge snap.
    let hull = convexHull(widened)
    if hull.count < 3 { return bboxFallback(bbox) }

    var polyMinX = Double.infinity, polyMaxX = -Double.infinity
    var polyMinY = Double.infinity, polyMaxY = -Double.infinity
    for p in hull {
      polyMinX = min(polyMinX, Double(p.x))
      polyMaxX = max(polyMaxX, Double(p.x))
      polyMinY = min(polyMinY, Double(p.y))
      polyMaxY = max(polyMaxY, Double(p.y))
    }
    let polyCx = (polyMinX + polyMaxX) / 2
    let polyCy = (polyMinY + polyMaxY) / 2
    let bboxCx = (bx1 + bx2) / 2
    let bboxCy = (by1 + by2) / 2
    let sx = bw / max(polyMaxX - polyMinX, 1e-6)
    let sy = bh / max(polyMaxY - polyMinY, 1e-6)
    let scaled = hull.map { p -> CGPoint in
      CGPoint(
        x: bboxCx + (Double(p.x) - polyCx) * sx,
        y: bboxCy + (Double(p.y) - polyCy) * sy
      )
    }
    let snapped = snapToEdges(
      scaled,
      bbox: bbox,
      imageSize: imageSize,
      kps: kps
    )
    return Polygon(points: snapped, isBodyShaped: true)
  }

  /// Rasterize the polygon into a binary mask via scanline fill (port direct
  /// du POC `polygonToMask`). Mask values: 0 = outside, 1 = inside.
  static func polygonToMask(
    points: [CGPoint],
    imageWidth: Int,
    imageHeight: Int
  ) -> Mask {
    var data = [UInt8](repeating: 0, count: imageWidth * imageHeight)
    if points.count < 3 {
      return Mask(data: data, width: imageWidth, height: imageHeight)
    }

    var minY = Double(imageHeight), maxY = 0.0
    for p in points {
      if Double(p.y) < minY { minY = Double(p.y) }
      if Double(p.y) > maxY { maxY = Double(p.y) }
    }
    let yStart = max(0, Int(floor(minY)))
    let yEnd = min(imageHeight - 1, Int(ceil(maxY)))
    if yStart > yEnd {
      return Mask(data: data, width: imageWidth, height: imageHeight)
    }

    for y in yStart...yEnd {
      var inter: [Double] = []
      let yd = Double(y)
      for i in 0..<points.count {
        let a = points[i]
        let b = points[(i + 1) % points.count]
        let ay = Double(a.y), by = Double(b.y)
        if (ay <= yd && by > yd) || (by <= yd && ay > yd) {
          let denom = by - ay
          if abs(denom) > 1e-9 {
            inter.append(Double(a.x) + (yd - ay) / denom * Double(b.x - a.x))
          }
        }
      }
      inter.sort()
      var k = 0
      while k + 1 < inter.count {
        let x1 = max(0, Int(floor(inter[k])))
        let x2 = min(imageWidth - 1, Int(ceil(inter[k + 1])))
        if x1 <= x2 {
          for x in x1...x2 {
            data[y * imageWidth + x] = 1
          }
        }
        k += 2
      }
    }
    return Mask(data: data, width: imageWidth, height: imageHeight)
  }

  // MARK: - Internals

  private static func extendHand(
    kps: [(point: CGPoint, confidence: Double)],
    elbowIdx: Int,
    wristIdx: Int,
    halfWidth: Double,
    out: inout [CGPoint]
  ) {
    guard elbowIdx < kps.count, wristIdx < kps.count else { return }
    let elbow = kps[elbowIdx], wrist = kps[wristIdx]
    if elbow.confidence < kpConfidence || wrist.confidence < kpConfidence { return }
    let dx = Double(wrist.point.x - elbow.point.x)
    let dy = Double(wrist.point.y - elbow.point.y)
    let hx = Double(wrist.point.x) + dx * handExtend
    let hy = Double(wrist.point.y) + dy * handExtend
    let w = halfWidth * 0.6
    out.append(CGPoint(x: hx - w, y: hy))
    out.append(CGPoint(x: hx + w, y: hy))
  }

  private static func snapToEdges(
    _ points: [CGPoint],
    bbox: CGRect,
    imageSize: CGSize,
    kps: [(point: CGPoint, confidence: Double)]
  ) -> [CGPoint] {
    let imgW = Double(imageSize.width)
    let imgH = Double(imageSize.height)
    let by1 = Double(bbox.minY), by2 = Double(bbox.maxY)
    let bx1 = Double(bbox.minX), bx2 = Double(bbox.maxX)
    let hasAnkles = [15, 16].contains { i in
      i < kps.count && kps[i].confidence >= kpConfidence
    }
    let hasHead = [0, 1, 2].contains { i in
      i < kps.count && kps[i].confidence >= kpConfidence
    }
    let snapBottom = !hasAnkles && by2 / imgH > (1 - edgeSnap)
    let snapTop = !hasHead && by1 / imgH < edgeSnap
    let snapLeft = bx1 / imgW < edgeSnap
    let snapRight = bx2 / imgW > (1 - edgeSnap)
    if !snapBottom && !snapTop && !snapLeft && !snapRight { return points }

    var minX = Double.infinity, maxX = -Double.infinity
    var minY = Double.infinity, maxY = -Double.infinity
    for p in points {
      minX = min(minX, Double(p.x)); maxX = max(maxX, Double(p.x))
      minY = min(minY, Double(p.y)); maxY = max(maxY, Double(p.y))
    }
    let xR = max(maxX - minX, 1)
    let yR = max(maxY - minY, 1)
    let near = 0.15
    return points.map { p -> CGPoint in
      var x = Double(p.x), y = Double(p.y)
      if snapBottom && y > maxY - yR * near { y = imgH }
      if snapTop && y < minY + yR * near { y = 0 }
      if snapLeft && x < minX + xR * near { x = 0 }
      if snapRight && x > maxX - xR * near { x = imgW }
      return CGPoint(x: x, y: y)
    }
  }

  private static func bboxFallback(_ bbox: CGRect) -> Polygon {
    let pts: [CGPoint] = [
      CGPoint(x: bbox.minX, y: bbox.minY),
      CGPoint(x: bbox.maxX, y: bbox.minY),
      CGPoint(x: bbox.maxX, y: bbox.maxY),
      CGPoint(x: bbox.minX, y: bbox.maxY),
    ]
    return Polygon(points: pts, isBodyShaped: false)
  }

  /// Andrew's monotone chain convex hull (port direct du POC `_convexHull`).
  private static func convexHull(_ pts: [CGPoint]) -> [CGPoint] {
    if pts.count < 3 { return pts }
    let sorted = pts.sorted { lhs, rhs in
      lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
    }
    let n = sorted.count

    func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
      Double((a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x))
    }

    var lower: [CGPoint] = []
    for i in 0..<n {
      while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], sorted[i]) <= 0 {
        lower.removeLast()
      }
      lower.append(sorted[i])
    }
    var upper: [CGPoint] = []
    for i in stride(from: n - 1, through: 0, by: -1) {
      while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], sorted[i]) <= 0 {
        upper.removeLast()
      }
      upper.append(sorted[i])
    }
    lower.removeLast()
    upper.removeLast()
    return lower + upper
  }
}
