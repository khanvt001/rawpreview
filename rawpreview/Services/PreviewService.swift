//
//  PreviewService.swift
//  rawpreview
//

import CoreGraphics
import Foundation

/// Full-resolution images for Single Image (loupe) mode and 100% zoom.
///
/// The loupe paints in two steps: the largest grid thumbnail already in memory
/// (`placeholder`, instant), then the full-resolution image (~90 ms for a 20 MP
/// NEF's embedded JPEG). Neighbours are prefetched so arrow-key navigation lands
/// on an already-decoded image.
nonisolated final class PreviewService: Sendable {
    static let shared = PreviewService()

    /// ~80 MB per 20 MP image; enough for the current image plus ±2 neighbours
    /// and a little history.
    private let loader = ImageLoader(cache: ImageCache(name: "full", totalCostLimitMB: 640, countLimit: 6))

    /// Best image available right now without decoding: the full image if
    /// cached, otherwise the largest cached grid thumbnail.
    func cachedImage(for url: URL) -> CGImage? {
        cachedFullResolution(for: url) ?? placeholder(for: url)
    }

    func cachedFullResolution(for url: URL) -> CGImage? {
        loader.cached(Self.key(url))
    }

    func placeholder(for url: URL) -> CGImage? {
        ThumbnailService.shared.largestCachedThumbnail(for: url)
    }

    func fullResolution(for url: URL) async -> CGImage? {
        return await loader.load(Self.key(url), priority: .userInitiated) {
            guard !Task.isCancelled else { return nil }
            return await RenderCoordinator.run(.high) {
                ImageDecoder.decode(url, maxPixelSize: nil)
            }
        }
    }

    /// Warms full-resolution images for the neighbours of the current one.
    func prefetch(_ urls: [URL]) {
        var jobs: [String: ImageLoader.Work] = [:]
        for url in urls {
            jobs[Self.key(url)] = {
                await RenderCoordinator.run(.low) { ImageDecoder.decode(url, maxPixelSize: nil) }
            }
        }
        loader.prefetch(jobs)
    }

    func removeAll() {
        loader.prefetch([:])
        loader.cache.removeAll()
    }

    private static func key(_ url: URL) -> String {
        ImageSourceKey.display(url, size: "full")
    }
}
