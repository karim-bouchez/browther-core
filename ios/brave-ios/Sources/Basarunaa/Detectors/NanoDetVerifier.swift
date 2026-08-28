// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CoreML
import Foundation
import OSLog

/// Boîte `person` produite par NanoDet, en coordonnées de l'image d'origine.
public struct VerifierBox: Sendable {
  public let bbox: CGRect
  public let confidence: Double
}

/// NanoDet-Plus-m 320 — **pré-filtre ET vérificateur** de gender-v2n.
///
/// ── Deux rôles, une seule inférence (parité desktop 2026-08-18) ────────────
/// 1. **Pré-filtre** : aucune personne vue → gender-v2n n'est pas lancé du
///    tout. Sur desktop, 61 % des images s'arrêtent là — c'est donc un GAIN de
///    latence, pas un coût.
/// 2. **Vérificateur** : sinon, ses boîtes `person` servent à jeter les
///    détections gender-v2n qui ne recouvrent aucun humain.
///
/// Ce qui rend NanoDet utile ici n'est pas sa taille mais ses **80 classes
/// CONCURRENTES** : gender-v2n n'a que 3 classes, toutes humaines, donc il ne
/// peut structurellement pas répondre « ceci est un chien ». NanoDet le peut.
/// Mesuré côté desktop : faux positifs sur images sans personne **14,5 % →
/// 2,1 %**, pour 0,24× le coût de gender-v2n (cf. `FINDINGS.md` § Choix du
/// vérificateur).
///
/// ── Histoire de ce fichier, pour ne pas le confondre ───────────────────────
/// Il a existé sous le nom `NanoDetSentinelDetector.swift` jusqu'au 2026-08-04,
/// dans un rôle **complètement différent** : veilleur du pipeline VIDÉO
/// two-tier, qui suivait les personnes entre deux inférences coûteuses. Ce
/// rôle-là est mort et ne doit pas revenir — gender-v2n à 250 ms est son propre
/// tracker. Ressuscité le 2026-08-28 pour le rôle ci-dessus, sur les IMAGES
/// seulement, avec une règle en plus que le sentinel n'avait pas
/// (`argmaxClasses`).
///
/// Modèle : NanoDet-Plus-m 320×320, COCO 80 classes, anchor-free, 4 strides
/// `[8, 16, 32, 64]`. Sortie `[1, 2125, 112]` = 80 scores de classe (déjà
/// post-sigmoid dans cet export) + 32 canaux de régression de boîte
/// (4 × reg_max+1), décodés par distribution focal loss.
///
/// Porté ligne à ligne depuis `private/extensions/basarunaa/src/detectors/nanodet.js`.
/// Ne pas « simplifier » — cf. `private/extensions/basarunaa/CLAUDE.md` § règle d'or.
final class NanoDetVerifier: @unchecked Sendable {
  static let inputSize: CGFloat = 320
  static let numClasses = 80
  static let personClassIndex = 0
  static let regMax = 7
  static let strides: [Int] = [8, 16, 32, 64]
  /// 0,20 — **relevé de 0,15 le 2026-08-18 après mesure en usage réel**. À 0,15
  /// le pré-filtre déclenchait gender-v2n sur ~47 % des images, ce qui annulait
  /// son intérêt en latence. 0,20 DOMINE 0,15 : moins de déclenchements
  /// (38,7 %) ET moins de faux positifs résiduels (2,1 % contre 2,7 %), pour
  /// 0,2 point de rappel et 0,28 point de fuite pré-filtre — à comparer aux
  /// 10,6 % d'images où gender-v2n seul ne voit déjà rien.
  static let confThreshold: Double = 0.20
  static let iouThreshold: Double = 0.5
  static let minBoxSize: CGFloat = 8
  /// Recouvrement minimal pour qu'une détection gender-v2n soit CONFIRMÉE par
  /// une boîte NanoDet. 0,1 et pas 0,5 : les deux modèles ne cadrent pas les
  /// corps de la même façon, et exiger un recouvrement fort ferait rejeter des
  /// personnes réelles — le vérificateur doit écarter « il n'y a aucun humain
  /// là », pas arbitrer un cadrage.
  static let minCoverage: Double = 0.1

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
    guard
      let firstOutput = self.model.modelDescription.outputDescriptionsByName.keys.sorted().first
    else {
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
    log.info("NanoDet chargé, sortie=\(firstOutput, privacy: .public) cellules=\(built.count, privacy: .public)")
  }

  /// Boîtes `person` de l'image, dans son repère d'origine.
  func detect(image: CGImage) throws -> [VerifierBox] {
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

    let raw = postprocess(
      tensor: multiArray, letterbox: letterboxed, originalSize: originalSize)
    return nms(boxes: raw, iouThreshold: Self.iouThreshold)
  }

  /// Décode `[1, 2125, 112]` (ou transposé `[1, 112, 2125]`) en boîtes `person`.
  private func postprocess(
    tensor: MLMultiArray,
    letterbox: Letterbox.Result,
    originalSize: CGSize
  ) -> [VerifierBox] {
    let shape = tensor.shape.map { $0.intValue }
    let strides = tensor.strides.map { $0.intValue }

    guard shape.count == 3, shape[0] == 1 else {
      log.error("forme de sortie NanoDet inattendue : \(shape, privacy: .public)")
      return []
    }
    let featLen = Self.numClasses + 4 * (Self.regMax + 1)  // 80 + 32 = 112
    let layoutIsCellMajor = (shape[1] == grids.count)
    let numCells = layoutIsCellMajor ? shape[1] : shape[2]
    let numChannels = layoutIsCellMajor ? shape[2] : shape[1]
    guard numChannels == featLen else {
      log.error("nombre de canaux inattendu : \(numChannels, privacy: .public) (attendu \(featLen, privacy: .public))")
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
    var results: [VerifierBox] = []
    results.reserveCapacity(64)

    let cellCount = min(numCells, grids.count)
    for i in 0..<cellCount {
      let cellBase = i * cellStride
      let score = Double(read(cellBase + Self.personClassIndex * channelStride))
      if score < Self.confThreshold { continue }

      // `argmaxClasses` — ne retenir une cellule que si `person` est la classe
      // GAGNANTE, au lieu de regarder son score isolément. C'est la logique
      // avec laquelle le rôle de vérificateur a été MESURÉ
      // (`training/collect_verifier.mjs`) : sans elle, une cellule où `dog`
      // domine largement mais où `person` passe quand même le seuil produirait
      // une boîte « personne », ce qui rendrait le vérificateur plus permissif
      // que ce que le banc a chiffré. Absente du sentinel vidéo d'origine — ne
      // pas la reperdre en re-synchronisant ce fichier sur l'ancien.
      var dominated = false
      for k in 1..<Self.numClasses where Double(read(cellBase + k * channelStride)) > score {
        dominated = true
        break
      }
      if dominated { continue }

      // Décodage de la boîte par distribution focal loss : chaque côté est
      // l'espérance d'une softmax sur regMax+1 bacs, en unités de stride.
      var distances = [Double](repeating: 0, count: 4)
      for d in 0..<4 {
        let start = cellBase + (regBaseChannel + d * regLen) * channelStride
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
      let clipped = letterbox.unmap(rect: lbRect).intersection(imageRect)
      if clipped.isNull || clipped.isEmpty { continue }
      if clipped.width < Self.minBoxSize || clipped.height < Self.minBoxSize { continue }

      results.append(VerifierBox(bbox: clipped, confidence: score))
    }

    return results
  }

  /// NMS glouton. Miroir de `utils/nms.js`.
  private func nms(boxes: [VerifierBox], iouThreshold: Double) -> [VerifierBox] {
    let sorted = boxes.sorted { $0.confidence > $1.confidence }
    var kept: [VerifierBox] = []
    kept.reserveCapacity(sorted.count)
    for b in sorted {
      var suppressed = false
      for k in kept where iou(b.bbox, k.bbox) > iouThreshold {
        suppressed = true
        break
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

/// Part de `box` recouverte par `ref`. Asymétrique par construction : on veut
/// savoir si la détection gender-v2n tombe DANS un humain, pas l'inverse (une
/// boîte NanoDet de foule recouvre mal une seule personne, et ce n'est pas une
/// raison de la rejeter). Port de `coveredBy` (`offscreen.js:620`).
func coveredBy(_ box: CGRect, _ ref: CGRect) -> Double {
  let inter = box.intersection(ref)
  if inter.isNull || inter.isEmpty { return 0 }
  let area = box.width * box.height
  guard area > 0 else { return 0 }
  return Double((inter.width * inter.height) / area)
}
