//
//  AsyncLimiter.swift
//  rawpreview
//

import Foundation

/// Caps how many jobs run at once. Memory cards read sequentially at best:
/// fifteen whole-file reads started together all finish late (measured: first
/// thumbnail after ~6 s on a Z 50 card), while two at a time put the first one
/// on screen in well under a second for the same total time.
///
/// Waiters are served in arrival order, `.high` before `.low`, and a waiter
/// whose task is cancelled (its grid cell scrolled away) leaves the queue
/// without ever running.
actor AsyncLimiter {
    enum Priority {
        /// On screen now.
        case high
        /// Prefetch; only runs when nothing visible is waiting.
        case low
    }

    private struct Waiter {
        let id: UUID
        let priority: Priority
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let limit: Int
    private var running = 0
    private var waiters: [Waiter] = []

    init(limit: Int) {
        self.limit = limit
    }

    /// Runs `body` once a slot is free. Returns `nil` without running it if the
    /// calling task is cancelled while waiting.
    @concurrent
    nonisolated func run<T: Sendable>(_ priority: Priority, _ body: @Sendable () -> T?) async -> T? {
        guard await acquire(priority) else { return nil }
        let result = body()
        await release()
        return result
    }

    private func acquire(_ priority: Priority) async -> Bool {
        if running < limit {
            running += 1
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Runs synchronously on this actor, so a cancellation that
                // arrives later always finds the waiter already queued.
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    waiters.append(Waiter(id: id, priority: priority, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    /// Hands the slot straight to the next waiter, so `running` stays the same.
    private func release() {
        let next = waiters.firstIndex { $0.priority == .high } ?? waiters.indices.first
        if let next {
            waiters.remove(at: next).continuation.resume(returning: true)
        } else {
            running -= 1
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }
}
