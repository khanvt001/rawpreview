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
        /// File output; yields to interactive rendering.
        case export
        /// Prefetch; only runs when nothing visible is waiting.
        case low
    }

    private struct Waiter {
        let id: UUID
        let priority: Priority
        let superseding: String?
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let limit: Int
    private var running = 0
    private var waiters: [Waiter] = []
    private var latestRequests: [String: UInt64] = [:]

    init(limit: Int) {
        self.limit = limit
    }

    /// Runs `body` once a slot is free. Returns `nil` without running it if the
    /// calling task is cancelled while waiting.
    @concurrent
    nonisolated func run<T: Sendable>(_ priority: Priority, superseding: String? = nil, requestID: UInt64? = nil, _ body: @Sendable () -> T?) async -> T? {
        let wait = PipelineMetrics.begin("QueueWait")
        let acquired = await acquire(priority, superseding: superseding, requestID: requestID)
        PipelineMetrics.end(wait)
        guard acquired else { return nil }
        // Cancellation can arrive as a waiter is handed a slot.
        let result = Task.isCancelled ? nil : body()
        await release()
        return result
    }

    private func acquire(_ priority: Priority, superseding: String?, requestID: UInt64?) async -> Bool {
        guard !Task.isCancelled else { return false }
        if let superseding {
            if let requestID {
                guard requestID >= latestRequests[superseding, default: 0] else {
                    PipelineMetrics.event("queue.stale")
                    return false
                }
                latestRequests[superseding] = requestID
            }
            let obsolete = waiters.filter { $0.superseding == superseding }
            waiters.removeAll { $0.superseding == superseding }
            for waiter in obsolete { waiter.continuation.resume(returning: false) }
            if !obsolete.isEmpty { PipelineMetrics.event("queue.superseded") }
        }
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
                    waiters.append(Waiter(id: id, priority: priority, superseding: superseding, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    /// Hands the slot straight to the next waiter, so `running` stays the same.
    private func release() {
        let next = waiters.firstIndex { $0.priority == .high }
            ?? waiters.firstIndex { $0.priority == .export }
            ?? waiters.indices.first
        if let next {
            waiters.remove(at: next).continuation.resume(returning: true)
        } else {
            running -= 1
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
        PipelineMetrics.event("queue.cancelled")
    }
}
