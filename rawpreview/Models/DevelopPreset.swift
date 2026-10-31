//
//  DevelopPreset.swift
//  rawpreview
//

import Foundation

/// A Lightroom develop preset (`.lrtemplate` or `.xmp`), reduced to what the
/// preview can apply: its tone curves, baked into one lookup table per channel.
///
/// This is an approximation of Lightroom's rendering, not a reproduction:
/// Camera Raw applies curves to raw sensor data in its own working space,
/// while we apply them to the camera's embedded JPEG on screen. For presets
/// built from curves, as most "look" presets are, the result is close.
/// Settings with no per-channel equivalent (exposure, HSL, clarity, white
/// balance…) are listed in `unsupportedSettings` instead of being faked.
nonisolated struct DevelopPreset: Identifiable, Sendable {
    /// File name inside the presets folder.
    let id: String
    let title: String
    let lut: ToneLUT
    /// Black & white: `ConvertToGrayscale` (Treatment: Black & White), or
    /// Saturation at -100. Applied before the curves, as in Lightroom, so
    /// per-channel curves can still tone the result.
    let isMonochrome: Bool
    /// Human-readable names of the adjustments this preset makes that the
    /// preview leaves out, e.g. `["Exposure", "HSL"]`.
    let unsupportedSettings: [String]
    /// Changes every time the file is loaded, so rendered images cached for an
    /// older version of the same file name are never reused.
    let revision = UUID()

    enum LoadError: LocalizedError {
        case unreadable(String)
        case notADevelopPreset(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): "\(name) isn't a Lightroom preset this app can read."
            case .notADevelopPreset(let name): "\(name) isn't a Develop preset."
            }
        }
    }

    static let fileExtensions = ["lrtemplate", "xmp"]

    static func load(from url: URL) throws -> DevelopPreset {
        let name = url.lastPathComponent
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let parsed: (title: String?, settings: [String: PresetValue])
        switch url.pathExtension.lowercased() {
        case "lrtemplate": parsed = try parseLRTemplate(url, name: name)
        case "xmp": parsed = try parseXMP(url, name: name)
        default: throw LoadError.unreadable(name)
        }
        return DevelopPreset(
            id: name,
            title: parsed.title.map(localizedTitle) ?? fallbackTitle,
            settings: parsed.settings
        )
    }

    init(id: String, title: String, settings: [String: PresetValue]) {
        self.id = id
        self.title = title
        lut = ToneLUT(settings: settings)
        isMonochrome = Self.isMonochrome(settings)
        unsupportedSettings = Self.unsupported(in: settings, isMonochrome: isMonochrome)
    }

    /// Nothing to apply: rendering can be skipped.
    var isNoOp: Bool {
        lut.isIdentity && !isMonochrome
    }

    private static func isMonochrome(_ settings: [String: PresetValue]) -> Bool {
        if case .bool(true) = settings["ConvertToGrayscale"] { return true }
        if let saturation = settings["Saturation"]?.number, saturation <= -100 { return true }
        return false
    }

    /// Lightroom's built-in presets use `$$$/Key=Default text`.
    private static func localizedTitle(_ title: String) -> String {
        guard title.hasPrefix("$$$/"), let equals = title.firstIndex(of: "=") else { return title }
        return String(title[title.index(after: equals)...])
    }

    // MARK: - Unsupported settings

    /// Adjustments whose default is 0 and that change the look.
    private static let unsupportedByKey: [String: String] = [
        "Exposure2012": "Exposure", "Contrast2012": "Contrast",
        "Highlights2012": "Highlights", "Shadows2012": "Shadows",
        "Whites2012": "Whites", "Blacks2012": "Blacks",
        "Clarity2012": "Clarity", "Texture": "Texture", "Dehaze": "Dehaze",
        "Vibrance": "Vibrance", "Saturation": "Saturation",
        "IncrementalTemperature": "White Balance", "IncrementalTint": "White Balance",
        "SplitToningShadowSaturation": "Split Toning", "SplitToningHighlightSaturation": "Split Toning",
        "ColorGradeShadowSat": "Color Grading", "ColorGradeMidtoneSat": "Color Grading",
        "ColorGradeHighlightSat": "Color Grading", "ColorGradeGlobalSat": "Color Grading",
        "ColorGradeShadowLum": "Color Grading", "ColorGradeMidtoneLum": "Color Grading",
        "ColorGradeHighlightLum": "Color Grading", "ColorGradeGlobalLum": "Color Grading",
        "RedHue": "Calibration", "RedSaturation": "Calibration",
        "GreenHue": "Calibration", "GreenSaturation": "Calibration",
        "BlueHue": "Calibration", "BlueSaturation": "Calibration", "ShadowTint": "Calibration",
        "PostCropVignetteAmount": "Vignette", "GrainAmount": "Grain",
    ]

    private static let unsupportedPrefixes = [
        "HueAdjustment": "HSL", "SaturationAdjustment": "HSL", "LuminanceAdjustment": "HSL",
        "GrayMixer": "B&W Mix",
    ]

    /// Profiles the camera's embedded JPEG already roughly looks like, plus
    /// the plain monochrome ones, which `isMonochrome` covers.
    private static let embeddedLookProfiles: Set<String> = [
        "Camera Standard", "Embedded", "Adobe Monochrome", "Camera Monochrome",
    ]

    private static func unsupported(in settings: [String: PresetValue], isMonochrome: Bool) -> [String] {
        var labels: [String] = []
        func add(_ label: String) {
            if !labels.contains(label) { labels.append(label) }
        }
        if let profile = settings["CameraProfile"]?.string, !embeddedLookProfiles.contains(profile) {
            add("Profile (\(profile))")
        }
        if let whiteBalance = settings["WhiteBalance"]?.string, whiteBalance != "As Shot" {
            add("White Balance")
        }
        for key in settings.keys.sorted() {
            guard let value = settings[key]?.number, value != 0 else { continue }
            // In black & white, colour-only adjustments have no visible effect
            // beyond the B&W mix (reported separately).
            if isMonochrome, ["Saturation", "Vibrance"].contains(key) || key.hasPrefix("HueAdjustment") || key.hasPrefix("SaturationAdjustment") {
                continue
            }
            // Lightroom only uses the gray mixer in black & white.
            if !isMonochrome, key.hasPrefix("GrayMixer") { continue }
            if let label = unsupportedByKey[key] ?? unsupportedPrefixes.first(where: { key.hasPrefix($0.key) })?.value {
                add(label)
            }
        }
        return labels
    }

    // MARK: - Parsing

    private static func parseLRTemplate(_ url: URL, name: String) throws -> (String?, [String: PresetValue]) {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let root = (try? LuaTableParser.parse(text))?.table
        else { throw LoadError.unreadable(name) }
        if let type = root["type"]?.string, type != "Develop" {
            throw LoadError.notADevelopPreset(name)
        }
        guard let settingsTable = root["value"]?.table?["settings"]?.table else {
            throw LoadError.notADevelopPreset(name)
        }

        var settings: [String: PresetValue] = [:]
        for (key, value) in settingsTable.fields {
            switch value {
            case .string(let string): settings[key] = .string(string)
            case .number(let number): settings[key] = .number(number)
            case .bool(let bool): settings[key] = .bool(bool)
            case .table(let table): settings[key] = .list(table.array.compactMap(\.number))
            case .nil: break
            }
        }
        return (root["title"]?.string, settings)
    }

    private static let crsNamespace = "http://ns.adobe.com/camera-raw-settings/1.0/"
    private static let rdfNamespace = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

    /// Lightroom 7.3+ presets: `crs:` attributes on an `rdf:Description`,
    /// curves as `rdf:Seq` lists of `"x, y"` items.
    private static func parseXMP(_ url: URL, name: String) throws -> (String?, [String: PresetValue]) {
        guard let document = try? XMLDocument(contentsOf: url, options: []),
              let description = descriptions(in: document.rootElement()).first(where: hasCameraRawSettings)
        else { throw LoadError.unreadable(name) }

        var settings: [String: PresetValue] = [:]
        var title: String?
        for attribute in description.attributes ?? [] where attribute.uri == crsNamespace {
            guard let key = attribute.localName, let text = attribute.stringValue else { continue }
            settings[key] = PresetValue(xmpText: text)
        }
        for child in description.children ?? [] {
            guard let element = child as? XMLElement, element.uri == crsNamespace, let key = element.localName else { continue }
            let items = element.elements(forLocalName: "Seq", uri: rdfNamespace).first?.elements(forLocalName: "li", uri: rdfNamespace)
                ?? element.elements(forLocalName: "Alt", uri: rdfNamespace).first?.elements(forLocalName: "li", uri: rdfNamespace)
            if key == "Name" {
                title = items?.first?.stringValue
            } else if let items, key.hasPrefix("ToneCurve") {
                // "x, y" per item → flat [x0, y0, x1, y1, …] like lrtemplates.
                settings[key] = .list(items.flatMap { item in
                    (item.stringValue ?? "").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                })
            } else if let text = items?.first?.stringValue ?? element.stringValue {
                settings[key] = PresetValue(xmpText: text)
            }
        }
        if let presetType = settings["PresetType"]?.string, presetType != "Normal" {
            throw LoadError.notADevelopPreset(name)
        }
        // `crs:Name` is usually an `rdf:Alt` element, sometimes an attribute.
        return (title ?? settings["Name"]?.string, settings)
    }

    private static func descriptions(in element: XMLElement?) -> [XMLElement] {
        guard let element else { return [] }
        let children = (element.children ?? []).compactMap { $0 as? XMLElement }
        let own = element.localName == "Description" && element.uri == rdfNamespace ? [element] : []
        return own + children.flatMap(descriptions)
    }

    private static func hasCameraRawSettings(_ description: XMLElement) -> Bool {
        (description.attributes ?? []).contains { $0.uri == crsNamespace }
            || (description.children ?? []).contains { ($0 as? XMLElement)?.uri == crsNamespace }
    }
}

/// One develop setting, as either preset format stores it.
nonisolated enum PresetValue: Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    /// Curve points, flattened: `[x0, y0, x1, y1, …]` on a 0–255 scale.
    case list([Double])

    init(xmpText text: String) {
        if let number = Double(text) {
            self = .number(number)
        } else if text == "True" || text == "False" {
            self = .bool(text == "True")
        } else {
            self = .string(text)
        }
    }

    var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    var number: Double? {
        if case .number(let value) = self { value } else { nil }
    }

    var list: [Double]? {
        if case .list(let value) = self { value } else { nil }
    }
}
