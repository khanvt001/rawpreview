import Foundation
import os

/// All GPU rendering and file-output jobs share one permit. The interactive
/// lane retains only the newest pending request; tiles/prefetch yield to it.
/// An already-submitted GPU band finishes before the next job starts.
nonisolated enum RenderCoordinator {
    private static let limiter = AsyncLimiter(limit: 1)
    private static let sequence = OSAllocatedUnfairLock(initialState: UInt64(0))

    static func nextRequestID() -> UInt64 {
        sequence.withLock { $0 += 1; return $0 }
    }

    static func run<T: Sendable>(
        _ priority: AsyncLimiter.Priority,
        latest: String? = nil,
        requestID: UInt64? = nil,
        work: @Sendable () -> T?
    ) async -> T? {
        await limiter.run(priority, superseding: latest, requestID: requestID, work)
    }
}
