//
//  MetadataInspector.swift
//  rawpreview
//

import SwiftUI

/// Right sidebar in Single Image mode: a readable summary on top, then every
/// field ImageIO exposes, grouped by EXIF / TIFF / maker notes etc.
struct MetadataInspector: View {
    let item: PhotoItem
    let isChecked: Bool
    let rating: Rating

    @State private var exif: ExifInfo?
    @State private var sections: [MetadataSection] = []

    var body: some View {
        Form {
            Section("Photo") {
                LabeledContent("File", value: item.fileName)
                LabeledContent("Size", value: item.fileSize.formatted(.byteCount(style: .file)))
                if let size = exif?.orientedPixelSize {
                    LabeledContent("Dimensions") {
                        Text("\(Int(size.width)) × \(Int(size.height))")
                    }
                }
                LabeledContent("Rating") {
                    if rating.isRated {
                        RatingStarsView(rating: rating, size: 11)
                    } else {
                        Text("None")
                    }
                }
                LabeledContent("Copy", value: isChecked ? "Marked" : "Not marked")
            }

            if let exif {
                Section("Capture") {
                    row("Camera", [exif.cameraMake, exif.cameraModel].compactMap(\.self).joined(separator: " "))
                    row("Lens", exif.lensModel)
                    row("Aperture", exif.apertureText)
                    row("Shutter", exif.shutterText)
                    row("ISO", exif.iso.map(String.init))
                    row("Focal Length", exif.focalLengthText)
                    row("Exposure Bias", exif.exposureBiasText)
                    row("Captured", exif.captureDate?.formatted(date: .abbreviated, time: .standard))
                }
            }

            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.rows, id: \.self) { entry in
                        LabeledContent(entry.label) {
                            Text(entry.value)
                                .textSelection(.enabled)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .font(.callout)
        .task(id: item.id) {
            exif = MetadataService.shared.cachedExif(for: item.url)
            sections = []
            guard item.kind.isImage else { return }
            if exif == nil {
                exif = await MetadataService.shared.exif(for: item.url)
            }
            let loaded = await MetadataService.shared.detailedMetadata(for: item.url)
            if !Task.isCancelled {
                sections = loaded
            }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label, value: value)
        }
    }
}
