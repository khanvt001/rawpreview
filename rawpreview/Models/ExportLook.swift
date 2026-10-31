//
//  ExportLook.swift
//  rawpreview
//

import Foundation

/// What exported or shared JPEGs get applied: the chosen preset, plus each
/// shot's own Edit adjustments on top of it.
nonisolated struct ExportLook: Sendable {
    let preset: DevelopPreset?
    /// Light adjustments by shot (`PhotoItem.sidecarURL`), so a RAW+JPEG pair
    /// exported from either file gets them.
    let adjustments: [URL: LightAdjustments]

    /// `nil` when there is nothing to apply.
    init?(preset: DevelopPreset?, adjustments: [URL: LightAdjustments]) {
        guard preset != nil || !adjustments.isEmpty else { return nil }
        self.preset = preset
        self.adjustments = adjustments
    }

    /// The look for one photo; `nil` exports it as shot.
    func preset(for item: PhotoItem) -> DevelopPreset? {
        DevelopPreset.combining(preset, with: adjustments[item.sidecarURL] ?? LightAdjustments())
    }

    /// For "Export 3 JPEGs with …": "“Kodak Gold”", "Edits" or
    /// "“Kodak Gold” + Edits".
    var title: String {
        switch (preset, adjustments.isEmpty) {
        case (let preset?, true): "“\(preset.title)”"
        case (let preset?, false): "“\(preset.title)” + Edits"
        case (nil, _): "Edits"
        }
    }
}
