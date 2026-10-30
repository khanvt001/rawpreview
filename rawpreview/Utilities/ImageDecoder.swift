//
//  ImageDecoder.swift
//  rawpreview
//

import CoreGraphics
import Foundation
import ImageIO

/// The one place that turns a file into pixels. Synchronous: callers run it on
/// background tasks.
///
/// Measured on Nikon Z 50 NEFs (5568×3712, Apple silicon):
///
/// | Option                                   | 512 px  | Full size |
/// |------------------------------------------|---------|-----------|
/// | `FromImageIfAbsent` (embedded preview)   | ~23 ms  | ~88 ms    |
/// | `FromImageAlways` (RAW engine)           | ~73 ms  | ~105 ms   |
///
/// …and `FromImageAlways` pays a ~6 s RAW-engine warm-up on first use. So for
/// RAW files we take the camera's embedded JPEG preview, and only fall back to
/// decoding the image itself when that preview is too small (e.g. some Sony
/// ARWs embed 1616 px). For JPEG/HEIF the embedded EXIF thumbnail is a useless
/// 160×120, so those go straight to decoding the image (≈40 ms for 512 px).
nonisolated enum ImageDecoder {
    /// - Parameter maxPixelSize: Longest side of the result; `nil` for the image's
    ///   full pixel dimensions (100% zoom).
    static func decode(_ url: URL, maxPixelSize: Int?) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        let sourceSize = longestSide(of: source)
        let target = [maxPixelSize, sourceSize].compactMap(\.self).min()

        if MediaKind(fileExtension: url.pathExtension) == .raw {
            let embedded = thumbnail(from: source, maxPixelSize: maxPixelSize, decodeFullImage: false)
            if let embedded, isLargeEnough(embedded, target: target) {
                return embedded
            }
        }

        guard !Task.isCancelled else { return nil }
        return thumbnail(from: source, maxPixelSize: target, decodeFullImage: true)
    }

    private static func thumbnail(from source: CGImageSource, maxPixelSize: Int?, decodeFullImage: Bool) -> CGImage? {
        var options: [CFString: Any] = [
            decodeFullImage
                ? kCGImageSourceCreateThumbnailFromImageAlways
                : kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            // Bake in EXIF orientation so portrait shots come out upright.
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Decode now, on this background thread, not lazily at first draw on main.
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let maxPixelSize {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func longestSide(of source: CGImageSource) -> Int? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return max(width, height)
    }

    /// Allows a little slack: embedded previews are sometimes a few pixels
    /// smaller than the sensor's active area.
    private static func isLargeEnough(_ image: CGImage, target: Int?) -> Bool {
        guard let target else { return true }
        return Double(max(image.width, image.height)) >= Double(target) * 0.9
    }
}
