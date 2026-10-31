//
//  PresetRenderer.swift
//  rawpreview
//

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import os

/// Applies a `DevelopPreset` to already-decoded images with Core Image on the
/// GPU: clarity / texture, the preset's colour as a 3D lookup table (see
/// `PresetLook`), then vignette and grain.
///
/// A few ms for a 1024 px preview, tens of ms for a 20 MP full-resolution
/// image. Results are cached so going back to a photo, or toggling before /
/// after, is instant.
nonisolated enum PresetRenderer {
    /// One full-resolution render plus navigation previews: the original is
    /// already in `PreviewService`, so more would mostly duplicate memory.
    private static let cache = ImageCache(name: "preset", totalCostLimitMB: 120, countLimit: 6)
    /// Lookup tables by preset revision; ~575 KB each, built on first use.
    /// Stepping through presets ([ / ]) can touch hundreds, so only the most
    /// recent `cubeLimit` are kept.
    private static let cubes = OSAllocatedUnfairLock<(tables: [UUID: Data], order: [UUID])>(initialState: ([:], []))
    private static let cubeLimit = 48
    private static let cubeDimension = 33
    /// 8-bit working buffers: the default half-float ones cost 8 bytes a pixel,
    /// ~180 MB per intermediate for a 24 MP photo, and a preset with clarity,
    /// vignette and grain needs several. Plenty of precision for a preview.
    private static let context = CIContext(options: [
        .workingFormat: CIFormat.RGBA8,
        .cacheIntermediates: false,
    ])
    /// Above this many pixels an image renders in bands of `bandHeight` rows
    /// (see `apply`), and Core Image's buffers are released afterwards.
    private static let largeImagePixels = 4_000_000
    private static let bandHeight = 512
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// `image` with `preset` applied, if that is available without rendering:
    /// `image` itself when there is nothing to apply, or a cached render.
    static func cached(_ image: CGImage, preset: DevelopPreset?, url: URL) -> CGImage? {
        guard let preset, !preset.isNoOp else { return image }
        return cache[key(image, preset: preset, url: url)]
    }

    /// Renders now on the current thread. Fine for previews; use
    /// `renderDetached` for full-resolution images.
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
        let look = preset.look
        let input = CIImage(cgImage: image)
        let extent = input.extent
        // Sizes are relative to the image, so a 1024 px preview and the full
        // image look alike at the same zoom-to-fit.
        let longSide = max(extent.width, extent.height)

        var output = input
        output = localContrast(output, source: image, amount: look.texture * 0.6, radius: longSide * 0.004)
        output = localContrast(output, source: image, amount: look.clarity * 0.8, radius: longSide * 0.02)

        let cube = CIFilter.colorCubeWithColorSpace()
        cube.inputImage = output
        cube.cubeDimension = Float(cubeDimension)
        cube.cubeData = cubeData(for: preset)
        // The look works on gamma-encoded sRGB values, like the sliders do.
        cube.colorSpace = sRGB
        output = cube.outputImage ?? output

        if let vignette = look.vignette {
            output = applyVignette(vignette, to: output, extent: extent)
        }
        if let grain = look.grain {
            output = applyGrain(grain, to: output, longSide: longSide)
        }

        guard !Task.isCancelled else { return nil }
        // Rendered here, into our own bitmap. `createCGImage` would hand back
        // an image that renders lazily, the first time it is drawn: on the
        // main thread, hundreds of ms for a full-resolution photo.
        // Same colour space and layout as `ImageDecoder.prepareForDisplay`,
        // so it still needs no conversion on screen.
        guard let bitmap = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? DisplayColorSpace.target,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ), let data = bitmap.data
        else { return nil }
        // In horizontal bands, so Core Image's working buffers are the size of
        // a band rather than of the whole photo (measured on 24 MP: ~190 MB
        // more in one pass, ~140 MB more again with negative clarity).
        let final = output.cropped(to: extent)
        let rowBytes = bitmap.bytesPerRow
        let bandHeight = image.width * image.height > largeImagePixels ? Self.bandHeight : image.height
        var top = 0
        while top < image.height {
            guard !Task.isCancelled else { return nil }
            let rows = min(bandHeight, image.height - top)
            // Bitmap rows run top-down; Core Image's y axis runs bottom-up.
            let band = CGRect(x: 0, y: image.height - top - rows, width: image.width, height: rows)
            context.render(
                final,
                toBitmap: data.advanced(by: top * rowBytes),
                rowBytes: rowBytes,
                bounds: band,
                format: .BGRA8,
                colorSpace: bitmap.colorSpace
            )
            top += rows
        }
        if bandHeight < image.height {
            context.clearCaches()
        }
        return bitmap.makeImage()
    }

    private static func cubeData(for preset: DevelopPreset) -> Data {
        let id = preset.revision
        if let data = cubes.withLock({ $0.tables[id] }) { return data }
        let data = preset.look.cubeData(dimension: cubeDimension)
        cubes.withLock { state in
            if state.tables.updateValue(data, forKey: id) == nil {
                state.order.append(id)
            }
            while state.order.count > cubeLimit {
                state.tables[state.order.removeFirst()] = nil
            }
        }
        return data
    }

    /// `(1 + amount)·image − amount·blurred`: an unsharp mask with a wide
    /// radius for positive amounts (more local contrast), a blend towards the
    /// blur for negative ones (softer, like negative Clarity).
    private static func localContrast(_ image: CIImage, source: CGImage, amount: Double, radius: Double) -> CIImage {
        guard amount != 0, radius >= 0.5 else { return image }
        let extent = image.extent

        // The blur only keeps coarse detail, so it's computed on a copy of the
        // source shrunk (by Core Graphics, outside Core Image) until the
        // radius is ~8 px, then scaled back up. Blurring or even downscaling
        // the full-size image in Core Image cost it hundreds of MB.
        let factor = max(1, radius / 8)
        guard let small = shrunk(source, by: factor) else { return image }
        let blurred = small.clampedToExtent()
            .applyingGaussianBlur(sigma: radius / factor)
            .cropped(to: small.extent)
            .transformed(by: CGAffineTransform(
                scaleX: extent.width / small.extent.width,
                y: extent.height / small.extent.height
            ))
            .clampedToExtent()
            .cropped(to: extent)

        // Core Image fuses these per-pixel steps into one pass, so the
        // out-of-range values in between never hit an 8-bit buffer.
        func scaled(_ image: CIImage, by factor: Double) -> CIImage {
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = image
            matrix.rVector = CIVector(x: factor, y: 0, z: 0, w: 0)
            matrix.gVector = CIVector(x: 0, y: factor, z: 0, w: 0)
            matrix.bVector = CIVector(x: 0, y: 0, z: factor, w: 0)
            return matrix.outputImage ?? image
        }
        let subtract = CIFilter.subtractBlendMode()
        subtract.inputImage = scaled(blurred, by: amount)
        subtract.backgroundImage = scaled(image, by: 1 + amount)
        return subtract.outputImage?.cropped(to: extent) ?? image
    }

    private static func shrunk(_ image: CGImage, by factor: Double) -> CIImage? {
        guard factor > 1 else { return CIImage(cgImage: image) }
        let width = max(1, Int((Double(image.width) / factor).rounded()))
        let height = max(1, Int((Double(image.height) / factor).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? sRGB,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage().map { CIImage(cgImage: $0) }
    }

    /// An ellipse following the frame (Lightroom's Roundness 0): darkens or
    /// lightens towards the corners.
    private static func applyVignette(_ vignette: PresetLook.Vignette, to image: CIImage, extent: CGRect) -> CIImage {
        // Built as a circle in a square of the image's height, then stretched.
        let corner = extent.height / 2 * 2.squareRoot()
        let reach = 0.25 + 0.6 * vignette.midpoint
        let inner = corner * reach * (1 - 0.6 * vignette.feather)
        let outer = max(inner + 1, corner * (reach * (1 + 0.6 * vignette.feather) + 0.15))
        let strength = min(abs(vignette.amount) * 0.85, 1)

        let gradient = CIFilter.radialGradient()
        gradient.center = .zero
        gradient.radius0 = Float(inner)
        gradient.radius1 = Float(outer)
        let darkens = vignette.amount < 0
        gradient.color0 = gray(darkens ? 1 : 0)
        gradient.color1 = gray(darkens ? 1 - strength : strength)
        guard let mask = gradient.outputImage?
            .transformed(by: CGAffineTransform(scaleX: extent.width / extent.height, y: 1)
                .concatenating(CGAffineTransform(translationX: extent.midX, y: extent.midY)))
            .cropped(to: extent)
        else { return image }

        let blend: CIFilter & CICompositeOperation = darkens ? CIFilter.multiplyCompositing() : CIFilter.screenBlendMode()
        blend.inputImage = mask
        blend.backgroundImage = image
        return blend.outputImage ?? image
    }

    /// Monochrome noise added to every channel; scaled with the image so
    /// grain size is a property of the photo, not of the preview's pixels.
    private static func applyGrain(_ grain: PresetLook.Grain, to image: CIImage, longSide: Double) -> CIImage {
        // Lightroom's default size (25) is about one pixel of a 4000 px image.
        let scale = (0.6 + grain.size * 1.6) * longSide / 4000
        // Grain finer than a pixel averages out in a small preview.
        let amplitude = grain.amount * 0.14 * min(1, scale.squareRoot())

        guard let random = CIFilter.randomGenerator().outputImage else { return image }
        let monochrome = CIFilter.colorMatrix()
        monochrome.inputImage = random
        let spread = CIVector(x: 2 * amplitude, y: 0, z: 0, w: 0)
        monochrome.rVector = spread
        monochrome.gVector = spread
        monochrome.bVector = spread
        monochrome.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        monochrome.biasVector = CIVector(x: -amplitude, y: -amplitude, z: -amplitude, w: 0)
        guard let noise = monochrome.outputImage?
            .transformed(by: CGAffineTransform(scaleX: max(scale, 1), y: max(scale, 1)))
            .cropped(to: image.extent)
        else { return image }

        let add = CIFilter.additionCompositing()
        add.inputImage = noise
        add.backgroundImage = image
        return add.outputImage ?? image
    }

    private static func gray(_ value: Double) -> CIColor {
        CIColor(red: value, green: value, blue: value, alpha: 1, colorSpace: sRGB) ?? CIColor(red: value, green: value, blue: value)
    }

    private static func key(_ image: CGImage, preset: DevelopPreset, url: URL) -> String {
        "\(preset.revision)|\(image.width)x\(image.height)|\(url.path(percentEncoded: false))"
    }
}
