import Foundation

/// Reports implementation coverage, never a claim of Adobe pixel equivalence.
nonisolated struct PresetCompatibility: Sendable {
    enum Level: String, Sendable, CaseIterable {
        case supported, approximate, unsupported
    }
    enum Kind: Sendable {
        case capability, invalidData
    }
    struct Entry: Sendable {
        let level: Level
        let label: String
        let keys: [String]
        let kind: Kind
    }
    let entries: [Entry]
    /// Unsupported Adobe features are compatibility information, not proof
    /// that a preset file is broken. Reserve attention badges for invalid data.
    var hasInvalidData: Bool { entries.contains { $0.kind == .invalidData } }

    func labels(for level: Level) -> [String] { entries.filter { $0.level == level }.map(\.label) }
    var details: String {
        entries.map { "\($0.level.rawValue): \($0.label) [\($0.keys.joined(separator: ", "))]" }.joined(separator: "\n")
    }

    init(settings: [String: PresetValue]) {
        var groups: [String: (level: Level, keys: [String], kind: Kind)] = [:]
        func add(_ label: String, _ level: Level, _ key: String, kind: Kind = .capability) {
            var entry = groups[label] ?? (level, [], kind)
            entry.keys.append(key)
            groups[label] = entry
        }
        let metadata: Set<String> = ["UUID", "Name", "Group", "Cluster", "Version", "PresetType", "HasSettings", "Amount",
                                     "SupportsAmount", "SupportsColor", "SupportsMonochrome", "SupportsHighDynamicRange", "SupportsNormalDynamicRange",
                                     "SupportsSceneReferred", "SupportsOutputReferred", "RequiresRenditionBehavior", "CameraModelRestriction", "ToneCurveName", "ToneCurveName2012"]
        let basic: Set<String> = ["Contrast2012", "Highlights2012", "Shadows2012", "Whites2012", "Blacks2012", "Saturation", "Vibrance",
                                  "ConvertToGrayscale", "Treatment", "ParametricShadows", "ParametricDarks", "ParametricLights", "ParametricHighlights",
                                  "ParametricShadowSplit", "ParametricMidtoneSplit", "ParametricHighlightSplit"]
        let calibration: Set<String> = ["RedHue", "RedSaturation", "GreenHue", "GreenSaturation", "BlueHue", "BlueSaturation", "ShadowTint"]
        let spatialSupported: Set<String> = ["Clarity2012", "Texture", "GrainAmount", "GrainSize", "GrainRoughness", "GrainFrequency",
                                             "PostCropVignetteAmount", "PostCropVignetteMidpoint", "PostCropVignetteFeather",
                                             "PostCropVignetteRoundness", "PostCropVignetteStyle", "PostCropVignetteHighlightContrast"]
        // Lens vignetting (Lens Corrections → Manual), not the post-crop effect.
        let optionalSpatial: Set<String> = ["VignetteAmount", "VignetteMidpoint"]
        let noise: Set<String> = ["LuminanceSmoothing", "ColorNoiseReduction", "LuminanceNoiseReductionDetail", "LuminanceNoiseReductionContrast", "ColorNoiseReductionDetail", "ColorNoiseReductionSmoothness"]
        let sharpen: Set<String> = ["Sharpness", "SharpenRadius", "SharpenDetail", "SharpenEdgeMasking"]
        // Lightroom's defaults for the detail controls not applied here: a
        // preset that leaves them alone loses nothing.
        let detailDefaults: [String: Double] = [
            "SharpenRadius": 1, "SharpenDetail": 25, "SharpenEdgeMasking": 0,
            "LuminanceNoiseReductionDetail": 50, "LuminanceNoiseReductionContrast": 0,
            "ColorNoiseReductionDetail": 50, "ColorNoiseReductionSmoothness": 50,
        ]
        func changesDefault(_ key: String, _ value: PresetValue) -> Bool {
            guard let number = value.number, let fallback = detailDefaults[key] else { return value.isActive }
            return abs(number - fallback) > 0.001
        }
        for key in settings.keys.sorted() {
            guard let value = settings[key] else { continue }
            if metadata.contains(key) { continue }
            let numeric = (basic.contains(key) && key != "Treatment" && key != "ConvertToGrayscale") || spatialSupported.contains(key)
                || calibration.contains(key) || noise.contains(key) || sharpen.contains(key) || optionalSpatial.contains(key)
                || key.hasPrefix("ColorGrade") || key.hasPrefix("SplitToning") || key.hasPrefix("HueAdjustment")
                || key.hasPrefix("SaturationAdjustment") || key.hasPrefix("LuminanceAdjustment") || key.hasPrefix("GrayMixer")
                || ["Exposure2012", "Temperature", "Tint", "IncrementalTemperature", "IncrementalTint", "Dehaze"].contains(key)
            if numeric, value.number == nil { add("Invalid values", .unsupported, key, kind: .invalidData); continue }
            if key == "ProcessVersion" {
                add("Process Version (retained only)", .unsupported, key)
            } else if key == "CameraProfile" || key == "CameraProfileDigest" {
                let name = settings["CameraProfile"]?.string ?? "Custom"
                if settings["CameraProfileDigest"]?.isActive == true { add("Camera profile (\(name), custom digest)", .unsupported, key) }
                else if name == "Embedded" { add("Embedded/native profile", .supported, key) }
                else if ["Adobe Vivid", "Adobe Monochrome", "Camera Monochrome"].contains(name) {
                    add("Profile simulation (\(name))", .approximate, key)
                } else { add("Camera profile (\(name))", .unsupported, key) }
            } else if key == "Look", value.isActive {
                add("Creative Look (\(PresetProfileReference(settings: settings).creativeName ?? "custom"))", .unsupported, key)
            } else if key == "Exposure2012" {
                add("Exposure", .supported, key)
            } else if key == "WhiteBalance" || ["Temperature", "Tint", "IncrementalTemperature", "IncrementalTint"].contains(key) {
                if settings["WhiteBalance"]?.string == "Auto" || (key == "WhiteBalance" && value.string != "As Shot" && settings["Temperature"]?.number == nil) {
                    add("White balance preset without neutral values", .unsupported, key)
                } else { add("White balance (native RAW / approximate JPEG)", .approximate, key) }
            } else if key.hasPrefix("ToneCurve") {
                if !key.hasPrefix("ToneCurvePV2012"), value.isActive { add("Legacy tone curve", .unsupported, key) }
                else if let points = value.list, points.count >= 4, points.count.isMultiple(of: 2), points.allSatisfy({ $0.isFinite && (0...255).contains($0) }) {
                    add("Tone curves", .approximate, key)
                } else if value.isActive { add("Invalid curves", .unsupported, key, kind: .invalidData) }
            } else if basic.contains(key) {
                add("Tone / B&W", .approximate, key)
            } else if key.hasPrefix("HueAdjustment") || key.hasPrefix("SaturationAdjustment") || key.hasPrefix("LuminanceAdjustment") || key.hasPrefix("GrayMixer") {
                add("HSL / B&W mix", .approximate, key)
            } else if key.hasPrefix("ColorGrade") || key.hasPrefix("SplitToning") {
                add("Color Grading", .approximate, key)
            } else if spatialSupported.contains(key) {
                add("Spatial effects", .approximate, key)
            } else if calibration.contains(key), value.isActive {
                add("Calibration", .approximate, key)
            } else if key == "LuminanceSmoothing" || key == "ColorNoiseReduction" {
                add("Noise reduction (amounts)", .approximate, key)
            } else if noise.contains(key) {
                if changesDefault(key, value) { add("Noise reduction detail/contrast", .unsupported, key) }
            } else if key == "Sharpness" {
                add("Sharpening (amount)", .approximate, key)
            } else if sharpen.contains(key) {
                if changesDefault(key, value) { add("Sharpening radius/detail/masking", .unsupported, key) }
            } else if optionalSpatial.contains(key), value.isActive {
                add("Lens vignetting (manual lens correction)", .unsupported, key)
            } else if key == "Dehaze", value.isActive {
                add("Dehaze (regional haze estimate)", .approximate, key)
            } else if value.isActive {
                if key.lowercased().contains("mask") || key.contains("Correction") || key.hasPrefix("Local") {
                    add("Masks / local adjustments", .unsupported, key)
                } else if key.hasPrefix("LensProfile") {
                    add("Lens profile (camera's built-in data, RAW only)", .approximate, key)
                } else if key.hasPrefix("Lens") || key.hasPrefix("Defringe") || key.hasPrefix("Perspective") || key == "AutoLateralCA" {
                    add("Lens / geometry", .unsupported, key)
                } else { add("Other unimplemented settings", .unsupported, key) }
            }
        }
        if settings["SupportsAmount"]?.bool == true || settings["Amount"] != nil { add("Amount (parameter scaling)", .approximate, "Amount") }
        entries = groups.keys.sorted().map { Entry(level: groups[$0]!.level, label: $0, keys: groups[$0]!.keys.sorted(), kind: groups[$0]!.kind) }
    }
}
