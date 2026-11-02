import CoreGraphics
import CoreImage
import Foundation

nonisolated enum DevelopError: LocalizedError, Sendable {
    case unsupportedRAW(URL)
    case noEmbeddedPreview(URL)
    case decodeFailed(URL)
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedRAW(let url):
            String(localized: "RAW processing isn't available for \(url.lastPathComponent). Choose Use Embedded Preview for this photo, or change the processing source in Settings.")
        case .noEmbeddedPreview(let url):
            String(localized: "\(url.lastPathComponent) has no readable embedded preview. Choose Original RAW in Settings to develop the RAW file.")
        case .decodeFailed(let url): String(localized: "Couldn't decode \(url.lastPathComponent).")
        case .renderFailed: String(localized: "Couldn't render this image with the selected processing source.")
        }
    }
}

nonisolated struct DevelopImage: Sendable {
    let image: CGImage
    let isRAW: Bool
    let nativeSize: CGSize
    /// The white balance a RAW base was decoded with, so a cached base can
    /// stand in for another white balance until its own decode exists.
    var neutral: RAWNeutral? = nil
}

nonisolated struct RAWNeutral: Sendable, Hashable {
    let asShotTemperature: Double
    let asShotTint: Double
    let temperature: Double
    let tint: Double

    /// The decoder's neutral for `wb`, from the photo's as-shot neutral.
    init(_ wb: DevelopState.WhiteBalance, asShotTemperature: Double, asShotTint: Double) {
        self.asShotTemperature = asShotTemperature
        self.asShotTint = asShotTint
        var temperature = asShotTemperature
        var tint = asShotTint
        if let target = wb.temperature, target > 0, asShotTemperature > 0 {
            let mired = 1_000_000 / asShotTemperature + (1_000_000 / target - 1_000_000 / asShotTemperature) * wb.amount
            temperature = min(50_000, max(2000, 1_000_000 / mired))
        }
        if let target = wb.tint { tint = asShotTint + (target - asShotTint) * wb.amount }
        if wb.incrementalTemperature != 0 {
            let mired = 1_000_000 / temperature - wb.incrementalTemperature * 0.5
            temperature = min(50_000, max(2000, 1_000_000 / max(mired, 20)))
        }
        self.temperature = temperature
        self.tint = min(150, max(-150, tint + wb.incrementalTint))
    }

    /// Linear gain that approximately turns this decode into one at `wb`
    /// (warmer for a higher neutral temperature, magenta for a higher tint,
    /// as in Lightroom). Approximate: for hover and tiles only.
    func gain(to wb: DevelopState.WhiteBalance) -> SIMD3<Double> {
        let target = RAWNeutral(wb, asShotTemperature: asShotTemperature, asShotTint: asShotTint)
        let mired = 1_000_000 / temperature - 1_000_000 / target.temperature
        let tint = target.tint - self.tint
        guard mired != 0 || tint != 0 else { return SIMD3(repeating: 1) }
        let gain = SIMD3(exp(mired * 0.0035), exp(-tint * 0.0025), exp(-mired * 0.0035))
        return gain / ColorMath.dot(gain, ColorMath.sRGBToXYZ.g)
    }
}

nonisolated enum DevelopDecoder {
    static let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
    static let context = CIContext(options: [
        .workingFormat: CIFormat.RGBAh,
        .workingColorSpace: workingSpace,
        .cacheIntermediates: false,
    ])

    /// Called under the common heavy-work permit. Materializing the small
    /// half-float image severs the lazy graph's reference to the RAW decoder.
    static func decode(_ url: URL, state: DevelopState, longEdge: Int?) throws -> DevelopImage {
        try Task.checkCancellation()
        if !state.processing.usesRAW(for: url) {
            guard let image = ImageDecoder.embeddedSource(url, maxPixelSize: longEdge) else {
                try Task.checkCancellation()
                if MediaKind(fileExtension: url.pathExtension) == .raw { throw DevelopError.noEmbeddedPreview(url) }
                throw DevelopError.decodeFailed(url)
            }
            return DevelopImage(image: image, isRAW: false, nativeSize: CGSize(width: image.width, height: image.height))
        }
        let timing = PipelineMetrics.begin("RAWDecode")
        defer { PipelineMetrics.end(timing) }
        guard let filter = CIRAWFilter(imageURL: url) else { throw DevelopError.unsupportedRAW(url) }
        let native = filter.nativeSize
        let longest = max(native.width, native.height)
        if let longEdge, longest > 0 { filter.scaleFactor = Float(min(1, Double(longEdge) / longest)) }
        // Retain scene headroom for the shared exposure/tone stage. Never
        // cache a display-converted 8-bit RAW base.
        filter.boostAmount = 0
        filter.extendedDynamicRangeAmount = 1
        filter.isGamutMappingEnabled = false
        if filter.isLocalToneMapSupported { filter.localToneMapAmount = 0 }
        if filter.isContrastSupported { filter.contrastAmount = 0 }
        // Sharpening and noise reduction run in the decoder, mapped so that
        // Lightroom's RAW defaults (Sharpening 40, Color NR 25) land on Core
        // Image's own (sharpness 1, color NR 0.5). Lens correction stays on,
        // as Lightroom applies a camera's built-in lens data to Nikon Z RAWs;
        // moiré reduction keeps the decoder default.
        let detail = state.detail(isRAW: true)
        if filter.isSharpnessSupported { filter.sharpnessAmount = Float(detail.sharpness / 40) }
        if filter.isDetailSupported { filter.detailAmount = 0 }
        if filter.isLuminanceNoiseReductionSupported { filter.luminanceNoiseReductionAmount = Float(detail.luminanceNoise / 100) }
        if filter.isColorNoiseReductionSupported { filter.colorNoiseReductionAmount = Float(min(1, detail.colorNoise / 50)) }
        if filter.isLensCorrectionSupported { filter.isLensCorrectionEnabled = true }
        let neutral = RAWNeutral(state.whiteBalance, asShotTemperature: Double(filter.neutralTemperature),
                                 asShotTint: Double(filter.neutralTint))
        filter.neutralTemperature = Float(neutral.temperature)
        filter.neutralTint = Float(neutral.tint)
        try Task.checkCancellation()
        guard let output = filter.outputImage else { throw DevelopError.unsupportedRAW(url) }
        let extent = output.extent
        guard extent.width.isFinite, extent.height.isFinite, extent.width > 0, extent.height > 0 else { throw DevelopError.unsupportedRAW(url) }
        // scaleFactor is Float and may yield a fractional or slightly oversized
        // extent. Round the requested pixel grid instead of ceil-padding an
        // extra row/column, so RAW and raster exports obey the same size rule.
        let rotated = (5...8).contains(filter.orientation.rawValue)
        let nativeGrid = rotated ? CGSize(width: native.height, height: native.width) : native
        let grid = longEdge != nil && nativeGrid.width > 0 && nativeGrid.height > 0 ? nativeGrid : extent.size
        let scale: Double
        if let longEdge { scale = min(1.0, Double(longEdge) / max(Double(grid.width), Double(grid.height))) }
        else { scale = 1.0 }
        let width = max(1, Int((Double(grid.width) * scale).rounded()))
        let height = max(1, Int((Double(grid.height) * scale).rounded()))
        let normalized = output.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: Double(width) / extent.width, y: Double(height) / extent.height))
        guard let image = context.createCGImage(normalized, from: CGRect(x: 0, y: 0, width: width, height: height),
                                               format: .RGBAh, colorSpace: workingSpace, deferred: false)
        else { throw DevelopError.unsupportedRAW(url) }
        try Task.checkCancellation()
        return DevelopImage(image: image, isRAW: true, nativeSize: native, neutral: neutral)
    }
}
