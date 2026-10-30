//
//  MetadataService.swift
//  rawpreview
//

import Foundation
import ImageIO
import Synchronization

/// A titled group of metadata rows for the loupe's EXIF sidebar.
nonisolated struct MetadataSection: Identifiable, Hashable, Sendable {
    struct Row: Hashable, Sendable {
        let label: String
        let value: String
    }

    let title: String
    let rows: [Row]
    var id: String { title }
}

/// Reads EXIF/TIFF properties without decoding any pixels. Results are tiny,
/// so every file read once stays cached for the session.
nonisolated final class MetadataService: Sendable {
    static let shared = MetadataService()

    private let cache = Mutex<[URL: ExifInfo]>([:])

    func cachedExif(for url: URL) -> ExifInfo? {
        cache.withLock { $0[url] }
    }

    func exif(for url: URL) async -> ExifInfo? {
        if let hit = cachedExif(for: url) { return hit }
        guard let info = await Self.readExif(url) else { return nil }
        cache.withLock { $0[url] = info }
        return info
    }

    /// Every property ImageIO exposes, grouped by dictionary, for the detail sidebar.
    @concurrent
    func detailedMetadata(for url: URL) async -> [MetadataSection] {
        guard let properties = Self.properties(of: url) else { return [] }

        var sections: [MetadataSection] = []
        var general: [MetadataSection.Row] = []
        for (key, value) in properties {
            if let dictionary = value as? [String: Any] {
                let rows = dictionary
                    .map { MetadataSection.Row(label: Self.humanize($0.key), value: Self.describe($0.value)) }
                    .sorted { $0.label < $1.label }
                if !rows.isEmpty {
                    sections.append(MetadataSection(title: Self.sectionTitle(key), rows: rows))
                }
            } else {
                general.append(MetadataSection.Row(label: Self.humanize(key), value: Self.describe(value)))
            }
        }
        sections.sort { Self.sectionOrder($0.title) < Self.sectionOrder($1.title) }
        if !general.isEmpty {
            sections.insert(MetadataSection(title: "Image", rows: general.sorted { $0.label < $1.label }), at: 0)
        }
        return sections
    }

    func removeAll() {
        cache.withLock { $0.removeAll() }
    }

    // MARK: - Reading

    private static func properties(of url: URL) -> [String: Any]? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [String: Any]
    }

    @concurrent
    private static func readExif(_ url: URL) async -> ExifInfo? {
        guard MediaKind(fileExtension: url.pathExtension).isImage,
              let props = properties(of: url)
        else { return nil }

        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let aux = props[kCGImagePropertyExifAuxDictionary as String] as? [String: Any] ?? [:]

        var info = ExifInfo()
        info.cameraMake = (tiff[kCGImagePropertyTIFFMake as String] as? String)?.trimmed
        info.cameraModel = (tiff[kCGImagePropertyTIFFModel as String] as? String)?.trimmed
        info.lensModel = ((exif[kCGImagePropertyExifLensModel as String] ?? aux[kCGImagePropertyExifAuxLensModel as String]) as? String)?.trimmed
        info.captureDate = (exif[kCGImagePropertyExifDateTimeOriginal as String] as? String).flatMap(parseExifDate)

        info.fNumber = exif[kCGImagePropertyExifFNumber as String] as? Double
        info.exposureTime = exif[kCGImagePropertyExifExposureTime as String] as? Double
        info.iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int])?.first
        info.focalLength = exif[kCGImagePropertyExifFocalLength as String] as? Double
        info.exposureBias = exif[kCGImagePropertyExifExposureBiasValue as String] as? Double

        info.pixelWidth = props[kCGImagePropertyPixelWidth as String] as? Int
        info.pixelHeight = props[kCGImagePropertyPixelHeight as String] as? Int
        info.orientation = props[kCGImagePropertyOrientation as String] as? Int
        return info
    }

    /// EXIF dates are `"yyyy:MM:dd HH:mm:ss"` in the camera's local time.
    private static func parseExifDate(_ string: String) -> Date? {
        let parts = string.split(whereSeparator: { $0 == ":" || $0 == " " }).compactMap { Int($0) }
        guard parts.count >= 6 else { return nil }
        let components = DateComponents(
            year: parts[0], month: parts[1], day: parts[2],
            hour: parts[3], minute: parts[4], second: parts[5]
        )
        return Calendar.current.date(from: components)
    }

    // MARK: - Formatting for the sidebar

    private static func sectionTitle(_ key: String) -> String {
        key.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
    }

    private static func sectionOrder(_ title: String) -> Int {
        ["Exif", "TIFF", "ExifAux", "GPS", "IPTC"].firstIndex(of: title) ?? 99
    }

    /// `"ExposureBiasValue"` → `"Exposure Bias Value"`.
    private static func humanize(_ key: String) -> String {
        var result = ""
        var previous: Character?
        for char in key {
            if let previous, char.isUppercase, previous.isLowercase || previous.isNumber {
                result.append(" ")
            }
            result.append(char)
            previous = char
        }
        return result
    }

    private static func describe(_ value: Any) -> String {
        switch value {
        case let array as [Any]:
            array.map(describe).joined(separator: ", ")
        case let number as NSNumber:
            number.stringValue
        case let string as String:
            string.trimmed
        default:
            String(describing: value)
        }
    }
}

nonisolated private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)) }
}
