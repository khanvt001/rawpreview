//
//  DevelopPreset.swift
//  rawpreview
//

import Foundation

/// A Lightroom develop preset (`.lrtemplate` or `.xmp`), turned into a
/// `PresetLook` the preview can apply.
///
/// This is an approximation of Lightroom's rendering, not a reproduction:
/// Camera Raw works on raw sensor data in its own colour space, while we
/// start from the camera's embedded JPEG. Settings the preview can't imitate
/// at all (Calibration, unusual profiles) are listed in
/// `unsupportedSettings` instead of being faked.
nonisolated struct DevelopPreset: Identifiable, Sendable {
    /// File name inside the presets folder, or `builtin/<category>/<name>`.
    let id: String
    let title: String
    /// One-line description, for built-in presets.
    let summary: String?
    let look: PresetLook
    /// Human-readable names of the adjustments this preset makes that the
    /// preview leaves out, e.g. `["Calibration"]`.
    let unsupportedSettings: [String]
    /// Changes every time the preset is loaded, so rendered images cached for
    /// an older version of the same file name are never reused.
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

    init(id: String, title: String, summary: String? = nil, settings: [String: PresetValue]) {
        self.id = id
        self.title = title
        self.summary = summary
        look = PresetLook(settings: settings)
        unsupportedSettings = Self.unsupported(in: settings)
    }

    var isMonochrome: Bool {
        look.isMonochrome
    }

    /// Nothing to apply: rendering can be skipped.
    var isNoOp: Bool {
        look.isIdentity
    }

    /// Lightroom's built-in presets use `$$$/Key=Default text`.
    private static func localizedTitle(_ title: String) -> String {
        guard title.hasPrefix("$$$/"), let equals = title.firstIndex(of: "=") else { return title }
        return String(title[title.index(after: equals)...])
    }

    // MARK: - Unsupported settings

    /// Adjustments whose default is 0 that `PresetLook` doesn't imitate.
    private static let unsupportedByKey: [String: String] = [
        "RedHue": "Calibration", "RedSaturation": "Calibration",
        "GreenHue": "Calibration", "GreenSaturation": "Calibration",
        "BlueHue": "Calibration", "BlueSaturation": "Calibration", "ShadowTint": "Calibration",
    ]

    /// Profiles the camera's embedded JPEG already roughly looks like, plus
    /// the ones `PresetLook` imitates.
    private static let supportedProfiles: Set<String> = [
        "Camera Standard", "Embedded", "Adobe Standard", "Adobe Color", "Adobe Vivid",
        "Adobe Monochrome", "Camera Monochrome",
    ]

    private static func unsupported(in settings: [String: PresetValue]) -> [String] {
        var labels: [String] = []
        func add(_ label: String) {
            if !labels.contains(label) { labels.append(label) }
        }
        if let profile = settings["CameraProfile"]?.string, !supportedProfiles.contains(profile) {
            add("Profile (\(profile))")
        }
        for key in settings.keys.sorted() {
            guard let value = settings[key]?.number, value != 0, let label = unsupportedByKey[key] else { continue }
            add(label)
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
            } else if key == "Look" {
                // Lightroom 7.3+ names the profile in a nested description.
                let look = element.elements(forLocalName: "Description", uri: rdfNamespace).first
                if settings["CameraProfile"] == nil,
                   let profile = look?.attribute(forLocalName: "Name", uri: crsNamespace)?.stringValue {
                    settings["CameraProfile"] = .string(profile)
                }
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

/// One develop setting, as either preset format (or the built-in preset
/// file, as plain JSON values) stores it.
nonisolated enum PresetValue: Sendable, Decodable {
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

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let list = try? container.decode([Double].self) {
            self = .list(list)
        } else {
            self = .string(try container.decode(String.self))
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
