// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import Foundation

// Décodage PUR du modèle single-shot gender-v2n `[1, C, N]` → persons.
// AUCUNE dépendance CoreML/UIKit → compilable et testable en standalone
// (`swiftc`) contre le golden `tests/golden/gender-v2n/` sans device.
//
// Spec de référence (contrat cross-langage) :
//   private/extensions/basarunaa/tests/golden/gender-v2n/DECODE_SPEC.md
// Port ligne-à-ligne de `src/detectors/yolo_gender_pose.js` (+ yolo_pose.js,
// nms.js). Toute divergence = dette silencieuse → validée par le golden.
//
// C = 4 (xywh) + numClasses (3 scores) + 3*numKeypoints (17×xyc) = 58.
// Layout d'accès abstrait via la closure `value(channel, det)` : le golden
// passe un tenseur dense `raw[c*N+i]`, la prod passe un accès stride CoreML
// (gère float16 + layout CHW/HWC) — le décodage lui est identique.

public enum GenderV2nClass: Int, Sendable {
  case male = 0
  case female = 1
  case child = 2
}

public struct GenderV2nKeypoint: Sendable {
  public let x: Double
  public let y: Double
  public let confidence: Double
}

/// Détection brute (pur extracteur — AUCUNE décision de flou ici : la policy
/// vit dans `core/policy.ts`, appliquée côté webkit TS).
public struct GenderV2nPersonRaw: Sendable {
  /// `[x1, y1, x2, y2]` en pixels image source (peut sortir du cadre : pas de
  /// clamp d'intersection, parité `yolo_gender_pose.js`).
  public let bbox: [Double]
  /// Score de la classe gagnante (= genderConfidence).
  public let confidence: Double
  public let genderClass: GenderV2nClass
  /// 17 keypoints COCO en pixels image source.
  public let keypoints: [GenderV2nKeypoint]
}

public enum GenderV2nDecode {
  public static let defaultConfThreshold = 0.25
  public static let defaultIoUThreshold = 0.5

  /// Décode `[1, numChannels, numDetections]` → persons (post-NMS).
  /// `value(c, i)` = valeur du canal `c` pour la détection `i`.
  public static func decode(
    numChannels: Int,
    numDetections: Int,
    numClasses: Int = 3,
    numKeypoints: Int = 17,
    scale: Double,
    padX: Double,
    padY: Double,
    srcWidth: Double,
    srcHeight: Double,
    confThreshold: Double = defaultConfThreshold,
    iouThreshold: Double = defaultIoUThreshold,
    value: (_ channel: Int, _ det: Int) -> Double
  ) -> [GenderV2nPersonRaw] {
    let kptOffset = 4 + numClasses  // 7
    var boxes: [GenderV2nPersonRaw] = []

    for i in 0..<numDetections {
      // Score = argmax des scores de classe. `>` strict → 1er max gagne (parité JS).
      var score = 0.0
      var cls = 0
      for k in 0..<numClasses {
        let s = value(4 + k, i)
        if s > score {
          score = s
          cls = k
        }
      }
      if score < confThreshold { continue }

      let cx = value(0, i)
      let cy = value(1, i)
      let w = value(2, i)
      let h = value(3, i)

      let x1 = max(0, (cx - w / 2 - padX) / scale)
      let y1 = max(0, (cy - h / 2 - padY) / scale)
      let x2 = min(srcWidth, (cx + w / 2 - padX) / scale)
      let y2 = min(srcHeight, (cy + h / 2 - padY) / scale)

      var keypoints: [GenderV2nKeypoint] = []
      keypoints.reserveCapacity(numKeypoints)
      for k in 0..<numKeypoints {
        let base = kptOffset + k * 3
        let kx = (value(base, i) - padX) / scale
        let ky = (value(base + 1, i) - padY) / scale
        let kc = value(base + 2, i)
        keypoints.append(GenderV2nKeypoint(x: kx, y: ky, confidence: kc))
      }

      boxes.append(
        GenderV2nPersonRaw(
          bbox: [x1, y1, x2, y2],
          confidence: score,
          genderClass: GenderV2nClass(rawValue: cls) ?? .male,
          keypoints: keypoints
        )
      )
    }

    return nms(boxes, iouThreshold: iouThreshold)
  }

  /// NMS class-agnostic gloutonne (parité `nms.js`) : tri par confidence
  /// décroissante, on garde la meilleure et retire les restantes avec IoU > seuil.
  static func nms(
    _ boxes: [GenderV2nPersonRaw],
    iouThreshold: Double
  ) -> [GenderV2nPersonRaw] {
    if boxes.isEmpty { return [] }
    // Tri stable par confidence décroissante (Swift `sorted` est stable).
    let sorted = boxes.sorted { $0.confidence > $1.confidence }
    var kept: [GenderV2nPersonRaw] = []
    kept.reserveCapacity(sorted.count)
    for det in sorted {
      var suppressed = false
      for keptDet in kept where iou(det.bbox, keptDet.bbox) > iouThreshold {
        suppressed = true
        break
      }
      if !suppressed { kept.append(det) }
    }
    return kept
  }

  /// IoU sur `[x1,y1,x2,y2]` (parité `nms.js:iou`).
  static func iou(_ a: [Double], _ b: [Double]) -> Double {
    let x1 = Swift.max(a[0], b[0])
    let y1 = Swift.max(a[1], b[1])
    let x2 = Swift.min(a[2], b[2])
    let y2 = Swift.min(a[3], b[3])
    let inter = Swift.max(0, x2 - x1) * Swift.max(0, y2 - y1)
    if inter == 0 { return 0 }
    let areaA = (a[2] - a[0]) * (a[3] - a[1])
    let areaB = (b[2] - b[0]) * (b[3] - b[1])
    return inter / (areaA + areaB - inter)
  }
}
