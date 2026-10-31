//
//  ShareService.swift
//  rawpreview
//

import CoreGraphics
import Foundation

/// Makes lightweight JPEG copies for sharing (AirDrop, Messages, Mail…), so a
/// 25 MB RAW goes out as a ~1 MB JPEG the other side can open.
///
/// - Decoded from the RAW's embedded preview (`ImageDecoder`), so it's fast
///   and matches what the camera showed.
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
    static func makeJPEGs(for items: [PhotoItem], look: ExportLook? = nil) async throws -> [URL] {
        let folder = exportRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let jobs = uniqueJobs(for: items)

        return try await withThrowingTaskGroup(of: (Int, URL).self) { group in
            for (index, job) in jobs.enumerated() {
                group.addTask {
                    (index, try makeJPEG(for: job.item, named: job.name, preset: look?.preset(for: job.item), in: folder))
                }
            }
            var results = [URL?](repeating: nil, count: jobs.count)
            for try await (index, url) in group {
                results[index] = url
            }
            return results.compactMap(\.self)
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

    private static func makeJPEG(for item: PhotoItem, named name: String, preset: DevelopPreset?, in folder: URL) throws -> URL {
        try Task.checkCancellation()
        // sRGB, not the screen's colour space: the JPEG goes to other devices.
        guard var image = ImageDecoder.decode(item.url, maxPixelSize: maxPixelSize, forDisplay: false) else {
            throw ShareError.decodeFailed(item.fileName)
        }
        if let preset {
            try Task.checkCancellation()
            guard let rendered = PresetRenderer.export(image, preset: preset) else {
                throw ShareError.writeFailed(item.fileName)
            }
            image = rendered
        }

        let destinationURL = folder.appending(path: name)
        // GPS deliberately not copied.
        try ImageWriter.write(image, to: destinationURL, original: item.url, quality: quality, keepsLocation: false)
        return destinationURL
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
