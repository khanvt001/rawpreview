//
//  ImageLoader.swift
//  rawpreview
//

import CoreGraphics
import Foundation
import os

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

    nonisolated let cache: ImageCache
    private let work = SharedWork<String, CGImage>()
    private struct Prefetch {
        let id: UUID
        let task: Task<Void, Never>
    }
    private var prefetchTasks: [String: Prefetch] = [:]
    private nonisolated let prefetchGeneration = OSAllocatedUnfairLock(initialState: 0)

    init(cache: ImageCache) {
        self.cache = cache
    }

    nonisolated func cached(_ key: String) -> CGImage? {
        cache[key]
    }

    func load(_ key: String, priority: TaskPriority? = nil, work: @escaping Work) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        if let hit = cache[key] {
            PipelineMetrics.event("decode.hit")
            return hit
        }
        let cache = cache
        return await self.work.run(key, priority: priority) {
            // Another caller may have filled the cache before registration.
            if let hit = cache[key] { return hit }
            PipelineMetrics.event("decode.miss")
            guard let image = await work(), !Task.isCancelled else { return nil }
            cache[key] = image
            return image
        }
    }

    /// Replaces the prefetch window, cancelling obsolete subscriptions. A
    /// visible caller sharing the same decode keeps its subscription.
    nonisolated func prefetch(_ jobs: [String: Work]) {
        let generation = prefetchGeneration.withLock { $0 += 1; return $0 }
        Task { await self.replacePrefetch(jobs, generation: generation) }
    }

    private func replacePrefetch(_ jobs: [String: Work], generation: Int) {
        guard prefetchGeneration.withLock({ $0 }) == generation else { return }
        for key in Array(prefetchTasks.keys) where jobs[key] == nil {
            prefetchTasks.removeValue(forKey: key)?.task.cancel()
        }
        for (key, work) in jobs where cached(key) == nil && prefetchTasks[key] == nil {
            let id = UUID()
            let task = Task(priority: .utility) {
                _ = await self.load(key, priority: .utility, work: work)
                self.prefetchFinished(key, id: id)
            }
            prefetchTasks[key] = Prefetch(id: id, task: task)
        }
    }

    private func prefetchFinished(_ key: String, id: UUID) {
        // The task may have been removed and replaced in a newer window.
        if prefetchTasks[key]?.id == id { prefetchTasks[key] = nil }
    }
}
