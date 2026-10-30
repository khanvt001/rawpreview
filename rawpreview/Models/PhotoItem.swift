//
//  PhotoItem.swift
//  rawpreview
//

import Foundation

/// A single file on the source volume. Immutable and `Sendable` so it can be
/// handed freely to background services (scanner, thumbnailer, copier).
nonisolated struct PhotoItem: Identifiable, Hashable, Sendable {
    let url: URL
    let fileSize: Int64
    let creationDate: Date?

    var id: URL { url }
    var fileName: String { url.lastPathComponent }
    var baseName: String { url.deletingPathExtension().lastPathComponent }
    /// Upper-cased extension, e.g. `"NEF"`, used for the extension filter chips.
    var fileExtension: String { url.pathExtension.uppercased() }
    var kind: MediaKind { MediaKind(fileExtension: url.pathExtension) }

    /// Location of the XMP sidecar Lightroom / Capture One look for: `IMG_0001.xmp`.
    var sidecarURL: URL { url.deletingPathExtension().appendingPathExtension("xmp") }

    init(url: URL, fileSize: Int64, creationDate: Date?) {
        self.url = url
        self.fileSize = fileSize
        self.creationDate = creationDate
    }
}
