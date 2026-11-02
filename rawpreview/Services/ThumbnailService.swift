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
    /// Each decode reads a whole file off the card, so only a couple run at once
    /// (see `AsyncLimiter`). Embedded-thumbnail reads are tiny and skip it.
    private let cardReads = AsyncLimiter(limit: 2)

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

    /// Synchronous peek at the low-res stand-in from `quickThumbnail(for:)`.
    func cachedQuickThumbnail(for url: URL) -> CGImage? {
        loader.cached(Self.quickKey(url))
    }

    /// The file's embedded EXIF thumbnail: blurry, but on screen in a few ms
    /// while the real thumbnail waits its turn to read the card. `nil` for RAW.
    func quickThumbnail(for url: URL) async -> CGImage? {
        await loader.load(Self.quickKey(url)) {
            guard !Task.isCancelled else { return nil }
            return ImageDecoder.embeddedThumbnail(url)
        }
    }

    func thumbnail(for url: URL, pixelSize: Int) async -> CGImage? {
        let bucket = Self.bucket(for: pixelSize)
        let cardReads = cardReads
        return await loader.load(Self.key(url, bucket)) {
            await cardReads.run(.high) {
                guard !Task.isCancelled else { return nil }
                return Self.decodePreview(url, pixelSize: bucket)
            }
        }
    }

    func prefetch(_ urls: [URL], pixelSize: Int) {
        let bucket = Self.bucket(for: pixelSize)
        let cardReads = cardReads
        var jobs: [String: ImageLoader.Work] = [:]
        for url in urls {
            jobs[Self.key(url, bucket)] = {
                await cardReads.run(.low) { Self.decodePreview(url, pixelSize: bucket) }
            }
        }
        loader.prefetch(jobs)
    }

    func removeAll() {
        loader.prefetch([:])
        loader.cache.removeAll()
    }

    /// Grid/prefetch must not start an uncoordinated RAW engine merely to
    /// enlarge a small embedded preview. Full RAW development belongs to the
    /// shared heavy-work permit in DevelopService.
    private static func decodePreview(_ url: URL, pixelSize: Int) -> CGImage? {
        guard let image = ImageDecoder.embeddedSource(url, maxPixelSize: pixelSize), !Task.isCancelled else { return nil }
        return ImageDecoder.prepareForDisplay(image)
    }

    private static func key(_ url: URL, _ size: Int) -> String {
        ImageSourceKey.display(url, size: String(size))
    }

    private static func quickKey(_ url: URL) -> String {
        ImageSourceKey.display(url, size: "exif")
    }
}
