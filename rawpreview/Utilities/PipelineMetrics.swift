import Foundation
import os

/// Signposts for Instruments. Bounded in-process samples are opt-in via
/// RAWPREVIEW_METRICS=1, so ordinary browsing keeps no timing history.
nonisolated enum PipelineMetrics {
    private static let log = OSLog(subsystem: "rawpreview", category: "ImagePipeline")
    private static let enabled = ProcessInfo.processInfo.environment["RAWPREVIEW_METRICS"] == "1"
    private struct State {
        var counts: [String: Int] = [:]
        var samples: [String: [Double]] = [:]
    }
    private static let state = OSAllocatedUnfairLock(initialState: State())

    struct Interval {
        let name: StaticString
        let id: OSSignpostID
        let start: ContinuousClock.Instant
    }

    static func begin(_ name: StaticString) -> Interval {
        let interval = Interval(name: name, id: OSSignpostID(log: log), start: .now)
        os_signpost(.begin, log: log, name: name, signpostID: interval.id)
        return interval
    }

    static func end(_ interval: Interval) {
        os_signpost(.end, log: log, name: interval.name, signpostID: interval.id)
        guard enabled else { return }
        let duration = interval.start.duration(to: .now).components
        let ms = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
        state.withLock { state in
            let key = interval.name.description
            state.counts[key, default: 0] += 1
            var samples = state.samples[key, default: []]
            if samples.count == 512 { samples.removeFirst() }
            samples.append(ms)
            state.samples[key] = samples
        }
    }

    static func event(_ name: String) {
        guard enabled else { return }
        state.withLock { $0.counts[name, default: 0] += 1 }
    }

    static func reset() { state.withLock { $0 = State() } }

    static func summary() -> String {
        state.withLock { state in
            state.counts.keys.sorted().map { key in
                let count = state.counts[key, default: 0]
                guard let sorted = state.samples[key]?.sorted(), !sorted.isEmpty else { return "\(key): \(count)" }
                let median = sorted[sorted.count / 2]
                let p95 = sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
                return String(format: "%@: %d, median %.2f ms, p95 %.2f ms (last %d)", key, count, median, p95, sorted.count)
            }.joined(separator: "\n")
        }
    }
}
