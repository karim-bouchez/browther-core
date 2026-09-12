// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import SwiftUI

/// Les médias de l'introduction et leur **floutage pré-calculé**.
///
/// Pourquoi pré-calculé : faire tourner le modèle pendant l'écran coûterait un
/// chargement CoreML, un délai variable et un rendu qui dépend du téléphone,
/// pour une scène connue d'avance. Le vrai pipeline a donc tourné une fois, sur
/// Mac (`private/extensions/basarunaa/scripts/render_intro_media.mjs`), et on
/// embarque son résultat : par personne, le contour du voile et son genre.
/// L'app ne fait plus que poser le voile — le choix « les femmes / les hommes /
/// les deux » reste donc vivant à l'écran.
enum BrowtherIntroMedia {

  /// Une personne détectée, en coordonnées **relatives** (0…1) : le média sera
  /// affiché à des tailles différentes selon l'appareil.
  struct Person: Decodable {
    /// Contour du voile, déjà dilaté comme le fait le compositeur macOS.
    let poly: [[Double]]
    let gender: String
    let confidence: Double

    /// Faut-il flouter cette personne pour ce choix ?
    ///
    /// ⚠️ Même règle que le moteur (`src/core/policy.ts`) : la cible choisie,
    /// **plus tout ce dont le genre n'est pas sûr**. Dans le doute, on floute —
    /// une prévisualisation plus permissive que l'app mentirait sur ce qu'elle
    /// fait.
    func isBlurred(for target: BrowtherBlurTarget, certainty: Double = 0.70) -> Bool {
      switch target {
      case .both: return true
      case .women: if gender == "female" { return true }
      case .men: if gender == "male" { return true }
      }
      return confidence < certainty
    }

    func path(in size: CGSize) -> Path {
      var path = Path()
      for (index, point) in poly.enumerated() where point.count == 2 {
        let cgPoint = CGPoint(x: point[0] * size.width, y: point[1] * size.height)
        if index == 0 {
          path.move(to: cgPoint)
        } else {
          path.addLine(to: cgPoint)
        }
      }
      path.closeSubpath()
      return path
    }
  }

  private struct PhotoFile: Decodable {
    let persons: [Person]
  }

  private struct VideoFile: Decodable {
    struct Frame: Decodable {
      let t: Double
      let persons: [Person]
    }
    let fps: Double
    let frames: [Frame]
  }

  // MARK: - Photo

  static let photoName = "browther-intro-photo"
  static let videoName = "browther-intro-video"

  static let photoPersons: [Person] = {
    guard let url = Bundle.module.url(forResource: photoName, withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let file = try? JSONDecoder().decode(PhotoFile.self, from: data)
    else { return [] }
    return file.persons
  }()

  static var photoImage: UIImage? {
    guard let url = Bundle.module.url(forResource: photoName, withExtension: "jpg") else {
      return nil
    }
    return UIImage(contentsOfFile: url.path)
  }

  // MARK: - Vidéo

  static var videoURL: URL? {
    Bundle.module.url(forResource: videoName, withExtension: "mp4")
  }

  private static let video: VideoFile? = {
    guard let url = Bundle.module.url(forResource: videoName, withExtension: "json"),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return try? JSONDecoder().decode(VideoFile.self, from: data)
  }()

  /// Les personnes à l'instant `time` de la vidéo. On prend l'échantillon le
  /// plus proche : les boîtes sont calculées à 8 images/s alors que la lecture
  /// tourne à 24 — interpoler n'apporterait rien à cette échelle, le voile est
  /// large et flou.
  static func persons(at time: Double) -> [Person] {
    guard let video, !video.frames.isEmpty else { return [] }
    let step = 1.0 / video.fps
    let index = max(0, min(video.frames.count - 1, Int((time / step).rounded())))
    return video.frames[index].persons
  }

  static var videoDuration: Double {
    guard let video, let last = video.frames.last else { return 0 }
    return last.t + 1.0 / video.fps
  }

  // MARK: - Son

  /// Les deux versions du même extrait : l'originale et celle passée dans
  /// Sawtunaa. L'interrupteur de l'écran bascule de l'une à l'autre sans
  /// déplacer la tête de lecture — c'est ce qui rend la comparaison juste.
  static var audioBeforeURL: URL? {
    Bundle.module.url(forResource: "browther-intro-audio-before", withExtension: "m4a")
  }

  static var audioAfterURL: URL? {
    Bundle.module.url(forResource: "browther-intro-audio-after", withExtension: "m4a")
  }
}
