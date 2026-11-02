//
//  ImageWriter.swift
//  rawpreview
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes a decoded (already upright) image as a JPEG, HEIF or PNG carrying
/// the original file's camera metadata.
nonisolated enum ImageWriter {
    enum WriteError: LocalizedError {
        case failed(String, UTType)

        var errorDescription: String? {
            switch self {
            case let .failed(name, type):
                String(localized: "Couldn't create a \(type.preferredFilenameExtension?.uppercased() ?? "file") for \(name).")
            }
        }
    }

    /// - Parameters:
    ///   - type: `.jpeg`, `.heic` or `.png`.
    ///   - quality: Compression quality, 0…1; ignored for PNG.
    ///   - original: The file the image came from; its EXIF (exposure, lens,
    ///     date) is copied, with the pixel size updated.
    ///   - keepsLocation: Copy GPS too. Off for files that leave the Mac.
    ///   - rating: Written as `xmp:Rating`, so Lightroom / Photos see the stars.
    static func write(
        _ image: CGImage,
        to destinationURL: URL,
        type: UTType = .jpeg,
        original: URL,
        quality: Double,
        keepsLocation: Bool,
        rating: Rating? = nil
    ) throws {
        try Task.checkCancellation()
        let timing = PipelineMetrics.begin("Encode")
        defer { PipelineMetrics.end(timing) }
        let name = original.lastPathComponent
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL, type.identifier as CFString, 1, nil
        ) else { throw WriteError.failed(name, type) }

        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            // The pixels are already rotated upright by the decoder.
            kCGImagePropertyOrientation: 1,
        ]
        if let source = CGImageSourceCreateWithURL(original as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            if var exif = metadata[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                // Describe the new image, not the sensor.
                exif[kCGImagePropertyExifPixelXDimension] = image.width
                exif[kCGImagePropertyExifPixelYDimension] = image.height
                properties[kCGImagePropertyExifDictionary] = exif
            }
            if var tiff = metadata[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                properties[kCGImagePropertyTIFFDictionary] = tiff
            }
            if keepsLocation, let gps = metadata[kCGImagePropertyGPSDictionary] {
                properties[kCGImagePropertyGPSDictionary] = gps
            }
        }
        if let rating, rating.isRated {
            // ImageIO writes IPTC StarRating out as xmp:Rating as well.
            properties[kCGImagePropertyIPTCDictionary] = [kCGImagePropertyIPTCStarRating: rating.rawValue]
        }

        try Task.checkCancellation()
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw WriteError.failed(name, type)
        }
    }
}
