//
//  MediaKind.swift
//  rawpreview
//

import Foundation

/// Broad category of a file found on the source volume, derived from its extension.
nonisolated enum MediaKind: String, Sendable, Hashable, CaseIterable {
    case raw
    case jpeg
    case heif
    case video
    case other

    static let rawExtensions: Set<String> = [
        "nef", "nrw",          // Nikon
        "cr2", "cr3", "crw",   // Canon
        "arw", "srf", "sr2",   // Sony
        "raf",                 // Fujifilm
        "orf",                 // OM System / Olympus
        "rw2",                 // Panasonic
        "pef",                 // Pentax
        "srw",                 // Samsung
        "3fr", "fff",          // Hasselblad
        "iiq",                 // Phase One
        "rwl",                 // Leica
        "x3f",                 // Sigma
        "dng",                 // Adobe / Leica / phones
    ]
    static let jpegExtensions: Set<String> = ["jpg", "jpeg"]
    static let heifExtensions: Set<String> = ["heic", "heif", "hif"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mts", "m2ts"]

    init(fileExtension ext: String) {
        let ext = ext.lowercased()
        if Self.rawExtensions.contains(ext) {
            self = .raw
        } else if Self.jpegExtensions.contains(ext) {
            self = .jpeg
        } else if Self.heifExtensions.contains(ext) {
            self = .heif
        } else if Self.videoExtensions.contains(ext) {
            self = .video
        } else {
            self = .other
        }
    }

    /// Whether ImageIO can produce a thumbnail / preview for this kind.
    var isImage: Bool {
        switch self {
        case .raw, .jpeg, .heif: true
        case .video, .other: false
        }
    }
}
