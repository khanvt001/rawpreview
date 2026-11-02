import Foundation

/// Coalesces identical work. Cancellation releases a caller immediately; the
/// worker is cancelled only when its last subscriber leaves. Generation IDs
/// prevent an abandoned worker from completing a newer request for the key.
/// A latest-only lane owns its keys: switching keys supersedes all of that
/// key's subscribers. Use separate keys for background and interactive work.
actor SharedWork<Key: Hashable & Sendable, Value: Sendable> {
    struct Latest: Sendable {
        let lane: String
        let id: UInt64
    }
    private struct Entry {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Value?, Never>]
    }
    private var entries: [Key: Entry] = [:]
    private var latest: [String: (id: UInt64, key: Key)] = [:]

    func run(_ key: Key, priority: TaskPriority? = nil, latest request: Latest? = nil, work: @escaping @Sendable () async -> Value?) async -> Value? {
        guard !Task.isCancelled else { return nil }
        if let request {
            if let previous = latest[request.lane] {
                guard request.id >= previous.id else { return nil }
                if previous.key != key { abandon(previous.key) }
            }
            latest[request.lane] = (request.id, key)
        }
        let waiterID = UUID()
        let value: Value? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                if var entry = entries[key] {
                    entry.waiters[waiterID] = continuation
                    entries[key] = entry
                    PipelineMetrics.event("work.coalesced")
                } else {
                    let id = UUID()
                    let task = Task.detached(priority: priority ?? Task.currentPriority) {
                        let value = await work()
                        await self.finish(key, id: id, value: Task.isCancelled ? nil : value)
                    }
                    entries[key] = Entry(id: id, task: task, waiters: [waiterID: continuation])
                }
            }
        } onCancel: {
            Task { await self.cancel(key, waiterID: waiterID) }
        }
        return Task.isCancelled ? nil : value
    }

    private func finish(_ key: Key, id: UUID, value: Value?) {
        guard let entry = entries[key], entry.id == id else { return }
        entries[key] = nil
        for waiter in entry.waiters.values { waiter.resume(returning: value) }
    }

    private func abandon(_ key: Key) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        entry.task.cancel()
        for waiter in entry.waiters.values { waiter.resume(returning: nil) }
        PipelineMetrics.event("work.superseded")
    }

    private func cancel(_ key: Key, waiterID: UUID) {
        guard var entry = entries[key], let waiter = entry.waiters.removeValue(forKey: waiterID) else { return }
        waiter.resume(returning: nil)
        PipelineMetrics.event("work.cancelled")
        if entry.waiters.isEmpty {
            entry.task.cancel()
            entries[key] = nil
        } else {
            entries[key] = entry
        }
    }
}
