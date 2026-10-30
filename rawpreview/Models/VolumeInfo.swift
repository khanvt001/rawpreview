//
//  VolumeInfo.swift
//  rawpreview
//

import Foundation

/// A mounted volume that can serve as a photo source (typically an SD card).
nonisolated struct VolumeInfo: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isRemovable: Bool
    let totalCapacity: Int64?
    let availableCapacity: Int64?

    var id: URL { url }

    /// Camera cards put images under `DCIM`; jump straight there when present.
    var preferredSourceURL: URL {
        let dcim = url.appending(path: "DCIM", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: dcim.path(percentEncoded: false)) ? dcim : url
    }
}
