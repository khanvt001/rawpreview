//
//  ExifInfo.swift
//  rawpreview
//

import CoreGraphics
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

    /// Photographic notation is always "f/4.5", never the locale's "f/4,5".
    private static let numberLocale = Locale(identifier: "en_US_POSIX")

    var apertureText: String? {
        fNumber.map { "ƒ/" + $0.formatted(.number.precision(.fractionLength(0...1)).locale(Self.numberLocale)) }
    }

    var shutterText: String? {
        guard let t = exposureTime, t > 0 else { return nil }
        if t >= 1 {
            return t.formatted(.number.precision(.fractionLength(0...1)).locale(Self.numberLocale)) + "s"
        }
        return "1/\(Int((1 / t).rounded()))s"
    }

    var isoText: String? { iso.map { "ISO \($0)" } }

    var exposureBiasText: String? {
        guard let bias = exposureBias else { return nil }
        let value = bias.formatted(.number.precision(.fractionLength(0...1)).sign(strategy: .always(includingZero: false)).locale(Self.numberLocale))
        return value + " EV"
    }

    /// Pixel size as displayed, i.e. with EXIF orientation applied
    /// (orientations 5–8 rotate by 90°, swapping width and height).
    var orientedPixelSize: CGSize? {
        guard let pixelWidth, let pixelHeight else { return nil }
        let isRotated = (5...8).contains(orientation ?? 1)
        return isRotated
            ? CGSize(width: pixelHeight, height: pixelWidth)
            : CGSize(width: pixelWidth, height: pixelHeight)
    }

    var focalLengthText: String? {
        focalLength.map { $0.formatted(.number.precision(.fractionLength(0)).locale(Self.numberLocale)) + "mm" }
    }

    /// Compact "ƒ/2.8 · 1/250s · ISO 400" line for grid thumbnails.
    var summaryLine: String {
        [apertureText, shutterText, isoText].compactMap(\.self).joined(separator: " · ")
    }
}
