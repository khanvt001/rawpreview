import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Half-float graph shared by preview and export. Only its last bitmap/profile
/// conversion differs. The creative LUT still approximates Lightroom.
nonisolated enum DevelopRenderer {
    static func resized(_ source: DevelopImage, longEdge: Int) throws -> DevelopImage {
        let factor = min(1, Double(longEdge) / Double(max(source.image.width, source.image.height)))
        guard factor < 1 else { return source }
        try Task.checkCancellation()
        let scaled = CIImage(cgImage: source.image).transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        guard let image = DevelopDecoder.context.createCGImage(scaled, from: scaled.extent.integral, format: .RGBAh,
                                                              colorSpace: DevelopDecoder.workingSpace, deferred: false)
        else { throw DevelopError.renderFailed }
        return DevelopImage(image: image, isRAW: source.isRAW, nativeSize: source.nativeSize, neutral: source.neutral)
    }
    /// The RAW base curve: scene-linear luminance to the brightness a camera
    /// JPEG gives it. A Hill curve, y = xⁿ / (xⁿ + Kⁿ), fitted to luminance
    /// quantiles of Nikon Z 50 NEF + in-camera JPEG pairs (boost 0 decode):
    /// mid grey gains ~1.4 EV, shadows less, highlights roll off towards 1.
    /// RMS error ×1.16, against ×2.4 for the previous linear-plus-shoulder.
    static let baseCurveExponent = 1.30
    static let baseCurveMidpoint = 0.206
    private static let baseCurve = DevelopKernels.color("rawBaseCurve")
    private static let lumaDetail = DevelopKernels.color("lumaDetail")

    /// `extraGain` adjusts a RAW base decoded at another white balance.
    static func render(_ source: DevelopImage, state: DevelopState, outputSpace: CGColorSpace, sixteenBit: Bool = false,
                       extraGain: SIMD3<Double> = SIMD3(repeating: 1)) throws -> CGImage {
        try Task.checkCancellation()
        let color = state.colorPreset
        let cubeData: Data?
        if let color, !color.isNoOp {
            guard let data = PresetRenderer.cubeData(for: color) else { throw CancellationError() }
            cubeData = data
        } else { cubeData = nil }
        let timing = PipelineMetrics.begin("DevelopRender")
        defer { PipelineMetrics.end(timing) }
        let input = CIImage(cgImage: source.image)
        let extent = input.extent
        let gain = state.linearGain(isRAW: source.isRAW) * extraGain
        var output = input
        if gain != SIMD3(repeating: 1) {
            let matrix = CIFilter.colorMatrix()
            let working = ColorMath.workingGain(gain)
            matrix.inputImage = output
            matrix.rVector = CIVector(x: working.r.x, y: working.r.y, z: working.r.z, w: 0)
            matrix.gVector = CIVector(x: working.g.x, y: working.g.y, z: working.g.z, w: 0)
            matrix.bVector = CIVector(x: working.b.x, y: working.b.y, z: working.b.z, w: 0)
            output = matrix.outputImage ?? output
        }
        // A RAW is sharpened and denoised by its decoder; a processed image
        // (already sharpened in camera) only by what the preset asks for.
        if !source.isRAW {
            output = detail(output, state.detail(isRAW: false), extent: extent)
        }
        // Scene-linear RAW to display brightness, before the creative LUT,
        // which expects camera-rendered input like the embedded preview.
        // Exposure deltas are already combined, so nothing clips before an
        // opposite Edit delta is applied.
        if source.isRAW {
            guard let baseCurve,
                  let mapped = baseCurve.apply(extent: extent, arguments: [
                      output, baseCurveExponent, pow(baseCurveMidpoint, baseCurveExponent),
                  ])
            else { throw DevelopError.renderFailed }
            output = mapped
        }
        if let preset = state.effectivePreset, preset.dehaze != 0 {
            output = try dehaze(output, amount: preset.dehaze, extent: extent)
        }
        if let preset = state.effectivePreset {
            output = try localContrast(output, amount: preset.texture * 0.6, radius: max(extent.width, extent.height) * 0.004)
            output = try localContrast(output, amount: preset.clarity * 0.8, radius: max(extent.width, extent.height) * 0.02)
        }
        try Task.checkCancellation()
        if let cubeData {
            let cube = CIFilter.colorCubeWithColorSpace()
            cube.inputImage = output
            cube.cubeDimension = 33
            cube.cubeData = cubeData
            cube.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            output = cube.outputImage ?? output
        }
        if let vignette = state.effectivePreset?.vignette { output = PresetRenderer.applyVignette(vignette, to: output, extent: extent) }
        if let grain = state.effectivePreset?.grain { output = PresetRenderer.applyGrain(grain, to: output, longSide: max(extent.width, extent.height)) }
        return try bitmap(output.cropped(to: extent), width: source.image.width, height: source.image.height, space: outputSpace, sixteenBit: sixteenBit)
    }

    /// Luminance noise reduction, then luminance sharpening, at radii scaled
    /// with the image so a preview and a full-size export look alike.
    private static func detail(_ input: CIImage, _ detail: DevelopState.Detail, extent: CGRect) -> CIImage {
        let scale = max(extent.width, extent.height) / 6000
        var output = input
        if detail.luminanceNoise > 0 {
            let filter = CIFilter.noiseReduction()
            filter.inputImage = output
            filter.noiseLevel = Float(0.06 * detail.luminanceNoise / 100)
            filter.sharpness = 0
            output = filter.outputImage?.cropped(to: extent) ?? output
        }
        if detail.sharpness > 0, scale > 0.15 {
            let filter = CIFilter.sharpenLuminance()
            filter.inputImage = output
            filter.sharpness = Float(detail.sharpness / 100)
            filter.radius = Float(1.0 * scale)
            output = filter.outputImage?.cropped(to: extent) ?? output
        }
        return output
    }

    private static let darkChannel = DevelopKernels.color("darkChannel")
    private static let dehazeKernel = DevelopKernels.color("regionalDehaze")

    /// Dehaze with a dark-channel haze estimate (He et al.): haze is thick
    /// where even the darkest channel of a neighbourhood is bright. Positive
    /// amounts invert the haze model there; negative ones add haze, more in
    /// regions that already have some. The estimate comes from a ~256 px
    /// copy, so preview and export find the same regions.
    private static func dehaze(_ input: CIImage, amount: Double, extent: CGRect) throws -> CIImage {
        let factor = min(1, 256 / max(extent.width, extent.height))
        let small = input.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        guard let darkChannel, let dehazeKernel, let dark = darkChannel.apply(extent: small.extent, arguments: [small]) else {
            throw DevelopError.renderFailed
        }
        let minimum = CIFilter.morphologyMinimum()
        minimum.inputImage = dark.clampedToExtent()
        minimum.radius = 3
        guard let haze = minimum.outputImage?
            .applyingGaussianBlur(sigma: 6)
            .cropped(to: small.extent)
            .transformed(by: CGAffineTransform(scaleX: 1 / factor, y: 1 / factor))
            .clampedToExtent()
            .cropped(to: extent),
              let result = dehazeKernel.apply(extent: extent, arguments: [input, haze, amount])
        else { throw DevelopError.renderFailed }
        return result
    }

    private static func localContrast(_ input: CIImage, amount: Double, radius: Double) throws -> CIImage {
        guard amount != 0, radius >= 0.5 else { return input }
        let extent = input.extent
        let factor = max(1, radius / 8)
        let small = input.transformed(by: CGAffineTransform(scaleX: 1 / factor, y: 1 / factor))
        let blur = small.clampedToExtent().applyingGaussianBlur(sigma: radius / factor)
            .cropped(to: small.extent).transformed(by: CGAffineTransform(scaleX: factor, y: factor)).cropped(to: extent)
        guard let lumaDetail, let result = lumaDetail.apply(extent: extent, arguments: [input, blur, amount]) else { throw DevelopError.renderFailed }
        return result
    }

    private static func bitmap(_ output: CIImage, width: Int, height: Int, space: CGColorSpace, sixteenBit: Bool) throws -> CGImage {
        try Task.checkCancellation()
        guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: sixteenBit ? 16 : 8,
                                    bytesPerRow: 0, space: space,
                                    bitmapInfo: sixteenBit ? CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
                                        : CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let data = bitmap.data else { throw DevelopError.renderFailed }
        defer { if width * height > 4_000_000 { DevelopDecoder.context.clearCaches() } }
        var top = 0
        while top < height {
            try Task.checkCancellation()
            let rows = min(512, height - top)
            DevelopDecoder.context.render(output, toBitmap: data.advanced(by: top * bitmap.bytesPerRow), rowBytes: bitmap.bytesPerRow,
                                         bounds: CGRect(x: 0, y: height - top - rows, width: width, height: rows),
                                         format: sixteenBit ? .RGBA16 : .BGRA8, colorSpace: space)
            top += rows
        }
        guard let image = bitmap.makeImage() else { throw DevelopError.renderFailed }
        return image
    }
}
