// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CoreVideo
import Foundation
import UIKit

/// Letterbox: resize an image into a square `size × size` canvas while preserving
/// aspect ratio, padding the unused area with a uniform gray value (default 128).
/// Returns the resulting CVPixelBuffer plus the parameters needed to undo the
/// transform (scale + xy offset) so detections expressed in the 640×640 canvas
/// can be mapped back to original image pixel coords.
enum Letterbox {
  struct Result {
    let pixelBuffer: CVPixelBuffer?
    /// Scale applied to original-image dims to fit them inside the canvas.
    let scale: CGFloat
    /// Pixel offset of the resized image within the canvas.
    let offset: CGPoint
    /// Canvas side length (square).
    let canvasSize: CGFloat
    /// Original image size.
    let originalSize: CGSize

    func unmap(point: CGPoint) -> CGPoint {
      CGPoint(
        x: (point.x - offset.x) / scale,
        y: (point.y - offset.y) / scale
      )
    }

    func unmap(rect: CGRect) -> CGRect {
      let origin = unmap(point: rect.origin)
      return CGRect(
        x: origin.x,
        y: origin.y,
        width: rect.width / scale,
        height: rect.height / scale
      )
    }
  }

  static func fit(image: CGImage, to size: CGFloat, padding: UInt8 = 128) -> Result {
    let originalSize = CGSize(width: image.width, height: image.height)
    let scale = min(size / originalSize.width, size / originalSize.height)
    let scaledW = originalSize.width * scale
    let scaledH = originalSize.height * scale
    let offsetX = (size - scaledW) / 2
    let offsetY = (size - scaledH) / 2

    let intSize = Int(size)
    var pixelBuffer: CVPixelBuffer?
    let attrs: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ]
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      intSize, intSize,
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &pixelBuffer
    )
    guard let buffer = pixelBuffer else {
      return Result(
        pixelBuffer: nil,
        scale: scale,
        offset: CGPoint(x: offsetX, y: offsetY),
        canvasSize: size,
        originalSize: originalSize
      )
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

    let base = CVPixelBufferGetBaseAddress(buffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard
      let ctx = CGContext(
        data: base,
        width: intSize,
        height: intSize,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else {
      return Result(
        pixelBuffer: nil,
        scale: scale,
        offset: CGPoint(x: offsetX, y: offsetY),
        canvasSize: size,
        originalSize: originalSize
      )
    }

    // Fill canvas with gray padding.
    let gray = CGFloat(padding) / 255.0
    ctx.setFillColor(red: gray, green: gray, blue: gray, alpha: 1.0)
    ctx.fill(CGRect(x: 0, y: 0, width: intSize, height: intSize))

    // Draw the original image into the centered scaled rect.
    let drawRect = CGRect(x: offsetX, y: offsetY, width: scaledW, height: scaledH)
    ctx.draw(image, in: drawRect)

    return Result(
      pixelBuffer: buffer,
      scale: scale,
      offset: CGPoint(x: offsetX, y: offsetY),
      canvasSize: size,
      originalSize: originalSize
    )
  }
}
