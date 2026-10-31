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
    /// - Parameters:
    ///   - maxPixelSize: Longest side of the result; `nil` for the image's full
    ///     pixel dimensions (100% zoom).
    ///   - forDisplay: Convert to the current screen's colour space so drawing
    ///     it costs the main thread nothing (see `DisplayColorSpace`). Pass
    ///     `false` for images that are written to files.
    static func decode(_ url: URL, maxPixelSize: Int?, forDisplay: Bool = true) -> CGImage? {
        guard let image = decodeOriginal(url, maxPixelSize: maxPixelSize) else { return nil }
        return forDisplay ? prepareForDisplay(image) : image
    }

    /// The tiny preview a camera embeds in a JPEG/HEIF's EXIF (Nikon: 160×120),
    /// read from the file header without touching the image data: ~20 ms even
    /// from a slow card, against ~90 ms to read a whole 8 MB JPEG. Blurry at
    /// grid size, so it only stands in until `decode` finishes. `nil` for RAW
    /// files (ImageIO would hand back their large preview, which is no faster)
    /// and for files without one.
    static func embeddedThumbnail(_ url: URL) -> CGImage? {
        guard MediaKind(fileExtension: url.pathExtension) != .raw else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        // Neither `FromImage…` flag: ImageIO returns the embedded thumbnail or
        // nothing. A max size is still required, or it returns the full image.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let cropped = cropLetterbox(thumbnail, toAspectOf: source) ?? thumbnail
        return prepareForDisplay(cropped)
    }

    /// EXIF thumbnails are always 4:3, so cameras pad 3:2 photos with black
    /// bars. Center-crops them away so the tile doesn't jump when the real
    /// thumbnail replaces this one.
    private static func cropLetterbox(_ thumbnail: CGImage, toAspectOf source: CGImageSource) -> CGImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = properties[kCGImagePropertyPixelWidth] as? Int,
              var height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        // Orientations 5–8 rotate by 90°; the thumbnail already has that baked in.
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, (5...8).contains(orientation) {
            swap(&width, &height)
        }

        let sourceAspect = Double(width) / Double(height)
        let thumbWidth = Double(thumbnail.width), thumbHeight = Double(thumbnail.height)
        // Rounds inward: a leftover row of a bar shows, a lost row of photo doesn't.
        var rect = CGRect(x: 0, y: 0, width: thumbWidth, height: thumbHeight)
        if thumbWidth / thumbHeight < sourceAspect {
            rect.size.height = (thumbWidth / sourceAspect).rounded(.down)
            rect.origin.y = ((thumbHeight - rect.height) / 2).rounded(.up)
        } else {
            rect.size.width = (thumbHeight * sourceAspect).rounded(.down)
            rect.origin.x = ((thumbWidth - rect.width) / 2).rounded(.up)
        }
        return thumbnail.cropping(to: rect)
    }

    /// Redraws `image` in the screen's colour space with the 32-bit BGRA layout
    /// Core Animation uses natively, so it is uploaded as-is instead of being
    /// colour-matched on the main thread when it first appears (measured ~80 ms
    /// → <1 ms for a 20 MP photo on an external monitor).
    static func prepareForDisplay(_ image: CGImage) -> CGImage {
        guard !Task.isCancelled,
              let context = CGContext(
                  data: nil,
                  width: image.width,
                  height: image.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: DisplayColorSpace.target,
                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return image }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }

    private static func decodeOriginal(_ url: URL, maxPixelSize: Int?) -> CGImage? {
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
