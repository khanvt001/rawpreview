import Foundation
import os

/// A strict, byte-bounded LRU. Keys and bookkeeping are evicted together.
nonisolated final class BoundedCache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private struct Entry: Sendable {
        let value: Value
        let cost: Int
    }
    private struct State: Sendable {
        var entries: [Key: Entry] = [:]
        var order: [Key] = []
        var bytes = 0
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let byteLimit: Int
    private let countLimit: Int

    init(byteLimit: Int, countLimit: Int) {
        self.byteLimit = byteLimit
        self.countLimit = countLimit
    }

    subscript(key: Key) -> Value? {
        state.withLock { state in
            guard let entry = state.entries[key] else { return nil }
            state.order.removeAll { $0 == key }
            state.order.append(key)
            return entry.value
        }
    }

    /// The most recently used entry whose key matches, without touching the order.
    func last(where matches: @Sendable (Key) -> Bool) -> (key: Key, value: Value)? {
        state.withLock { state in
            guard let key = state.order.last(where: matches), let entry = state.entries[key] else { return nil }
            return (key, entry.value)
        }
    }

    func insert(_ value: Value, for key: Key, cost: Int, replacing matches: @Sendable (Key) -> Bool = { _ in false }) {
        state.withLock { state in
            let removed = state.order.filter { $0 == key || matches($0) }
            for old in removed {
                state.bytes -= state.entries.removeValue(forKey: old)?.cost ?? 0
            }
            state.order.removeAll { removed.contains($0) }
            guard cost <= byteLimit else { return }
            state.entries[key] = Entry(value: value, cost: cost)
            state.order.append(key)
            state.bytes += cost
            while state.bytes > byteLimit || state.order.count > countLimit {
                let old = state.order.removeFirst()
                state.bytes -= state.entries.removeValue(forKey: old)?.cost ?? 0
            }
        }
    }

    func removeAll() {
        state.withLock { $0 = State() }
    }
}
