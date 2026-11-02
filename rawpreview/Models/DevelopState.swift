import Foundation

/// Phase 2's single develop state. Light sliders are deltas relative to the
/// preset; Amount interpolates supported parameters, not two clipped images.
/// This is an approximation and does not implement Adobe's Amount semantics.
nonisolated struct DevelopState: Sendable {
    let processing: ProcessingConfiguration
    let settings: [String: PresetValue]
    let effectivePreset: DevelopPreset?
    let profile: String?
    let processVersion: String?
    let whiteBalanceAmount: Double
    /// The preset's Amount, for parameters interpolated from a non-zero default.
    let amount: Double
    static let pipelineVersion = 4

    init(processing: ProcessingConfiguration, preset: DevelopPreset?, light: LightAdjustments = LightAdjustments()) {
        self.processing = processing
        whiteBalanceAmount = preset?.amount ?? 1
        amount = preset?.amount ?? 1
        var parameters: [String: PresetValue] = [:]
        if let preset, preset.amount > 0 {
            parameters = preset.settings
            let amount = preset.amount
            for (key, value) in preset.settings {
                if let points = value.list, key.hasPrefix("ToneCurve") {
                    parameters[key] = .list(points.enumerated().map { index, y in
                        index.isMultiple(of: 2) ? y : points[index - 1] + (y - points[index - 1]) * amount
                    })
                } else if let number = value.number, !Self.unscaled.contains(key) {
                    parameters[key] = .number(number * amount)
                }
            }
        }
        for slider in LightAdjustments.Slider.allCases {
            let combined = (parameters[slider.settingsKey]?.number ?? 0) + light[slider]
            let bound = slider == .exposure ? 16.0 : 100.0
            let value = min(bound, max(-bound, combined))
            if parameters[slider.settingsKey] != nil || value != 0 { parameters[slider.settingsKey] = .number(value) }
        }
        settings = parameters
        profile = parameters["CameraProfile"]?.string
        processVersion = parameters["ProcessVersion"]?.string
            ?? parameters["ProcessVersion"]?.number.map { String($0) }
        effectivePreset = parameters.isEmpty ? nil : DevelopPreset(id: "effective", title: "Develop", settings: parameters)
    }

    // Coordinates, absolute WB and shape parameters have non-zero defaults.
    private static let unscaled: Set<String> = [
        "Temperature", "Tint", "ProcessVersion", "ParametricShadowSplit", "ParametricMidtoneSplit", "ParametricHighlightSplit",
        "PostCropVignetteMidpoint", "PostCropVignetteFeather", "PostCropVignetteRoundness", "PostCropVignetteStyle",
        "PostCropVignetteHighlightContrast", "GrainSize", "GrainFrequency", "GrainRoughness",
        "ColorGradeShadowHue", "ColorGradeMidtoneHue", "ColorGradeHighlightHue", "ColorGradeGlobalHue",
        "SplitToningShadowHue", "SplitToningHighlightHue", "ColorGradeBlending",
        // Detail: interpolated from Lightroom's defaults in `detail(isRAW:)`.
        "Sharpness", "LuminanceSmoothing", "ColorNoiseReduction",
    ]

    /// Sharpening and noise reduction, in Lightroom's units (Sharpness 0…150,
    /// the others 0…100). A RAW starts from Lightroom's RAW defaults, a
    /// processed image from none; Amount moves from there towards the preset.
    struct Detail: Hashable, Sendable {
        let sharpness: Double
        let luminanceNoise: Double
        let colorNoise: Double
    }

    func detail(isRAW: Bool) -> Detail {
        func value(_ key: String, default rawDefault: Double, range: ClosedRange<Double>) -> Double {
            let base = isRAW ? rawDefault : 0
            let target = settings[key]?.number ?? base
            return min(range.upperBound, max(range.lowerBound, base + (target - base) * amount))
        }
        return Detail(
            sharpness: value("Sharpness", default: 40, range: 0...150),
            luminanceNoise: value("LuminanceSmoothing", default: 0, range: 0...100),
            colorNoise: value("ColorNoiseReduction", default: 25, range: 0...100)
        )
    }

    struct WhiteBalance: Hashable, Sendable {
        let temperature: Double?
        let tint: Double?
        let incrementalTemperature: Double
        let incrementalTint: Double
        let amount: Double
    }

    var whiteBalance: WhiteBalance {
        let absolute = settings["WhiteBalance"]?.string.map { $0 != "As Shot" } ?? false
        let temperature = absolute ? settings["Temperature"]?.number : nil
        let tint = absolute ? settings["Tint"]?.number : nil
        return WhiteBalance(
            temperature: temperature,
            tint: tint,
            incrementalTemperature: settings["IncrementalTemperature"]?.number ?? 0,
            incrementalTint: settings["IncrementalTint"]?.number ?? 0,
            amount: temperature == nil && tint == nil ? 1 : whiteBalanceAmount
        )
    }

    /// Exposure and JPEG WB run in linear light ahead of the bounded creative
    /// LUT. RAW WB is applied by the decoder, using its as-shot neutral.
    var colorPreset: DevelopPreset? {
        var color = settings
        color["Exposure2012"] = nil
        for key in ["WhiteBalance", "Temperature", "Tint", "IncrementalTemperature", "IncrementalTint"] { color[key] = nil }
        for key in color.keys where key == "Clarity2012" || key == "Texture" || key.hasPrefix("Grain") || key.hasPrefix("PostCropVignette") {
            color[key] = nil
        }
        return color.isEmpty ? nil : DevelopPreset(id: "color", title: "Color", settings: color)
    }

    func linearGain(isRAW: Bool) -> SIMD3<Double> {
        var linear: [String: PresetValue] = [:]
        if !isRAW {
            for key in ["WhiteBalance", "Temperature", "Tint"] { linear[key] = settings[key] }
        }
        let wb = PresetLook(settings: linear).linearGain
        let strength = SIMD3(pow(wb.x, whiteBalanceAmount), pow(wb.y, whiteBalanceAmount), pow(wb.z, whiteBalanceAmount))
        var incremental: [String: PresetValue] = [:]
        if !isRAW {
            for key in ["IncrementalTemperature", "IncrementalTint"] { incremental[key] = settings[key] }
        }
        return strength * PresetLook(settings: incremental).linearGain * pow(2, settings["Exposure2012"]?.number ?? 0)
    }
}
