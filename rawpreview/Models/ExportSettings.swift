//
//  ExportSettings.swift
//  rawpreview
//

import UniformTypeIdentifiers

/// The Export dialog's choices; remembered across launches.
nonisolated struct ExportSettings: Codable, Equatable, Sendable {
    enum Format: String, Codable, CaseIterable, Identifiable, Sendable {
        case jpeg, heif, png

        var id: Self { self }

        var title: String {
            switch self {
            case .jpeg: "JPEG"
            case .heif: "HEIF"
            case .png: "PNG"
            }
        }

        var fileExtension: String {
            switch self {
            case .jpeg: "jpg"
            case .heif: "heic"
            case .png: "png"
            }
        }

        var type: UTType {
            switch self {
            case .jpeg: .jpeg
            case .heif: .heic
            case .png: .png
            }
        }

        var isLossy: Bool {
            self != .png
        }
    }

    var format = Format.jpeg
    /// 0.5…1; JPEG and HEIF only.
    var quality = 0.92
    /// 16 bits per channel; PNG only.
    var uses16Bit = false
    /// Longest side in pixels; `nil` for full size.
    var longEdge: Int?
    /// Copy GPS from the original.
    var keepsLocation = true
    /// Apply the chosen preset and each photo's edits.
    var appliesLook = true

    static let longEdgeChoices = [4096, 3072, 2048, 1600]

    /// Whether the file is written with 16 bits per channel.
    var writes16Bit: Bool {
        format == .png && uses16Bit
    }

    /// Upper bound for an exported file's size as a multiple of the file it
    /// comes from (a RAW or the camera's JPEG), for the free-space check.
    /// Measured on 20 MP Nikon files: an 8-bit PNG is ~1.5–2× the NEF.
    var sizeFactor: Double {
        switch format {
        case .jpeg, .heif: 1
        case .png: uses16Bit ? 5 : 2.5
        }
    }
}
