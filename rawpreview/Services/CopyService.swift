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
/// - Optionally each shot lands in a `YYYY-MM-DD` subfolder named after its
///   capture day; a RAW+JPEG pair always shares one folder.
/// - A RAW's `.xmp` sidecar travels with it. If the destination already has
///   one (e.g. Lightroom edits) it is kept and only the rating is merged in;
///   the rating is also written when the card itself couldn't take a sidecar
///   (write-locked card).
/// - Exporting (`Export`), each shot is instead written as a JPEG, HEIF or
///   PNG in the chosen size, with its `ExportLook` (preset and / or Edit
///   adjustments) applied (`render`): one per RAW+JPEG pair, from the same
///   image the loupe shows, star rating embedded. A shot the look doesn't
///   change is exported as shot. A file already at the destination is never
///   overwritten or skipped; the export gets a suffix.
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
        /// Files an export wrote, in plan order, for sharing them afterwards.
        var exported: [URL] = []
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
                String(localized: "Choose a destination outside the folder you're copying from.")
            case let .notEnoughSpace(needed, available):
                String(localized: "Not enough space: \(needed.formatted(.byteCount(style: .file))) needed, \(available.formatted(.byteCount(style: .file))) available.")
            case .sizeMismatch:
                String(localized: "The copy's size doesn't match the original.")
            }
        }
    }

    static let maxConcurrentCopies = 3
    /// File output is sequential and shares the GPU permit with previews.
    static let maxConcurrentRenders = 1

    /// Write each shot as an image file instead of copying the originals.
    struct Export: Sendable {
        /// `nil`, or ignored when `settings.appliesLook` is off: as shot.
        let look: ExportLook?
        let settings: ExportSettings
        var processing: ProcessingConfiguration = .current

        /// What the progress and summary say, e.g. "PNG with Edits applied".
        var title: String {
            if let look, settings.appliesLook {
                return String(localized: "\(settings.format.title) with \(look.title) applied")
            }
            return settings.format.title
        }
    }

    /// One file's copy plan.
    struct Plan: Sendable {
        enum Action: Sendable {
            case copy
            case skipExisting
            /// Export using immutable source/develop state captured at planning.
            case render(DevelopState, ExportSettings)
        }

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
    func plan(
        _ items: [PhotoItem],
        to folder: URL,
        from sourceRoot: URL?,
        intoDateFolders: Bool = false,
        export: Export? = nil
    ) async throws -> [Plan] {
        if let sourceRoot, folder.isContained(in: sourceRoot) {
            throw CopyError.destinationInsideSource
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        // Earliest date per shot, so a pair straddling midnight isn't split.
        let shotDates = intoDateFolders
            ? Dictionary(items.compactMap { item in item.creationDate.map { (item.sidecarURL, $0) } }, uniquingKeysWith: min)
            : [:]

        let items = export == nil ? items : Self.oneImagePerShot(items)
        var reserved = Set<String>()
        var createdFolders: Set<URL> = [folder]
        var plans: [Plan] = []
        for item in items {
            var itemFolder = folder
            if intoDateFolders {
                itemFolder = folder.appending(path: Self.dateFolderName(for: shotDates[item.sidecarURL]), directoryHint: .isDirectory)
                if createdFolders.insert(itemFolder).inserted {
                    try fileManager.createDirectory(at: itemFolder, withIntermediateDirectories: true)
                }
            }
            if let export {
                let destination = Self.resolveExportDestination(
                    for: item, extension: export.settings.format.fileExtension, in: itemFolder, reserved: &reserved
                )
                let state = export.settings.appliesLook
                    ? export.look?.state(for: item, processing: export.processing) ?? DevelopState(processing: export.processing, preset: nil)
                    : DevelopState(processing: export.processing, preset: nil)
                let source = PhotoSourceResolver.resolveNow(item.url, processing: export.processing)
                plans.append(Plan(
                    source: source,
                    destination: destination,
                    size: item.fileSize,
                    action: .render(state, export.settings),
                    isRaw: false,
                    sourceSidecar: nil
                ))
                continue
            }
            let (destination, action) = Self.resolveDestination(for: item, in: itemFolder, reserved: &reserved)
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

        // A rendered JPEG is smaller than the RAW or camera JPEG it comes
        // from, so the source size is a safe upper bound for it; a PNG can be
        // several times larger (`sizeFactor`).
        let factor = export?.settings.sizeFactor ?? 1
        let needed = plans.filter { $0.action.writesFile }.reduce(Int64(0)) { $0 + Int64(Double($1.size) * factor) }
        if let available = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage,
           needed > available {
            throw CopyError.notEnoughSpace(needed: needed, available: available)
        }
        return plans
    }

    /// Images only; a RAW+JPEG pair is one shot, exported once from the RAW
    /// (whose embedded preview is the same picture, at least as large).
    private static func oneImagePerShot(_ items: [PhotoItem]) -> [PhotoItem] {
        var byShot: [URL: PhotoItem] = [:]
        var order: [URL] = []
        for item in items where item.kind.isImage {
            let shot = item.sidecarURL
            if let existing = byShot[shot] {
                if existing.kind != .raw, item.kind == .raw { byShot[shot] = item }
            } else {
                byShot[shot] = item
                order.append(shot)
            }
        }
        return order.compactMap { byShot[$0] }
    }

    /// `DSC_0001.jpg`, or `DSC_0001-1.jpg`… when a file of that name is
    /// already there: it may be the camera's own JPEG, copied earlier.
    private static func resolveExportDestination(
        for item: PhotoItem,
        extension ext: String,
        in folder: URL,
        reserved: inout Set<String>
    ) -> URL {
        var suffix = 0
        while true {
            let name = suffix == 0 ? "\(item.baseName).\(ext)" : "\(item.baseName)-\(suffix).\(ext)"
            let candidate = folder.appending(path: name)
            suffix += 1
            let key = candidate.path(percentEncoded: false).lowercased()
            guard !reserved.contains(key),
                  !FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false))
            else { continue }
            reserved.insert(key)
            return candidate
        }
    }

    /// `2026-10-31` in the Mac's time zone (the day the photographer saw),
    /// or `Undated` when the file carries no date.
    private static func dateFolderName(for date: Date?) -> String {
        guard let date else { return "Undated" }
        let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
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
            let key = candidate.path(percentEncoded: false).lowercased()
            guard !reserved.contains(key) else { continue }

            let path = candidate.path(percentEncoded: false)
            guard fileManager.fileExists(atPath: path) else {
                reserved.insert(key)
                return (candidate, .copy)
            }
            let existingSize = (try? fileManager.attributesOfItem(atPath: path)[.size] as? Int64) ?? -1
            if existingSize == item.fileSize {
                reserved.insert(key)
                return (candidate, .skipExisting)
            }
        }
    }

    // MARK: - Copying

    private enum Outcome: Sendable {
        case copied(Int64)
        case skipped
        case cancelled
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

        var exported: [Int: URL] = [:]
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

            let rendering = plans.contains { if case .render = $0.action { true } else { false } }
            let concurrency = rendering ? Self.maxConcurrentRenders : Self.maxConcurrentCopies
            for _ in 0..<min(concurrency, plans.count) { startNext() }

            while let (index, outcome) = await group.next() {
                let plan = plans[index]
                switch outcome {
                case .copied(let bytes):
                    report.copied += 1
                    report.copiedBytes += bytes
                    if case .render = plan.action { exported[index] = plan.destination }
                    // Base names: an export changes the extension, not the name.
                    if plan.destination.deletingPathExtension().lastPathComponent
                        != plan.source.deletingPathExtension().lastPathComponent { report.renamed += 1 }
                case .skipped:
                    report.skipped += 1
                case .cancelled:
                    report.wasCancelled = true
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

        report.exported = exported.keys.sorted().compactMap { exported[$0] }
        report.wasCancelled = report.wasCancelled || (Task.isCancelled && progress.completedFiles < plans.count)
        report.duration = ContinuousClock.now - start
        let withPreset = plans.contains { if case .render = $0.action { true } else { false } }
        Analytics.track("photos_copied", ["count": report.copied, "with_preset": withPreset])
        return report
    }

    /// Copies one file (and its sidecar) on a TaskGroup child.
    private static func perform(_ plan: Plan, rating: Rating?) async -> Outcome {
        guard !Task.isCancelled else { return .cancelled }
        let fileManager = FileManager.default
        do {
            if case let .render(state, settings) = plan.action {
                return .copied(try await render(plan, state: state, settings: settings, rating: rating))
            }
            var outcome = Outcome.skipped
            if case .copy = plan.action {
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
            if Task.isCancelled || error is CancellationError { return .cancelled }
            return .failed(error.localizedDescription)
        }
    }

    /// Decodes at the chosen size, applies the preset (if any) and writes the
    /// file; returns its size. Off the cooperative pool's threads: one takes
    /// several hundred ms.
    private static func render(_ plan: Plan, state: DevelopState, settings: ExportSettings, rating: Rating?) async throws -> Int64 {
        let result: Result<Int64, any Error>? = await RenderCoordinator.run(.export) {
            Result { try renderNow(plan, state: state, settings: settings, rating: rating) }
        }
        guard let result else { throw CancellationError() }
        return try result.get()
    }

    private static func renderNow(_ plan: Plan, state: DevelopState, settings: ExportSettings, rating: Rating?) throws -> Int64 {
        try Task.checkCancellation()
        let partial = plan.destination.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: partial)
        do {
            try ExportService.write(source: plan.source, to: partial, state: state, settings: settings, rating: rating)
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: partial, to: plan.destination)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        let size = try FileManager.default.attributesOfItem(atPath: plan.destination.path(percentEncoded: false))[.size] as? Int64
        return size ?? 0
    }

    enum ExportError: LocalizedError {
        case decodeFailed(String)

        var errorDescription: String? {
            switch self {
            case .decodeFailed(let name): String(localized: "Couldn't read \(name).")
            }
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

nonisolated extension CopyService.Plan.Action {
    /// Copies or renders (not a skip).
    var writesFile: Bool {
        if case .skipExisting = self { return false }
        return true
    }
}
