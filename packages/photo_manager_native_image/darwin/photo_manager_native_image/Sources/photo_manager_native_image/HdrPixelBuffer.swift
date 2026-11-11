// Copyright 2026 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import CoreImage
import Foundation
import ImageIO

enum HdrPixelBufferError: Error {
    case decodeFailed
    case allocationFailed
    case notHdr
}

/// Decodes encoded photo data to a premultiplied RGBA buffer of 32-bit floats in
/// extended sRGB (Flutter's `PixelFormat.rgbaFloat32`), allocated with `malloc`.
enum HdrPixelBufferFactory {
    private static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB) as Any,
        .cacheIntermediates: false,
    ])
    private static let outputColorSpace = CGColorSpace(name: CGColorSpace.extendedSRGB)

    /// Values this close to SDR white are treated as SDR.
    private static let hdrThreshold: Float = 1.02

    /// Whether the file carries HDR content: a gain map, or an HDR transfer
    /// function. Reads metadata only.
    @available(iOS 17.0, *)
    static func hasHdrContent(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        if CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil {
            return true
        }
        if #available(iOS 18.0, *),
           CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil {
            return true
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        if let name = properties?[kCGImagePropertyNamedColorSpace] as? String,
           let space = CGColorSpace(name: name as CFString) {
            return CGColorSpaceUsesITUR_2100TF(space)
        }
        return false
    }

    @available(iOS 17.0, *)
    static func make(from data: Data, target: CGSize, maxHeadroom: Double) throws -> PixelBuffer {
        guard var image = CIImage(
            data: data, options: [.expandToHDR: true, .applyOrientationProperty: true])
        else { throw HdrPixelBufferError.decodeFailed }
        let origin = image.extent.origin
        if origin != .zero {
            image = image.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
        }
        if let scaled = PixelBufferFactory.scaledSize(for: image.extent.size, target: target) {
            image = image.transformed(by: CGAffineTransform(
                scaleX: scaled.width / image.extent.width, y: scaled.height / image.extent.height))
        }
        if let filter = CIFilter(name: "CIToneMapHeadroom"),
           filter.inputKeys.contains("inputTargetHeadroom") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(maxHeadroom, forKey: "inputTargetHeadroom")
            image = filter.outputImage ?? image
        }
        let extent = image.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0 else { throw HdrPixelBufferError.decodeFailed }
        let rowBytes = width * 4 * MemoryLayout<Float>.size
        guard let pixels = malloc(rowBytes * height) else { throw HdrPixelBufferError.allocationFailed }
        context.render(
            image, toBitmap: pixels, rowBytes: rowBytes, bounds: extent,
            format: .RGBAf, colorSpace: outputColorSpace)
        guard exceedsSdrWhite(pixels, count: width * height) else {
            free(pixels)
            throw HdrPixelBufferError.notHdr
        }
        return PixelBuffer(data: pixels, width: width, height: height, rowBytes: rowBytes)
    }

    private static func exceedsSdrWhite(_ pixels: UnsafeMutableRawPointer, count: Int) -> Bool {
        let values = pixels.bindMemory(to: Float.self, capacity: count * 4)
        var index = 0
        while index < count * 4 {
            if values[index] > hdrThreshold || values[index + 1] > hdrThreshold
                || values[index + 2] > hdrThreshold {
                return true
            }
            index += 4
        }
        return false
    }
}
