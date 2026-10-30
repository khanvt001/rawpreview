//
//  CopyService.swift
//  rawpreview
//

import Foundation

/// Batch-copies marked files from the card to a destination folder.
///
/// - Destination names are planned up front, sequentially, so two
///   `DSC_0001.NEF` from different card folders can't race for one name.
/// - A file already at the destination with the same size is skipped, so
///   re-running a copy after an interruption only copies what's missing.
///   A different file with the same name gets a `-1`, `-2`… suffix.
/// - Each file is copied to a `.partial` name and renamed once its size is
///   verified, so an ejected card never leaves a truncated photo behind.
/// - Copies run in a `TaskGroup`, a few at a time. Measured on a Nikon Z 50
///   card, throughput is the card's read speed (~85–88 MB/s) whether 1, 3 or
///   6 files copy at once; the cap keeps cancellation snappy (only the files
///   in flight finish) and lets a fast source overlap with a slow destination.
/// - A RAW's `.xmp` sidecar travels with it. If the destination already has
///   one (e.g. Lightroom edits) it is kept and only the rating is merged in;
///   the rating is also written when the card itself couldn't take a sidecar
///   (write-locked card).
nonisolated struct CopyService: Sendable {
    struct Progress: Sendable, Equatable {
        var completedFiles = 0
        var totalFiles = 0
        var completedBytes: Int64 = 0
        var totalBytes: Int64 = 0
        var currentFile: String?

        var fraction: Double {
            totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 0
        }
    }

    struct Report: Sendable, Equatable {
        struct Failure: Sendable, Equatable {
            let fileName: String
            let reason: String
        }

        var destination: URL
        var copied = 0
        var skipped = 0
        var renamed = 0
        var failures: [Failure] = []
        var copiedBytes: Int64 = 0
        var duration: Duration = .zero
        var wasCancelled = false
    }

    enum CopyError: LocalizedError {
        case destinationInsideSource
        case notEnoughSpace(needed: Int64, available: Int64)
        case sizeMismatch

        var errorDescription: String? {
            switch self {
            case .destinationInsideSource:
                "Choose a destination outside the folder you're copying from."
            case let .notEnoughSpace(needed, available):
                "Not enough space: \(needed.formatted(.byteCount(style: .file))) needed, \(available.formatted(.byteCount(style: .file))) available."
            case .sizeMismatch:
                "The copy's size doesn't match the original."
            }
        }
    }

    static let maxConcurrentCopies = 3

    /// One file's copy plan.
    struct Plan: Sendable {
        enum Action: Sendable { case copy, skipExisting }

        let source: URL
        let destination: URL
        let size: Int64
        let action: Action
        let isRaw: Bool
        /// The RAW's sidecar, when one exists next to it.
        let sourceSidecar: URL?
    }

    // MARK: - Planning

    /// Works out every destination name and checks free space. Throws before
    /// anything is written if the copy can't succeed.
    @concurrent
    func plan(_ items: [PhotoItem], to folder: URL, from sourceRoot: URL?) async throws -> [Plan] {
        if let sourceRoot, folder.isContained(in: sourceRoot) {
            throw CopyError.destinationInsideSource
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        var reserved = Set<String>()
        var plans: [Plan] = []
        for item in items {
            let (destination, action) = Self.resolveDestination(for: item, in: folder, reserved: &reserved)
            let sidecar = item.kind == .raw && fileManager.fileExists(atPath: item.sidecarURL.path(percentEncoded: false))
                ? item.sidecarURL : nil
            plans.append(Plan(
                source: item.url,
                destination: destination,
                size: item.fileSize,
                action: action,
                isRaw: item.kind == .raw,
                sourceSidecar: sidecar
            ))
        }

        let needed = plans.filter { $0.action == .copy }.reduce(Int64(0)) { $0 + $1.size }
        if let available = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage,
           needed > available {
            throw CopyError.notEnoughSpace(needed: needed, available: available)
        }
        return plans
    }

    private static func resolveDestination(
        for item: PhotoItem,
        in folder: URL,
        reserved: inout Set<String>
    ) -> (URL, Plan.Action) {
        let fileManager = FileManager.default
        let base = item.baseName
        let ext = item.url.pathExtension
        var suffix = 0
        while true {
            let name = suffix == 0 ? "\(base).\(ext)" : "\(base)-\(suffix).\(ext)"
            let candidate = folder.appending(path: name)
            suffix += 1
            guard !reserved.contains(name.lowercased()) else { continue }

            let path = candidate.path(percentEncoded: false)
            guard fileManager.fileExists(atPath: path) else {
                reserved.insert(name.lowercased())
                return (candidate, .copy)
            }
            let existingSize = (try? fileManager.attributesOfItem(atPath: path)[.size] as? Int64) ?? -1
            if existingSize == item.fileSize {
                reserved.insert(name.lowercased())
                return (candidate, .skipExisting)
            }
        }
    }

    // MARK: - Copying

    private enum Outcome: Sendable {
        case copied(Int64)
        case skipped
        case failed(String)
    }

    /// Copies `plans`, reporting progress after each file. Cancelling the
    /// calling task stops new copies (in-flight files finish) and still
    /// returns a report with `wasCancelled` set.
    @concurrent
    func copy(
        _ plans: [Plan],
        to folder: URL,
        ratings: [URL: Rating],
        onProgress: @escaping @Sendable (Progress) -> Void
    ) async -> Report {
        let start = ContinuousClock.now
        var report = Report(destination: folder)
        var progress = Progress(totalFiles: plans.count, totalBytes: plans.reduce(0) { $0 + $1.size })
        onProgress(progress)

        await withTaskGroup(of: (Int, Outcome).self) { group in
            var next = 0
            func startNext() {
                guard next < plans.count, !Task.isCancelled else { return }
                let index = next
                next += 1
                let plan = plans[index]
                group.addTask {
                    (index, await Self.perform(plan, rating: ratings[PhotoItem.sidecarURL(for: plan.source)]))
                }
            }

            for _ in 0..<min(Self.maxConcurrentCopies, plans.count) { startNext() }

            while let (index, outcome) = await group.next() {
                let plan = plans[index]
                switch outcome {
                case .copied(let bytes):
                    report.copied += 1
                    report.copiedBytes += bytes
                    if plan.destination.lastPathComponent != plan.source.lastPathComponent { report.renamed += 1 }
                case .skipped:
                    report.skipped += 1
                case .failed(let reason):
                    report.failures.append(.init(fileName: plan.source.lastPathComponent, reason: reason))
                }
                progress.completedFiles += 1
                progress.completedBytes += plan.size
                progress.currentFile = plan.source.lastPathComponent
                onProgress(progress)
                startNext()
            }
        }

        report.wasCancelled = Task.isCancelled && progress.completedFiles < plans.count
        report.duration = ContinuousClock.now - start
        return report
    }

    /// Copies one file (and its sidecar) on a TaskGroup child.
    private static func perform(_ plan: Plan, rating: Rating?) async -> Outcome {
        guard !Task.isCancelled else { return .failed("Cancelled") }
        let fileManager = FileManager.default
        do {
            var outcome = Outcome.skipped
            if plan.action == .copy {
                let partial = plan.destination.appendingPathExtension("partial")
                try? fileManager.removeItem(at: partial)
                do {
                    try fileManager.copyItem(at: plan.source, to: partial)
                    let copiedSize = try fileManager.attributesOfItem(atPath: partial.path(percentEncoded: false))[.size] as? Int64
                    guard copiedSize == plan.size else { throw CopyError.sizeMismatch }
                    try fileManager.moveItem(at: partial, to: plan.destination)
                } catch {
                    try? fileManager.removeItem(at: partial)
                    throw error
                }
                outcome = .copied(plan.size)
            }
            try await copySidecar(for: plan, rating: rating)
            return outcome
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Sidecar named after the destination file (which may have a `-1` suffix).
    private static func copySidecar(for plan: Plan, rating: Rating?) async throws {
        guard plan.isRaw else { return }
        let destination = PhotoItem.sidecarURL(for: plan.destination)
        if let source = plan.sourceSidecar,
           !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.copyItem(at: source, to: destination)
        }
        // Merge rather than overwrite: keeps Lightroom edits in an existing sidecar.
        if let rating, rating.isRated {
            try await XMPService.shared.setRating(rating, sidecar: destination)
        }
    }
}
