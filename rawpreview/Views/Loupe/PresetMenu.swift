//
//  PresetMenu.swift
//  rawpreview
//

import SwiftUI
import UniformTypeIdentifiers

/// Toolbar menu for choosing, importing and toggling Lightroom presets.
struct PresetMenu: View {
    @Environment(PresetStore.self) private var store
    @State private var isImporting = false

    var body: some View {
        @Bindable var store = store

        Menu {
            Picker("Preset", selection: $store.selectedID) {
                Text("None").tag(String?.none)
                ForEach(store.presets) { preset in
                    Text(preset.title).tag(Optional(preset.id))
                }
            }
            .pickerStyle(.inline)

            Divider()
            Toggle("Show Preset (\\)", isOn: $store.isEnabled)
                .disabled(store.selectedPreset == nil)
            if let preset = store.selectedPreset, !preset.unsupportedSettings.isEmpty {
                Text("Not previewed: \(preset.unsupportedSettings.joined(separator: ", "))")
            }

            Divider()
            Button("Import Presets…") { isImporting = true }
            if let preset = store.selectedPreset {
                Button("Remove “\(preset.title)”") { store.remove(preset) }
            }
            Button("Show Presets Folder") { store.revealFolder() }
        } label: {
            Label("Preset", systemImage: store.activePreset == nil ? "camera.filters" : "camera.filters.fill")
        }
        .focusable(false)
        .help("Preview a Lightroom preset (.lrtemplate / .xmp) · \\ shows before / after")
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: DevelopPreset.fileExtensions.compactMap { UTType(filenameExtension: $0) },
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): store.importPresets(from: urls)
            case .failure(let error): store.loadError = error.localizedDescription
            }
        }
        .alert(
            "Preset Problem",
            isPresented: Binding(
                get: { store.loadError != nil },
                set: { if !$0 { store.loadError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.loadError ?? "")
        }
    }
}
