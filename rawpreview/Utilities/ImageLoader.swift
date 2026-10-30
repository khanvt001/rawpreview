//
//  ImageLoader.swift
//  rawpreview
//

import CoreGraphics
import Foundation

/// Cache-first image loading with request coalescing.
///
/// - Hits are served synchronously via `cached(_:)` so views can paint on the
///   first frame without a placeholder flash.
/// - Concurrent requests for the same key share one decode.
/// - A decode is cancelled only when *every* caller waiting on it is cancelled
///   (e.g. all grid cells showing that file scrolled off screen).
/// - Decodes run on the global concurrent pool, never on this actor, so many can
///   proceed in parallel; the actor only guards the bookkeeping.
actor ImageLoader {
    typealias Work = @Sendable () async -> CGImage?

    private struct InFlight {
        let id: UUID
        let task: Task<CGImage?, Never>
        var waiters: Int
    }

    nonisolated let cache: ImageCache
    private var inFlight: [String: InFlight] = [:]

    init(cache: ImageCache) {
        self.cache = cache
    }

    nonisolated func cached(_ key: String) -> CGImage? {
        cache[key]
    }

    func load(_ key: String, priority: TaskPriority? = nil, work: @escaping Work) async -> CGImage? {
        if let hit = cache[key] { return hit }

        let entry: InFlight
        if var existing = inFlight[key] {
            existing.waiters += 1
            entry = existing
        } else {
            entry = InFlight(
                id: UUID(),
                task: Task.detached(priority: priority ?? Task.currentPriority) { await work() },
                waiters: 1
            )
        }
        inFlight[key] = entry

        let image = await withTaskCancellationHandler {
            await entry.task.value
        } onCancel: {
            Task { await self.waiterCancelled(key: key, id: entry.id) }
        }

        // First waiter back publishes the result; the rest find the entry gone.
        if inFlight[key]?.id == entry.id {
            inFlight[key] = nil
            if let image { cache[key] = image }
        }
        return image
    }

    /// Starts loads without awaiting them (used for neighbour prefetch).
    nonisolated func prefetch(_ key: String, work: @escaping Work) {
        guard cached(key) == nil else { return }
        Task(priority: .utility) { _ = await self.load(key, priority: .utility, work: work) }
    }

    private func waiterCancelled(key: String, id: UUID) {
        guard var entry = inFlight[key], entry.id == id else { return }
        entry.waiters -= 1
        if entry.waiters <= 0 {
            entry.task.cancel()
            inFlight[key] = nil
        } else {
            inFlight[key] = entry
        }
    }
}
