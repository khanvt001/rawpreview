//
//  ThumbnailService.swift
//  rawpreview
//

import CoreGraphics
import Foundation
import ImageIO

/// Grid thumbnails, decoded from each RAW's embedded preview (see `ImageDecoder`).
nonisolated final class ThumbnailService: Sendable {
    static let shared = ThumbnailService()

    /// Requested sizes are rounded up to one of these so dragging the size slider
    /// reuses cached images instead of re-decoding at every pixel step.
    static let sizeBuckets = [256, 512, 1024]

    private let loader = ImageLoader(cache: ImageCache(name: "thumbnails", totalCostLimitMB: 512))

    static func bucket(for pixelSize: Int) -> Int {
        sizeBuckets.first { $0 >= pixelSize } ?? sizeBuckets[sizeBuckets.count - 1]
    }

    /// Synchronous cache peek. Falls back to a larger cached size, which looks fine
    /// scaled down and avoids a blank cell while the exact size loads.
    func cachedThumbnail(for url: URL, pixelSize: Int) -> CGImage? {
        let bucket = Self.bucket(for: pixelSize)
        for size in Self.sizeBuckets where size >= bucket {
            if let image = loader.cached(Self.key(url, size)) { return image }
        }
        return nil
    }

    /// Largest thumbnail in memory, used as the loupe's instant placeholder.
    func largestCachedThumbnail(for url: URL) -> CGImage? {
        Self.sizeBuckets.reversed().lazy.compactMap { self.loader.cached(Self.key(url, $0)) }.first
    }

    func thumbnail(for url: URL, pixelSize: Int) async -> CGImage? {
        let bucket = Self.bucket(for: pixelSize)
        return await loader.load(Self.key(url, bucket)) {
            guard !Task.isCancelled else { return nil }
            return ImageDecoder.decode(url, maxPixelSize: bucket)
        }
    }

    func prefetch(_ urls: [URL], pixelSize: Int) {
        let bucket = Self.bucket(for: pixelSize)
        for url in urls {
            loader.prefetch(Self.key(url, bucket)) { ImageDecoder.decode(url, maxPixelSize: bucket) }
        }
    }

    func removeAll() {
        loader.cache.removeAll()
    }

    private static func key(_ url: URL, _ size: Int) -> String {
        "\(size)|\(url.path(percentEncoded: false))"
    }
}
