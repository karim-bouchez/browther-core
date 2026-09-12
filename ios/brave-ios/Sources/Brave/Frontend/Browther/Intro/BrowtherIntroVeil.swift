// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Le voile de Basarunaa, **tel que le compositeur macOS le rend** —
/// `src/core/blur-compositor.ts` :
///
/// 1. un flou gaussien sur **toute** l'image, de rayon `max(25, 4 % du plus
///    grand côté)` ;
/// 2. un masque qui épouse le corps (le polygone pré-calculé), adouci de 10 px ;
/// 3. la composition des deux — l'image nette dessous, la floutée au travers du
///    masque.
///
/// ⚠️ Ne pas retomber sur `.ultraThinMaterial` : le matériau système n'est pas
/// un flou, c'est une **matière claire translucide**. Elle éclaircit tout ce
/// qu'elle couvre et rend un voile laiteux uniforme, très loin du rendu du
/// moteur. C'est l'erreur qu'a corrigée ce fichier (recette du 2026-09-12).
enum BrowtherIntroVeil {

  /// Le contexte est partagé : en créer un par image recompile les noyaux
  /// Metal à chaque fois.
  static let context = CIContext(options: [.useSoftwareRenderer: false])

  /// `blurRadiusForImage` du compositeur.
  static func blurRadius(for size: CGSize) -> Double {
    max(25, (max(size.width, size.height) * 0.04).rounded())
  }

  /// Le masque du compositeur : les contours remplis, puis adoucis.
  ///
  /// Les polygones sont normalisés avec l'origine **en haut** à gauche (repère
  /// image), alors que CoreGraphics et CoreImage travaillent depuis le bas :
  /// d'où l'inversion de `y`.
  static func mask(persons: [BrowtherIntroMedia.Person], pixelSize: CGSize, feather: Double)
    -> CIImage?
  {
    let width = Int(pixelSize.width.rounded())
    let height = Int(pixelSize.height.rounded())
    guard width > 0, height > 0,
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
      )
    else { return nil }
    context.setFillColor(gray: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(gray: 1, alpha: 1)
    for person in persons {
      let points = person.poly.compactMap { point -> CGPoint? in
        guard point.count == 2 else { return nil }
        return CGPoint(
          x: point[0] * pixelSize.width,
          y: (1 - point[1]) * pixelSize.height
        )
      }
      guard points.count > 2 else { continue }
      context.beginPath()
      context.move(to: points[0])
      for point in points.dropFirst() {
        context.addLine(to: point)
      }
      context.closePath()
      context.fillPath()
    }
    guard let image = context.makeImage() else { return nil }
    let mask = CIImage(cgImage: image)
    guard feather > 0 else { return mask }
    // Le flou du masque déborde de l'image : on le rogne pour que l'extent
    // reste celui du média, sinon la composition part en vrille.
    return
      mask
      .clampedToExtent()
      .applyingGaussianBlur(sigma: feather)
      .cropped(to: mask.extent)
  }

  /// L'image floutée là où le masque est blanc, nette ailleurs.
  static func composite(
    _ image: CIImage,
    persons: [BrowtherIntroMedia.Person],
    target: BrowtherBlurTarget?,
    feather: Double
  ) -> CIImage {
    let visible = persons.filter { $0.isBlurred(for: target) }
    guard !visible.isEmpty else { return image }
    let extent = image.extent
    guard
      let mask = mask(
        persons: visible,
        pixelSize: CGSize(width: extent.width, height: extent.height),
        feather: feather
      )
    else { return image }
    let blurred =
      image
      .clampedToExtent()
      .applyingGaussianBlur(sigma: blurRadius(for: extent.size))
      .cropped(to: extent)
    let blend = CIFilter.blendWithMask()
    blend.inputImage = blurred
    blend.backgroundImage = image
    // Le masque est né à l'origine (0, 0) ; l'image d'une vidéo, pas toujours.
    blend.maskImage = mask.transformed(by: .init(translationX: extent.minX, y: extent.minY))
    return blend.outputImage ?? image
  }
}
