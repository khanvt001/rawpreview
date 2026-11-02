//
//  ExportOptionsView.swift
//  rawpreview
//

import SwiftUI

/// The Export dialog, shown in the copy sheet before an export starts:
/// format, quality, size, whether to apply the preset and edits, location
/// data and destination. Choices are remembered.
struct ExportOptionsView: View {
    @Environment(LibraryViewModel.self) private var library
    @AppStorage(ProcessingSource.defaultsKey) private var processingSource = ProcessingSource.embedded.rawValue

    var body: some View {
        @Bindable var library = library
        let settings = library.exportSettings
        let shots = Set(library.exportItems.filter(\.kind.isImage).map(\.sidecarURL)).count

        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text("Export \(shots) Photos")
                    .font(.headline)
            } icon: {
                Image(systemName: "square.and.arrow.up.on.square")
            }

            Form {
                LabeledContent("Processing source", value: (ProcessingSource(rawValue: processingSource) ?? .embedded).title)
                Picker("Format", selection: $library.exportSettings.format) {
                    ForEach(ExportSettings.Format.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                if settings.format.isLossy {
                    LabeledContent("Quality") {
                        HStack {
                            Slider(value: $library.exportSettings.quality, in: 0.5...1, step: 0.01)
                            Text("\(Int((settings.quality * 100).rounded()))")
                                .monospacedDigit()
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                } else {
                    Picker("Bit Depth", selection: $library.exportSettings.uses16Bit) {
                        Text("8-bit").tag(false)
                        Text("16-bit").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .help("16-bit keeps smooth gradients after strong edits, at about twice the file size")
                }

                Picker("Size", selection: $library.exportSettings.longEdge) {
                    Text("Full Size").tag(Int?.none)
                    ForEach(ExportSettings.longEdgeChoices, id: \.self) { pixels in
                        Text("\(pixels) px long edge").tag(Int?.some(pixels))
                    }
                }

                if let look = library.pendingExportLook {
                    Toggle("Apply \(look.title)", isOn: $library.exportSettings.appliesLook)
                }
                Toggle("Include Location", isOn: $library.exportSettings.keepsLocation)
                    .help("Copy GPS coordinates from the originals")
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            Text(note(settings))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(library.copyDestination?.path(percentEncoded: false) ?? String(localized: "No folder chosen"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(library.copyDestination == nil ? .secondary : .primary)
                Spacer()
                Button("Change…") { library.chooseCopyDestination() }
            }
            .font(.callout)
            Toggle("Sort into Date Folders", isOn: $library.copiesIntoDateFolders)
                .font(.callout)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { library.dismissCopyResult() }
                    .keyboardShortcut(.cancelAction)
                Button("Share…") {
                    // The picker opens over the main window once the files
                    // are ready: this sheet is gone by then.
                    library.startCopy(
                        export: CopyService.Export(look: library.pendingExportLook, settings: settings),
                        sharingFrom: .pointer(in: NSApp.mainWindow)
                    )
                }
                .disabled(shots == 0)
                .help("Export with these options into a temporary folder, then share or AirDrop the files without keeping them")
                Button("Export") {
                    library.startCopy(export: CopyService.Export(look: library.pendingExportLook, settings: settings))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(shots == 0)
            }
        }
    }

    private func note(_ settings: ExportSettings) -> String {
        let source = String(localized: "RAW files are exported from the camera's full-size embedded preview.")
        switch settings.format {
        case .jpeg:
            return String(localized: "Smallest files, readable everywhere. 90 or above keeps compression hard to see. \(source)")
        case .heif:
            return String(localized: "About half the size of a JPEG at the same quality; best for Apple devices. \(source)")
        case .png:
            // Measured on 20 MP Nikon files: 8-bit 12 MB for a sky-heavy photo, more for busy ones.
            let size = settings.uses16Bit ? "25–70 MB" : "10–35 MB"
            return String(localized: "Lossless, no compression artifacts. Around \(size) per photo at full size. \(source)")
        }
    }
}
