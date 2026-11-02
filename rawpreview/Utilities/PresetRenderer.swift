//
//  PresetRenderer.swift
//  rawpreview
//

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import os

/// Legacy bitmap renderer retained for phase 1 benchmark comparisons. The
/// source-aware production path is DevelopRenderer; its LUT cache and spatial
/// effects reuse the helpers here.
/// Applies a `DevelopPreset` to already-decoded images with Core Image on the
/// GPU: clarity / texture, the preset's colour as a 3D lookup table (see
/// `PresetLook`), then vignette and grain.
///
/// A few ms for a 1024 px preview, tens of ms for a 20 MP full-resolution
/// image. Results are cached so going back to a photo, or toggling before /
/// after, is instant.
nonisolated enum PresetRenderer {
    private struct SourceKey: Hashable, Sendable {
        let file: String
        let width: Int
        let height: Int
        let profile: Data?
        let displayGeneration: Int
        let version: Int
    }
    private struct ResultKey: Hashable, Sendable {
        let source: SourceKey
        let look: DevelopPreset.RenderKey
    }
    private struct WorkKey: Hashable, Sendable {
        let result: ResultKey
        let interactive: Bool
    }
    enum Purpose: Sendable {
        case selected, hover, tile
    }
    // Hover/tile churn cannot evict the selected look needed on pointer exit.
    private static let cache = BoundedCache<ResultKey, CGImage>(byteLimit: 120 * 1024 * 1024, countLimit: 6)
    private static let transient = BoundedCache<ResultKey, CGImage>(byteLimit: 16 * 1024 * 1024, countLimit: 24)
    private static let pending = SharedWork<WorkKey, CGImage>()
    private static let cubes = BoundedCache<DevelopPreset.ColorKey, Data>(byteLimit: 28 * 1024 * 1024, countLimit: 48)
    private static let cubeDimension = 33
    /// 8-bit working buffers: the default half-float ones cost 8 bytes a pixel,
    /// ~180 MB per intermediate for a 24 MP photo, and a preset with clarity,
    /// vignette and grain needs several. Plenty of precision for a preview.
    private static let context = CIContext(options: [
        .workingFormat: CIFormat.RGBA8,
        .cacheIntermediates: false,
    ])
    /// Exports work in half-float: 8-bit intermediates round every step,
    /// which shows as banding in skies once a tone curve stretches them.
    /// Rendering in bands keeps the larger buffers affordable.
    private static let exportContext = CIContext(options: [
        .workingFormat: CIFormat.RGBAh,
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
        let key = key(image, preset: preset, url: url)
        return cache[key] ?? transient[key]
    }

    /// Both cache misses and LUT generation run through the shared render
    /// permit. Interactive callers replace the lane's pending request.
    static func renderDetached(
        _ image: CGImage,
        preset: DevelopPreset?,
        url: URL,
        priority: AsyncLimiter.Priority = .high,
        purpose: Purpose = .selected
    ) async -> CGImage {
        guard !Task.isCancelled else { return image }
        if let hit = cached(image, preset: preset, url: url) {
            PipelineMetrics.event("render.hit")
            return hit
        }
        guard let preset else { return image }
        let requestID = RenderCoordinator.nextRequestID()
        let key = key(image, preset: preset, url: url)
        return await pending.run(
            WorkKey(result: key, interactive: priority == .high),
            priority: priority == .low ? .utility : .userInitiated,
            latest: priority == .high ? .init(lane: "loupe", id: requestID) : nil
        ) {
            await RenderCoordinator.run(priority, latest: priority == .high ? "loupe.render" : nil, requestID: requestID) {
                // A previous request may have finished while this one waited.
                if let hit = cache[key] ?? transient[key] { return hit }
                guard !Task.isCancelled else { return nil }
                PipelineMetrics.event("render.miss")
                guard let rendered = apply(preset, to: image), !Task.isCancelled else { return nil }
                let target = purpose == .selected ? cache : transient
                target.insert(rendered, for: key, cost: rendered.bytesPerRow * rendered.height) {
                    // Keep only the latest selected look for a photo/size.
                    purpose == .selected && $0.source == key.source
                }
                return rendered
            }
        } ?? image
    }

    /// Called inside RenderCoordinator's file-output permit, in half-float.
    /// Does not fill the preview cache. This API is internal to file workers.
    static func export(_ image: CGImage, preset: DevelopPreset, sixteenBit: Bool = false) -> CGImage? {
        preset.isNoOp ? image : apply(preset, to: image, context: exportContext, sixteenBit: sixteenBit)
    }

    static func removeAll() {
        cache.removeAll()
        transient.removeAll()
        cubes.removeAll()
        context.clearCaches()
        exportContext.clearCaches()
    }

    private static func apply(
        _ preset: DevelopPreset,
        to image: CGImage,
        context: CIContext = context,
        sixteenBit: Bool = false
    ) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        guard let cubeData = cubeData(for: preset) else { return nil }
        guard !Task.isCancelled else { return nil }
        let timing = PipelineMetrics.begin("Render")
        defer { PipelineMetrics.end(timing) }
        let input = CIImage(cgImage: image)
        let extent = input.extent
        // Sizes are relative to the image, so a 1024 px preview and the full
        // image look alike at the same zoom-to-fit.
        let longSide = max(extent.width, extent.height)

        var output = input
        output = localContrast(output, source: image, amount: preset.texture * 0.6, radius: longSide * 0.004)
        guard !Task.isCancelled else { return nil }
        output = localContrast(output, source: image, amount: preset.clarity * 0.8, radius: longSide * 0.02)

        guard !Task.isCancelled else { return nil }
        let cube = CIFilter.colorCubeWithColorSpace()
        cube.inputImage = output
        cube.cubeDimension = Float(cubeDimension)
        cube.cubeData = cubeData
        // The look works on gamma-encoded sRGB values, like the sliders do.
        cube.colorSpace = sRGB
        output = cube.outputImage ?? output

        if let vignette = preset.vignette {
            output = applyVignette(vignette, to: output, extent: extent)
        }
        if let grain = preset.grain {
            output = applyGrain(grain, to: output, longSide: longSide)
        }

        guard !Task.isCancelled else { return nil }
        // Rendered here, into our own bitmap. `createCGImage` would hand back
        // an image that renders lazily, the first time it is drawn: on the
        // main thread, hundreds of ms for a full-resolution photo.
        // Same colour space and layout as `ImageDecoder.prepareForDisplay`,
        // so it still needs no conversion on screen. A grey source (B&W
        // JPEG) comes out in sRGB: a preset may tint it.
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? sRGB
        guard let bitmap = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: sixteenBit ? 16 : 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: sixteenBit
                ? CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
                : CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
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
                format: sixteenBit ? .RGBA16 : .BGRA8,
                colorSpace: bitmap.colorSpace
            )
            top += rows
        }
        if bandHeight < image.height {
            context.clearCaches()
        }
        return bitmap.makeImage()
    }

    static func cubeData(for preset: DevelopPreset) -> Data? {
        let key = preset.colorKey
        if let data = cubes[key] {
            PipelineMetrics.event("lut.hit")
            return data
        }
        // All preview/export workers hold the same permit here. The second
        // caller rechecks the content cache instead of building a duplicate.
        guard !Task.isCancelled else { return nil }
        PipelineMetrics.event("lut.miss")
        let timing = PipelineMetrics.begin("LUT")
        let data = preset.cubeData(dimension: cubeDimension)
        PipelineMetrics.end(timing)
        guard !Task.isCancelled, !data.isEmpty else { return nil }
        cubes.insert(data, for: key, cost: data.count)
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

    private static let vignetteKernel = DevelopKernels.general("postCropVignette")

    /// Lightroom's post-crop vignette: an ellipse following the frame at
    /// Roundness 0, a circle at 100, close to the frame's rectangle at -100;
    /// Highlight Priority keeps bright areas, Color Priority keeps hues,
    /// Paint Overlay mixes towards black or white.
    static func applyVignette(_ vignette: PresetLook.Vignette, to image: CIImage, extent: CGRect) -> CIImage {
        // Distances are in half-frame units, so a corner is √2 away.
        let corner = 2.0.squareRoot()
        let reach = 0.25 + 0.6 * vignette.midpoint
        let inner = corner * reach * (1 - 0.6 * vignette.feather)
        let outer = max(inner + 0.01, corner * (reach * (1 + 0.6 * vignette.feather) + 0.15))
        let strength = min(abs(vignette.amount) * 0.85, 1)
        guard let vignetteKernel,
              let output = vignetteKernel.apply(
                  extent: extent,
                  roiCallback: { _, rect in rect },
                  arguments: [
                      image,
                      CIVector(x: extent.midX, y: extent.midY, z: extent.width / 2, w: extent.height / 2),
                      CIVector(x: vignette.roundness, y: inner, z: outer, w: 0),
                      CIVector(x: vignette.amount < 0 ? -strength : strength, y: Double(vignette.style.rawValue),
                               z: vignette.highlightContrast, w: 0),
                  ])
        else { return image }
        return output
    }

    private static let grainKernel = DevelopKernels.color("filmGrain")

    /// Monochrome grain, strongest in the midtones as in Lightroom; Roughness
    /// mixes in a coarser layer. Scaled with the image so grain size is a
    /// property of the photo, not of the preview's pixels.
    static func applyGrain(_ grain: PresetLook.Grain, to image: CIImage, longSide: Double) -> CIImage {
        // Lightroom's default size (25) is about one pixel of a 4000 px image.
        let scale = (0.6 + grain.size * 1.6) * longSide / 4000
        // Grain finer than a pixel averages out in a small preview.
        let amplitude = grain.amount * 0.14 * min(1, scale.squareRoot())

        guard let random = CIFilter.randomGenerator().outputImage, let grainKernel else { return image }
        let fine = random.transformed(by: CGAffineTransform(scaleX: max(scale, 1), y: max(scale, 1))).cropped(to: image.extent)
        let coarse = random
            .transformed(by: CGAffineTransform(translationX: 1031, y: 577))
            .transformed(by: CGAffineTransform(scaleX: max(scale * 2.3, 1), y: max(scale * 2.3, 1)))
            .cropped(to: image.extent)
        return grainKernel.apply(extent: image.extent, arguments: [image, fine, coarse, amplitude, grain.roughness]) ?? image
    }

    private static func key(_ image: CGImage, preset: DevelopPreset, url: URL) -> ResultKey {
        ResultKey(source: SourceKey(
            file: ImageSourceKey.file(url),
            width: image.width,
            height: image.height,
            profile: image.colorSpace?.copyICCData() as Data?,
            displayGeneration: DisplayColorSpace.generation,
            version: ImageSourceKey.pipelineVersion
        ), look: preset.renderKey)
    }
}
