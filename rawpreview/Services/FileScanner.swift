//
//  FileScanner.swift
//  rawpreview
//

import Foundation

/// Walks a source folder and returns every previewable file, sorted by capture order.
nonisolated struct FileScanner: Sendable {
    private static let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey,
        .fileSizeKey,
        .creationDateKey,
    ]

    @concurrent
    func scan(_ root: URL) async throws -> [PhotoItem] {
        try Self.collect(in: root)
    }

    /// Synchronous on purpose: `NSDirectoryEnumerator` iteration is unavailable in
    /// async contexts, and the caller already guarantees we're off the main actor.
    private static func collect(in root: URL) throws -> [PhotoItem] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let keySet = Set(resourceKeys)
        var items: [PhotoItem] = []
        var visited = 0

        while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited.isMultiple(of: 256) { try Task.checkCancellation() }

            // Sidecars (.xmp), camera databases (.DAT) etc. are not shown.
            guard MediaKind(fileExtension: url.pathExtension) != .other,
                  let values = try? url.resourceValues(forKeys: keySet),
                  values.isRegularFile == true
            else { continue }

            items.append(PhotoItem(
                url: url,
                fileSize: Int64(values.fileSize ?? 0),
                creationDate: values.creationDate
            ))
        }

        // Camera file dates track capture time; the name breaks ties (and keeps
        // RAW+JPEG pairs adjacent) without an expensive EXIF read per file.
        return items.sorted { lhs, rhs in
            switch (lhs.creationDate, rhs.creationDate) {
            case let (l?, r?) where l != r: l < r
            default: lhs.fileName.localizedStandardCompare(rhs.fileName) == .orderedAscending
            }
        }
    }
}
