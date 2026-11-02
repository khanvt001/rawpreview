//
//  DevelopPreset.swift
//  rawpreview
//

import Foundation

/// A Lightroom develop preset (`.lrtemplate` or `.xmp`), turned into a
/// `PresetLook` the preview can apply.
///
/// This is an approximation of Lightroom's rendering, not a reproduction:
/// Camera Raw uses Adobe's camera profiles and process algorithms, while
/// our creative look follows the selected ImageIO/Apple RAW decode. Settings we can't imitate
/// at all (Calibration, unusual profiles) are listed in
/// `unsupportedSettings` instead of being faked.
nonisolated struct DevelopPreset: Identifiable, Sendable {
    /// File name inside the presets folder, or `builtin/<category>/<name>`.
    let id: String
    let title: String
    /// One-line description, for built-in presets.
    let summary: String?
    /// The preset file's settings, kept so Edit adjustments can be added on top.
    let settings: [String: PresetValue]
    let look: PresetLook
    /// Human-readable names of the adjustments this preset makes that the
    /// preview leaves out, e.g. `["Calibration"]`.
    let unsupportedSettings: [String]
    let compatibility: PresetCompatibility
    var processVersion: String? { settings["ProcessVersion"]?.string ?? settings["ProcessVersion"]?.number.map { String($0) } }
    var profileReference: PresetProfileReference { PresetProfileReference(settings: settings) }
    /// UI/store revision. Render and LUT caches use effective content keys.
    private(set) var revision = UUID()
    /// 0…1 strength. DevelopState resolves effective parameters for production;
    /// the legacy `apply` method retains phase 1's image-mixing comparison.
    private(set) var amount = 1.0
    /// Legacy post-look adjustments, for phase 1 comparisons. Production Light
    /// deltas are stored separately and resolved by DevelopState.
    private(set) var adjustments: PresetLook?

    enum LoadError: LocalizedError {
        case unreadable(String)
        case notADevelopPreset(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): String(localized: "\(name) isn't a Lightroom preset this app can read.")
            case .notADevelopPreset(let name): String(localized: "\(name) isn't a Develop preset.")
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
        let normalized = PresetNormalization.normalize(settings)
        self.settings = normalized
        look = PresetLook(settings: normalized)
        compatibility = PresetCompatibility(settings: normalized)
        unsupportedSettings = compatibility.labels(for: .unsupported)
    }

    /// This preset applied at `amount` (0…1), with a new UI/store revision.
    func atAmount(_ amount: Double) -> DevelopPreset {
        var preset = self
        preset.amount = amount.isFinite ? min(max(amount, 0), 1) : 0
        preset.revision = UUID()
        return preset
    }

    /// Legacy comparison helper: `preset` followed by `light`, as one preset the
    /// renderer can apply; `light` alone when there is no preset. The edits
    /// come after the preset rather than being added to its settings, so the
    /// preset's Amount doesn't scale them too.
    static func combining(_ preset: DevelopPreset?, with light: LightAdjustments) -> DevelopPreset? {
        guard !light.isZero else { return preset }
        var settings: [String: PresetValue] = [:]
        for slider in LightAdjustments.Slider.allCases where light[slider] != 0 {
            settings[slider.settingsKey] = .number(light[slider])
        }
        guard var combined = preset else {
            return DevelopPreset(id: "edit", title: "Edit", settings: settings)
        }
        combined.adjustments = PresetLook(settings: settings)
        combined.revision = UUID()
        return combined
    }

    var isMonochrome: Bool {
        look.isMonochrome
    }

    /// Nothing to apply: rendering can be skipped.
    var isNoOp: Bool {
        (amount == 0 || look.isIdentity) && (adjustments?.isIdentity ?? true)
    }

    struct ColorKey: Hashable, Sendable {
        let look: PresetLook
        let amount: Double
        let adjustments: PresetLook?
        let appliesLook: Bool
    }

    /// Content, not revision/UUID: equivalent imports, amounts and edits share
    /// the same table. Amount and edits retain phase 1's existing semantics.
    var colorKey: ColorKey {
        ColorKey(look: look.colorKey, amount: amount, adjustments: adjustments?.colorKey, appliesLook: amount > 0 && !look.isIdentity)
    }

    struct RenderKey: Hashable, Sendable {
        let color: ColorKey
        let clarity: Double
        let texture: Double
        let dehaze: Double
        let vignette: PresetLook.Vignette?
        let grain: PresetLook.Grain?
    }

    var renderKey: RenderKey {
        RenderKey(color: colorKey, clarity: clarity, texture: texture, dehaze: dehaze, vignette: vignette, grain: grain)
    }

    // MARK: - Rendering

    /// One colour through the preset at `amount`, then the edits: what the
    /// renderer's lookup table holds.
    func apply(_ color: SIMD3<Double>) -> SIMD3<Double> {
        var result = color
        if amount > 0, !look.isIdentity {
            let full = look.apply(color)
            result = amount >= 1 ? full : color + (full - color) * amount
        }
        return adjustments?.apply(result) ?? result
    }

    /// RGBA float cube of `apply` for `CIColorCubeWithColorSpace`.
    func cubeData(dimension: Int) -> Data {
        PresetLook.cubeData(dimension: dimension, apply)
    }

    /// The preset's local contrast, vignette and grain, scaled by `amount`.
    var clarity: Double { look.clarity * amount }
    var texture: Double { look.texture * amount }
    var dehaze: Double { look.dehaze * amount }

    var vignette: PresetLook.Vignette? {
        guard amount > 0, let vignette = look.vignette else { return nil }
        return PresetLook.Vignette(amount: vignette.amount * amount, midpoint: vignette.midpoint, feather: vignette.feather,
                                   roundness: vignette.roundness, style: vignette.style, highlightContrast: vignette.highlightContrast)
    }

    var grain: PresetLook.Grain? {
        guard amount > 0, let grain = look.grain else { return nil }
        return PresetLook.Grain(amount: grain.amount * amount, size: grain.size, roughness: grain.roughness)
    }

    /// "Kodak Gold", or "Kodak Gold 50%" below full strength.
    var titleWithAmount: String {
        amount < 1 ? "\(title) \(Int((amount * 100).rounded()))%" : title
    }

    /// Lightroom's built-in presets use `$$$/Key=Default text`.
    private static func localizedTitle(_ title: String) -> String {
        guard title.hasPrefix("$$$/"), let equals = title.firstIndex(of: "=") else { return title }
        return String(title[title.index(after: equals)...])
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
            settings[key] = PresetValue(lua: value)
        }
        return (root["title"]?.string, settings)
    }

    private static let crsNamespace = "http://ns.adobe.com/camera-raw-settings/1.0/"
    private static let rdfNamespace = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

    /// Lightroom 7.3+ presets: `crs:` attributes on an `rdf:Description`,
    /// curves as `rdf:Seq` lists of `"x, y"` items.
    private static func parseXMP(_ url: URL, name: String) throws -> (String?, [String: PresetValue]) {
        guard let document = try? XMLDocument(contentsOf: url, options: [.nodeLoadExternalEntitiesNever]),
              let description = descriptions(in: document.rootElement()).first(where: hasCameraRawSettings)
        else { throw LoadError.unreadable(name) }

        var settings: [String: PresetValue] = [:]
        var title: String?
        for attribute in description.attributes ?? [] where attribute.uri == crsNamespace {
            guard let key = attribute.localName, let text = attribute.stringValue else { continue }
            settings[key] = scalar(key, text)
        }
        for child in description.children ?? [] {
            guard let element = child as? XMLElement, element.uri == crsNamespace, let key = element.localName else { continue }
            let items = element.elements(forLocalName: "Seq", uri: rdfNamespace).first?.elements(forLocalName: "li", uri: rdfNamespace)
                ?? element.elements(forLocalName: "Alt", uri: rdfNamespace).first?.elements(forLocalName: "li", uri: rdfNamespace)
            if key == "Name" {
                title = (items?.first { $0.attribute(forName: "xml:lang")?.stringValue == "x-default" } ?? items?.first)?.stringValue
            } else if let items, key.hasPrefix("ToneCurve") {
                // "x, y" per item → flat [x0, y0, x1, y1, …] like lrtemplates.
                let components = items.map { ($0.stringValue ?? "").split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) } }
                let values = components.flatMap { $0 }.compactMap { Double($0) }
                if components.allSatisfy({ $0.count == 2 }), values.count == items.count * 2, values.allSatisfy(\.isFinite) {
                    settings[key] = .list(values)
                } else {
                    settings[key] = .array(items.map { .string($0.stringValue ?? "") })
                }
            } else {
                settings[key] = ["ProcessVersion", "Version"].contains(key) ? .string(element.stringValue ?? "") : xmlValue(element)
            }
        }
        if let presetType = settings["PresetType"]?.string, presetType != "Normal" {
            throw LoadError.notADevelopPreset(name)
        }
        // `crs:Name` is usually an `rdf:Alt` element, sometimes an attribute.
        return (title ?? settings["Name"]?.string, settings)
    }

    /// Keep RDF resources/arrays intact, including Look UUID/Amount/Parameters
    /// and unsupported masks. Never substitute a creative Look for CameraProfile.
    private static func xmlValue(_ element: XMLElement) -> PresetValue {
        if let sequence = (element.children ?? []).compactMap({ $0 as? XMLElement }).first(where: {
            $0.uri == rdfNamespace && ["Seq", "Bag", "Alt"].contains($0.localName ?? "")
        }) {
            if sequence.localName == "Alt" {
                let items = sequence.elements(forLocalName: "li", uri: rdfNamespace)
                let preferred = items.filter { $0.attribute(forName: "xml:lang")?.stringValue == "x-default" }
                    + items.filter { $0.attribute(forName: "xml:lang")?.stringValue != "x-default" }
                return .array(preferred.map { .string($0.stringValue ?? "") })
            }
            return PresetValue.sequence(sequence.elements(forLocalName: "li", uri: rdfNamespace).map(xmlValue))
        }
        let resource = element.elements(forLocalName: "Description", uri: rdfNamespace).first ?? element
        var fields: [String: PresetValue] = [:]
        if let reference = resource.attribute(forLocalName: "resource", uri: rdfNamespace)?.stringValue {
            fields["rdf:resource"] = .string(reference)
        }
        for attribute in resource.attributes ?? [] where attribute.uri == crsNamespace {
            if let name = attribute.localName, let text = attribute.stringValue { fields[name] = scalar(name, text) }
        }
        for child in (resource.children ?? []).compactMap({ $0 as? XMLElement }) where child.uri == crsNamespace {
            if let name = child.localName { fields[name] = xmlValue(child) }
        }
        return fields.isEmpty ? scalar(resource.localName ?? "", resource.stringValue ?? "") : .object(fields)
    }

    private static func scalar(_ key: String, _ text: String) -> PresetValue {
        if ["Name", "UUID", "Version", "ProcessVersion", "CameraProfile"].contains(key) || key.hasSuffix("Digest") {
            return .string(text)
        }
        return PresetValue(xmpText: text)
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
nonisolated enum PresetValue: Sendable, Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    /// Curve points, flattened: `[x0, y0, x1, y1, …]` on a 0–255 scale.
    case list([Double])
    indirect case object([String: PresetValue])
    indirect case array([PresetValue])

    init?(lua: LuaValue) {
        switch lua {
        case .string(let value): self = .string(value)
        case .number(let value): self = value.isFinite ? .number(value) : .string(String(value))
        case .bool(let value): self = .bool(value)
        case .table(let table):
            if !table.fields.isEmpty {
                var fields = table.fields.compactMapValues { PresetValue(lua: $0) }
                if !table.array.isEmpty { fields["_items"] = Self.sequence(table.array.compactMap { PresetValue(lua: $0) }) }
                self = .object(fields)
            }
            else {
                let values = table.array.compactMap { PresetValue(lua: $0) }
                self = Self.sequence(values)
            }
        case .nil: return nil
        }
    }

    static func sequence(_ values: [PresetValue]) -> PresetValue {
        values.allSatisfy { $0.number != nil } ? .list(values.compactMap(\.number)) : .array(values)
    }

    init(xmpText text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Double(text), number.isFinite {
            self = .number(number)
        } else if text.lowercased() == "true" || text.lowercased() == "false" {
            self = .bool(text.lowercased() == "true")
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
        } else if let object = try? container.decode([String: PresetValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([PresetValue].self) {
            self = .array(array)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .list(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        }
    }

    var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    var number: Double? {
        if case .number(let value) = self, value.isFinite { value } else { nil }
    }

    var list: [Double]? {
        if case .list(let value) = self { value } else { nil }
    }

    var object: [String: PresetValue]? {
        if case .object(let value) = self { value } else { nil }
    }

    var bool: Bool? {
        if case .bool(let value) = self { value } else { nil }
    }

    var isActive: Bool {
        switch self {
        case .number(let value): value != 0
        case .bool(let value): value
        case .string(let value): !value.isEmpty && value != "None" && value != "Off"
        case .list(let value): !value.isEmpty
        case .object(let value): !value.isEmpty
        case .array(let value): !value.isEmpty
        }
    }
}
