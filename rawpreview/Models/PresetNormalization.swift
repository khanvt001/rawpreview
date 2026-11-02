import Foundation

nonisolated enum PresetNormalization {
    /// Resolve each grading component independently. Modern midtones/global
    /// frequently coexist with SplitToning shadow/highlight fields in XMP.
    static func normalize(_ input: [String: PresetValue]) -> [String: PresetValue] {
        var settings = input
        let aliases = [
            "ColorGradeShadowHue": "SplitToningShadowHue",
            "ColorGradeShadowSat": "SplitToningShadowSaturation",
            "ColorGradeHighlightHue": "SplitToningHighlightHue",
            "ColorGradeHighlightSat": "SplitToningHighlightSaturation",
            "ColorGradeBalance": "SplitToningBalance",
        ]
        for (canonical, legacy) in aliases where settings[canonical] == nil { settings[canonical] = settings[legacy] }
        let treatment = settings["Treatment"]?.string?.lowercased() ?? ""
        let profile = PresetProfileReference(settings: settings)
        if ["black & white", "black and white", "b&w", "monochrome"].contains(treatment)
            || profile.cameraName?.lowercased().contains("monochrome") == true
            || profile.creativeName?.lowercased().contains("monochrome") == true {
            settings["ConvertToGrayscale"] = .bool(true)
        }
        return settings
    }
}

nonisolated struct PresetProfileReference: Sendable, Hashable {
    let cameraName: String?
    let cameraDigest: String?
    let creativeLook: PresetValue?

    init(settings: [String: PresetValue]) {
        cameraName = settings["CameraProfile"]?.string
        cameraDigest = settings["CameraProfileDigest"]?.string
        creativeLook = settings["Look"]
    }

    var creativeName: String? {
        let name = creativeLook?.object?["Name"]
        if let text = name?.string { return text }
        if case .array(let alternatives) = name { return alternatives.compactMap(\.string).first }
        return nil
    }
    var creativeUUID: String? { creativeLook?.object?["UUID"]?.string }
}
