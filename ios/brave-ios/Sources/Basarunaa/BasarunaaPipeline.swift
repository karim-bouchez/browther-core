// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CoreML
import Foundation
import OSLog
import Preferences

/// Genre 3 classes du modèle single-shot gender-v2n (aligné `core/gender.ts`
/// `GenderClass` : male=0, female=1, child=2). rawValue = chaîne envoyée au JS.
public enum Gender: String, Sendable {
  case male
  case female
  case child
}

/// Person produite par le pipeline single-shot gender-v2n. PUR EXTRACTEUR :
/// aucune décision de flou ici (pas de seuil/downgrade). La policy vit dans
/// `core/policy.ts`, appliquée côté bundle webkit TS à partir de `gender` +
/// `genderConfidence`.
public struct DetectedPerson: @unchecked Sendable {
  /// Body bbox en coords image originale.
  public let bbox: CGRect
  /// 17 keypoints COCO.
  public let keypoints: [(point: CGPoint, confidence: Double)]
  /// Genre = classe argmax du modèle (brut, non seuillé).
  public let gender: Gender
  /// Confiance = score de la classe gagnante (sert de genderConfidence ET de
  /// score de détection — un seul score en single-shot).
  public let genderConfidence: Double
}

public struct BasarunaaResult: Sendable {
  public let persons: [DetectedPerson]
  public let totalLatencyMs: Double
  public let poseLatencyMs: Double
  public let classifyLatencyMs: Double
  public let imageSize: CGSize
  /// True si le classifieur NSFW plein-cadre (Marqo) a flaggé l'image.
  public let isNsfw: Bool
  /// Softmax NSFW Marqo (0..1), ou nil si non exécuté.
  public let nsfwScore: Double?

  /// Verdicts bruts des deux modèles, pour la collecte de corpus (strates
  /// `fp-suspect` / `leak-suspect`, cf. `CollectPolicy.classify`). Renseigné
  /// même quand le vérificateur n'a pas tourné — `pf` vaut alors `nil`, ce qui
  /// se lit « pas d'information » et non « zéro personne ».
  public let det: CollectDetection
  /// Latence du passage NanoDet (0 s'il n'a pas tourné).
  public let verifierLatencyMs: Double
  /// L'image s'est arrêtée au pré-filtre : gender-v2n n'a pas été lancé.
  public let skippedByPrefilter: Bool
}

public enum BasarunaaError: Error {
  case modelLoadFailed(String)
  case inferenceFailed(String)
  case invalidImage
}

/// Pipeline Basarunaa iOS — **single-shot gender-v2n** (migration 2026-07-13,
/// cf. `private/docs/BASARUNAA_MOBILE_GENDER_V2N.md`). Une inférence CoreML
/// donne persons + genre 3 classes + keypoints. La cascade historique (YOLO
/// pose + YOLOv8n-face + genderage InsightFace + PPLCNet + matching + synth
/// bodies) est retirée, ainsi que le sentinel NanoDet (2026-08-03 — le
/// pipeline vidéo est one-tier : gender-v2n à 250 ms est son propre tracker).
/// NSFW (Marqo + NudeNet) reste, gaté par la pref `nsfw_enabled` côté handler.
public actor BasarunaaPipeline {
  public static let shared = BasarunaaPipeline()

  private let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa")

  private var detector: GenderV2nPoseDetector?
  private var nsfwClassifier: NSFWClassifier?
  private var nudeNetDetector: NudeNetDetector?

  /// Pré-filtre + vérificateur NanoDet (images uniquement, cf. `analyze`).
  private var verifier: NanoDetVerifier?
  /// Le vérificateur s'auto-désactive après quelques échecs consécutifs, avec
  /// UN seul message. Sans ce garde-fou, un modèle qui charge mais échoue à
  /// chaque inférence produit une ligne de log par image — c'est ce qui est
  /// arrivé sur desktop le 2026-08-18 (ORT jetant « memory access out of
  /// bounds » avec 5 sessions WebGPU concurrentes).
  private var verifierFails = 0
  private static let verifierMaxFails = 3

  private init() {}

  public func warmup() async {
    do {
      let devices = MLModel.availableComputeDevices
      let labels = devices.map { d -> String in
        switch d {
        case .cpu: return "cpu"
        case .gpu: return "gpu"
        case .neuralEngine: return "ane"
        @unknown default: return "unknown"
        }
      }
      log.info("CoreML compute devices: [\(labels.joined(separator: ", "), privacy: .public)]")
      // On ne précharge QUE le détecteur (chemin chaud `analyze` — ~5s de compile
      // CoreML au 1er appel = le cold-start observé). NSFW (opt-in, OFF par défaut)
      // reste lazy : chargé à sa 1re demande réelle par checkNsfw(), pour ne pas
      // payer ni la mémoire ni le temps si inutile.
      _ = try loadDetectorIfNeeded()
      // Le vérificateur est désormais sur le chemin chaud des images : le
      // charger ici évite de payer sa compilation CoreML à la première image
      // analysée, c'est-à-dire pile au moment où l'utilisateur attend.
      _ = loadVerifierIfNeeded()
      log.info("warmup done (detector + verifier)")
    } catch {
      log.error("warmup failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// Phase 2 — NSFW (Marqo + NudeNet). À lancer en parallèle d'`analyze`.
  public func checkNsfw(image: CGImage) async throws -> (
    isNsfw: Bool, score: Double?, latencyMs: Double, nudeClasses: [String]
  ) {
    let (nsfwClassifier, nudeNetDetector) = try loadNsfwIfNeeded()
    let nsfwStart = Date()
    let marqoResult = try? nsfwClassifier.classify(
      image: image, threshold: Preferences.Basarunaa.nsfwConf.value)
    let nudeDetections =
      (try? nudeNetDetector.detect(
        image: image, threshold: Preferences.Basarunaa.nudenetConf.value)) ?? []
    let exposedHit = nudeDetections.contains { d in
      guard let cls = NudeNetClass(rawValue: d.classIdx) else { return false }
      return NudeNetClass.alwaysFlagged.contains(cls)
    }
    let marqoIsNsfw = marqoResult?.isNsfw ?? false
    let nsfwScore = marqoResult?.score
    let latencyMs = Date().timeIntervalSince(nsfwStart) * 1000
    let isNsfw = marqoIsNsfw || exposedHit
    let nudeClasses = nudeDetections.compactMap { d -> String? in
      guard let cls = NudeNetClass(rawValue: d.classIdx) else { return nil }
      return String(describing: cls)
    }
    if isNsfw {
      let trigger =
        marqoIsNsfw
        ? "marqo=\(String(format: "%.2f", nsfwScore ?? 0))"
        : "nudenet_exposed"
      log.info(
        "checkNsfw POSITIVE: \(trigger, privacy: .public) (\(String(format: "%.1f", latencyMs), privacy: .public)ms)"
      )
    } else {
      log.info("checkNsfw negative (\(String(format: "%.1f", latencyMs), privacy: .public)ms)")
    }
    return (isNsfw: isNsfw, score: nsfwScore, latencyMs: latencyMs, nudeClasses: nudeClasses)
  }

  /// Phase 1 — détection single-shot gender-v2n. Renvoie ASAP toutes les
  /// persons BRUTES (genre 3 classes + conf + keypoints), SANS décision de flou.
  ///
  /// - Parameter useVerifier: active le passage NanoDet (pré-filtre +
  ///   vérificateur). **`true` pour les images, `false` pour la vidéo** — et ce
  ///   n'est pas une timidité : desktop fait exactement ce partage (le
  ///   pré-filtre vit dans l'offscreen, qui ne voit que les images ; la vidéo
  ///   desktop passe par le pipeline natif sans NanoDet). Sur mobile la vidéo
  ///   tourne à 250 ms en one-tier, où gender-v2n est son propre tracker :
  ///   y ajouter une inférence par frame changerait la cadence qu'on est
  ///   justement en train de calibrer au bench.
  public func analyze(image: CGImage, useVerifier: Bool = false) async throws -> BasarunaaResult {
    let bodyThreshold = Preferences.Basarunaa.confBody.value
    let imageSize = CGSize(width: image.width, height: image.height)
    let start = Date()

    // ---- Passage NanoDet : pré-filtre PUIS vérificateur, une seule inférence.
    var verifierBoxes: [VerifierBox]?
    var verifierMs: Double = 0
    if useVerifier, let nd = loadVerifierIfNeeded() {
      let t0 = Date()
      do {
        verifierBoxes = try nd.detect(image: image)
        verifierFails = 0  // une réussite efface l'ardoise
      } catch {
        // Une panne du vérificateur ne doit JAMAIS faire fuiter : on retombe
        // sur gender-v2n seul plutôt que de ne rien analyser. Les faux positifs
        // reviennent, personne n'est révélé par erreur.
        verifierBoxes = nil
        verifierFails += 1
        if verifierFails >= Self.verifierMaxFails {
          verifier = nil
          log.warning(
            "vérificateur désactivé après \(Self.verifierMaxFails, privacy: .public) échecs — gender-v2n seul, les faux positifs reviennent"
          )
        }
      }
      verifierMs = Date().timeIntervalSince(t0) * 1000

      if let boxes = verifierBoxes, boxes.isEmpty {
        // Aucun humain dans l'image → gender-v2n n'est pas lancé du tout.
        // C'est 61 % des images en usage réel : le pré-filtre est un gain de
        // latence, pas un coût.
        log.info(
          "prefilter_skip (\(String(format: "%.1f", verifierMs), privacy: .public)ms) — gender-v2n non lancé"
        )
        return BasarunaaResult(
          persons: [], totalLatencyMs: verifierMs, poseLatencyMs: 0,
          classifyLatencyMs: 0, imageSize: imageSize, isNsfw: false, nsfwScore: nil,
          det: CollectDetection(pf: 0, raw: 0, ok: 0, confs: []),
          verifierLatencyMs: verifierMs, skippedByPrefilter: true)
      }
    }

    let detector = try loadDetectorIfNeeded()
    let raws = try detector.detect(image: image, scoreThreshold: bodyThreshold)
    let allPersons = raws.map { r -> DetectedPerson in
      DetectedPerson(
        bbox: CGRect(
          x: r.bbox[0], y: r.bbox[1],
          width: r.bbox[2] - r.bbox[0], height: r.bbox[3] - r.bbox[1]),
        keypoints: r.keypoints.map { (point: CGPoint(x: $0.x, y: $0.y), confidence: $0.confidence) },
        gender: Self.gender(from: r.genderClass),
        genderConfidence: r.confidence
      )
    }

    // ---- Vérification par boîte -------------------------------------------
    // Une détection gender-v2n n'est retenue que si elle tombe DANS un humain
    // vu par NanoDet. C'est ce qui écarte les chiens, peluches et beignets sur
    // lesquels un modèle à 3 classes toutes humaines n'a aucun moyen de dire
    // « ceci n'est pas quelqu'un ».
    var persons = allPersons
    if let boxes = verifierBoxes {
      persons = allPersons.filter { p in
        boxes.contains { coveredBy(p.bbox, $0.bbox) >= NanoDetVerifier.minCoverage }
      }
    }

    let totalLatencyMs = Date().timeIntervalSince(start) * 1000
    let rejected = allPersons.count - persons.count
    log.info(
      """
      analyze done: persons=\(persons.count, privacy: .public) \
      brutes=\(allPersons.count, privacy: .public) rejets_verif=\(rejected, privacy: .public) \
      nanodet=\(verifierBoxes?.count ?? -1, privacy: .public) \
      total=\(String(format: "%.1f", totalLatencyMs), privacy: .public)ms \
      (dont vérif \(String(format: "%.1f", verifierMs), privacy: .public)ms)
      """
    )
    // Désaccord MONTANT : le généraliste voit un humain, gender-v2n aucun. Le
    // pré-filtre a donc lancé gender-v2n pour rien ET l'image restera nette —
    // c'est le mode de défaillance le plus coûteux en usage (l'utilisateur voit
    // une personne non floutée, il ne signale pas, il désactive).
    if let boxes = verifierBoxes, !boxes.isEmpty, persons.isEmpty {
      log.info("missed_by_gender nanodet=\(boxes.count, privacy: .public)")
    }
    for (i, p) in persons.enumerated() {
      log.info(
        "[\(i, privacy: .public)] bbox=\(p.bbox.debugDescription, privacy: .public) → \(p.gender.rawValue, privacy: .public)@\(String(format: "%.2f", p.genderConfidence), privacy: .public)"
      )
    }

    return BasarunaaResult(
      persons: persons,
      totalLatencyMs: totalLatencyMs,
      poseLatencyMs: totalLatencyMs,
      classifyLatencyMs: 0,
      imageSize: imageSize,
      isNsfw: false,
      nsfwScore: nil,
      det: CollectDetection(
        pf: verifierBoxes?.count,
        raw: allPersons.count,
        ok: persons.count,
        confs: persons.map(\.genderConfidence)),
      verifierLatencyMs: verifierMs,
      skippedByPrefilter: false
    )
  }

  private static func gender(from cls: GenderV2nClass) -> Gender {
    switch cls {
    case .male: return .male
    case .female: return .female
    case .child: return .child
    }
  }

  // MARK: - Loading

  /// Chargement paresseux du vérificateur. `nil` = il a été désactivé (échecs
  /// répétés) ou n'a pas pu charger — l'appelant retombe alors sur gender-v2n
  /// seul, qui est le comportement d'avant le 2026-08-28. Jamais une exception :
  /// un vérificateur absent dégrade la qualité, il ne doit pas casser l'analyse.
  private func loadVerifierIfNeeded() -> NanoDetVerifier? {
    if let verifier { return verifier }
    guard verifierFails < Self.verifierMaxFails else { return nil }
    do {
      let nd = try NanoDetVerifier()
      verifier = nd
      return nd
    } catch {
      verifierFails = Self.verifierMaxFails
      log.error(
        "vérificateur NanoDet indisponible : \(String(describing: error), privacy: .public) — gender-v2n seul"
      )
      return nil
    }
  }

  private func loadDetectorIfNeeded() throws -> GenderV2nPoseDetector {
    if let detector { return detector }
    let newDetector = try GenderV2nPoseDetector()
    self.detector = newDetector
    return newDetector
  }

  private func loadNsfwIfNeeded() throws -> (NSFWClassifier, NudeNetDetector) {
    if let nsfwClassifier, let nudeNetDetector {
      return (nsfwClassifier, nudeNetDetector)
    }
    let newNsfw = try NSFWClassifier()
    let newNudeNet = try NudeNetDetector()
    self.nsfwClassifier = newNsfw
    self.nudeNetDetector = newNudeNet
    return (newNsfw, newNudeNet)
  }
}
