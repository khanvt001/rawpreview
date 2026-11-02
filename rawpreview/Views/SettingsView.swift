//
//  SettingsView.swift
//  rawpreview
//

import SwiftUI

/// The app's Settings window (⌘,).
struct SettingsView: View {
    @AppStorage(Analytics.enabledKey) private var sharesUsage = true
    @AppStorage(LibraryViewModel.cardDeleteErasesKey) private var cardDeleteErases = true
    @AppStorage(ShareService.maxPixelSizeKey) private var shareLongEdge = 2048
    @AppStorage("gridShowsInfo") private var gridShowsInfo = true
    @AppStorage(ProcessingSource.defaultsKey) private var processingSource = ProcessingSource.embedded.rawValue
    @AppStorage(ProcessingSource.fallbackKey) private var rawFallbacks = Data()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section {
                Picker("Image processing source", selection: $processingSource) {
                    ForEach(ProcessingSource.allCases, id: \.rawValue) { source in
                        Text(source.title).tag(source.rawValue)
                    }
                }
                if !ProcessingConfiguration.decodeFallbacks(rawFallbacks).isEmpty {
                    Button("Reset RAW Fallback Choices") { rawFallbacks = Data() }
                }
            } footer: {
                Text("Presets, edits and exports use this source. Fast uses the camera JPEG for paired shots. RAW can look different; unsupported files require choosing a fallback. Copying or sharing originals keeps the original files.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Delete on memory cards", selection: $cardDeleteErases) {
                    Text("Erase at once").tag(true)
                    Text("Move to Trash").tag(false)
                }
            } footer: {
                Text("Erasing frees the card's space straight away. Files moved to a card's Trash only go once you empty the Trash in Finder. On other drives, deleted files always go to the Trash.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Quick share size", selection: $shareLongEdge) {
                    ForEach(ShareService.maxPixelSizeChoices, id: \.self) { pixels in
                        Text("\(pixels) px long edge").tag(pixels)
                    }
                }
                Toggle("Show file name and exposure on thumbnails", isOn: $gridShowsInfo)
            } footer: {
                Text("Quick share is Share as JPEGs and AirDrop as JPEGs. Export lets you choose the size each time.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Share anonymous usage statistics", isOn: $sharesUsage)
            } footer: {
                Text("Counts app launches and how many photos are copied or shared, with the app and macOS version. Never file names, folders or photos.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Enjoying RawPreview?") {
                    Button("Buy Me a Coffee…") { openWindow(id: SupportView.windowID) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: sharesUsage) { _, on in
            if on { Analytics.start() }
        }
    }
}
