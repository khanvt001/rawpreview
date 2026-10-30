//
//  ExifInfo.swift
//  rawpreview
//

import Foundation

/// The subset of EXIF / TIFF metadata the UI cares about. Filled by
/// `MetadataService` (Phase 2) from `CGImageSourceCopyPropertiesAtIndex`.
nonisolated struct ExifInfo: Hashable, Sendable {
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var captureDate: Date?

    var fNumber: Double?
    var exposureTime: Double?
    var iso: Int?
    var focalLength: Double?
    var exposureBias: Double?

    var pixelWidth: Int?
    var pixelHeight: Int?
    /// EXIF orientation (1–8).
    var orientation: Int?

    // MARK: Formatted values for overlays

    var apertureText: String? {
        fNumber.map { "ƒ/" + $0.formatted(.number.precision(.fractionLength(0...1))) }
    }

    var shutterText: String? {
        guard let t = exposureTime, t > 0 else { return nil }
        if t >= 1 {
            return t.formatted(.number.precision(.fractionLength(0...1))) + "s"
        }
        return "1/\(Int((1 / t).rounded()))s"
    }

    var isoText: String? { iso.map { "ISO \($0)" } }

    var focalLengthText: String? {
        focalLength.map { $0.formatted(.number.precision(.fractionLength(0))) + "mm" }
    }

    /// Compact "ƒ/2.8 · 1/250s · ISO 400" line for grid thumbnails.
    var summaryLine: String {
        [apertureText, shutterText, isoText].compactMap(\.self).joined(separator: " · ")
    }
}
