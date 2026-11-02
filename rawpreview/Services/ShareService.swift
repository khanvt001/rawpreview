//
//  ShareService.swift
//  rawpreview
//

import CoreGraphics
import Foundation

/// Makes lightweight JPEG copies for sharing (AirDrop, Messages, Mail…), so a
/// 25 MB RAW goes out as a ~1 MB JPEG the other side can open.
///
/// - Uses the snapshotted processing source, preset, Amount and Light deltas
///   through ExportService, the same graph as loupe and normal exports.
/// - Long edge 2048 px by default (Settings), quality 0.85; orientation baked in.
/// - Optionally with a preset and Edit adjustments applied (`ExportLook`).
/// - Camera EXIF (exposure, lens, date) is kept; GPS is removed, so a shared
///   photo doesn't reveal where it was taken.
/// - Written under a per-share folder in the temporary directory; old
///   folders are purged at launch.
nonisolated enum ShareService {
    static let maxPixelSizeKey = "shareLongEdge"
    static let maxPixelSizeChoices = [1024, 2048, 3072, 4096]
    static var maxPixelSize: Int {
        let stored = UserDefaults.standard.integer(forKey: maxPixelSizeKey)
        return stored > 0 ? stored : 2048
    }
    static let quality = 0.85

    enum ShareError: LocalizedError {
        case decodeFailed(String)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .decodeFailed(let name): String(localized: "Couldn't read \(name).")
            case .writeFailed(let name): String(localized: "Couldn't create a JPEG for \(name).")
            }
        }
    }

    static var exportRoot: URL {
        FileManager.default.temporaryDirectory.appending(path: "RawPreview-Share", directoryHint: .isDirectory)
    }

    /// One JPEG per shot, in input order, named after the original
    /// (`DSC_6260.NEF` → `DSC_6260.jpg`), with `look` applied if given.
    @concurrent
    static func makeJPEGs(for items: [PhotoItem], look: ExportLook? = nil,
                          processing: ProcessingConfiguration = .current,
                          longEdge: Int = maxPixelSize,
                          onProgress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> [URL] {
        let folder = exportRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let jobs = uniqueJobs(for: items)

        onProgress(0, jobs.count)
        var results: [URL] = []
        do {
            for job in jobs {
                try Task.checkCancellation()
                let state = look?.state(for: job.item, processing: processing) ?? DevelopState(processing: processing, preset: nil)
                let source = PhotoSourceResolver.resolveNow(job.item.url, processing: processing)
                let result: Result<URL, any Error>? = await RenderCoordinator.run(.export) {
                    Result {
                        var settings = ExportSettings()
                        settings.longEdge = longEdge
                        settings.quality = quality
                        settings.keepsLocation = false
                        let destination = folder.appending(path: job.name)
                        try ExportService.write(source: source, to: destination, state: state, settings: settings)
                        return destination
                    }
                }
                guard let result else { throw CancellationError() }
                results.append(try result.get())
                onProgress(results.count, jobs.count)
            }
            return results
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// A RAW+JPEG pair is one shot: share it once, from the RAW. Different
    /// photos with the same name (`100NZ_50/DSC_0001`, `101NZ_50/DSC_0001`)
    /// get `-2`, `-3`… so they don't overwrite each other.
    private static func uniqueJobs(for items: [PhotoItem]) -> [(item: PhotoItem, name: String)] {
        var byShot: [URL: PhotoItem] = [:]
        var order: [URL] = []
        for item in items {
            let shot = item.sidecarURL
            if let existing = byShot[shot] {
                if existing.kind != .raw, item.kind == .raw { byShot[shot] = item }
            } else {
                byShot[shot] = item
                order.append(shot)
            }
        }

        var used = Set<String>()
        return order.map { shot in
            let item = byShot[shot]!
            var name = item.baseName
            var suffix = 2
            while used.contains(name.lowercased()) {
                name = "\(item.baseName)-\(suffix)"
                suffix += 1
            }
            used.insert(name.lowercased())
            return (item, "\(name).jpg")
        }
    }

    /// Removes share folders older than a day. Recent ones are kept in case a
    /// transfer (e.g. AirDrop) is still reading them.
    @concurrent
    static func purgeOldExports() async {
        let fileManager = FileManager.default
        guard let folders = try? fileManager.contentsOfDirectory(
            at: exportRoot, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        let cutoff = Date.now.addingTimeInterval(-24 * 60 * 60)
        for folder in folders {
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if created < cutoff {
                try? fileManager.removeItem(at: folder)
            }
        }
    }
}
