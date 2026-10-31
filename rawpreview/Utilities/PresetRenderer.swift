//
//  PresetRenderer.swift
//  rawpreview
//

import Accelerate
import CoreGraphics
import Foundation

/// Applies a `DevelopPreset` to already-decoded images.
///
/// A table lookup per channel over the display-ready bitmap: ~0.5 ms for a
/// 1024 px preview, ~15 ms for a 20 MP full-resolution image. Results are
/// cached so going back to a photo, or toggling before / after, is instant.
nonisolated enum PresetRenderer {
    /// Two or three full-resolution renders plus their navigation previews.
    private static let cache = ImageCache(name: "preset", totalCostLimitMB: 400, countLimit: 12)

    /// Images up to this many pixels render inline on the caller's thread.
    static let inlinePixelLimit = 2_000_000

    /// `image` with `preset` applied, if that is available without rendering:
    /// `image` itself when there is nothing to apply, or a cached render.
    static func cached(_ image: CGImage, preset: DevelopPreset?, url: URL) -> CGImage? {
        guard let preset, !preset.isNoOp else { return image }
        return cache[key(image, preset: preset, url: url)]
    }

    /// Renders now on the current thread. Fine for previews and thumbnails;
    /// use `renderDetached` for full-resolution images.
    static func render(_ image: CGImage, preset: DevelopPreset?, url: URL) -> CGImage {
        if let hit = cached(image, preset: preset, url: url) { return hit }
        guard let preset, let rendered = apply(preset, to: image) else { return image }
        cache[key(image, preset: preset, url: url)] = rendered
        return rendered
    }

    static func renderDetached(_ image: CGImage, preset: DevelopPreset?, url: URL) async -> CGImage {
        if let hit = cached(image, preset: preset, url: url) { return hit }
        return await Task.detached(priority: .userInitiated) {
            render(image, preset: preset, url: url)
        }.value
    }

    private static func apply(_ preset: DevelopPreset, to image: CGImage) -> CGImage? {
        let lut = preset.lut
        // Same layout as `ImageDecoder.prepareForDisplay`, so drawing the
        // source in is a straight copy and the result needs no further
        // conversion on screen.
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? DisplayColorSpace.target
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ), let data = context.data
        else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        var buffer = vImage_Buffer(
            data: data,
            height: vImagePixelCount(image.height),
            width: vImagePixelCount(image.width),
            rowBytes: context.bytesPerRow
        )
        // 32-bit little-endian with the unused byte first is B, G, R, X in
        // memory; vImage names those four bytes "A, R, G, B".
        if preset.isMonochrome {
            guard grayscale(&buffer) == kvImageNoError else { return nil }
        }
        let error = lut.blue.withUnsafeBufferPointer { blue in
            lut.green.withUnsafeBufferPointer { green in
                lut.red.withUnsafeBufferPointer { red in
                    identityTable.withUnsafeBufferPointer { identity in
                        vImageTableLookUp_ARGB8888(
                            &buffer, &buffer,
                            blue.baseAddress, green.baseAddress, red.baseAddress, identity.baseAddress,
                            vImage_Flags(kvImageNoFlags)
                        )
                    }
                }
            }
        }
        guard error == kvImageNoError, !Task.isCancelled else { return nil }
        return context.makeImage()
    }

    /// Replaces B, G and R with luma (Rec. 601 weights on the gamma-encoded
    /// values, close to Lightroom's default B&W mix); leaves X alone.
    private static func grayscale(_ buffer: inout vImage_Buffer) -> vImage_Error {
        let divisor: Int32 = 256
        let (r, g, b): (Int16, Int16, Int16) = (77, 150, 29) // sums to 256
        // Row = source byte, column = destination byte, both in memory order B, G, R, X.
        let matrix: [Int16] = [
            b, b, b, 0,
            g, g, g, 0,
            r, r, r, 0,
            0, 0, 0, Int16(divisor),
        ]
        // In place: a second descriptor of the same pixels.
        var source = buffer
        return vImageMatrixMultiply_ARGB8888(&source, &buffer, matrix, divisor, nil, nil, vImage_Flags(kvImageNoFlags))
    }

    private static let identityTable = (0...255).map(UInt8.init)

    private static func key(_ image: CGImage, preset: DevelopPreset, url: URL) -> String {
        "\(preset.revision)|\(image.width)x\(image.height)|\(url.path(percentEncoded: false))"
    }
}
