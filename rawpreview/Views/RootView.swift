//
//  RootView.swift
//  rawpreview
//

import SwiftUI

struct RootView: View {
    @Environment(LibraryViewModel.self) private var library

    var body: some View {
        NavigationSplitView {
            SourceSidebar()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Open Folder…", systemImage: "folder.badge.plus") {
                    library.chooseFolder()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
        .task {
            await library.refreshVolumes()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let sourceURL = library.sourceURL {
            // Replaced by the photo grid in Phase 3.
            ContentUnavailableView(
                sourceURL.lastPathComponent,
                systemImage: "photo.on.rectangle.angled",
                description: Text(sourceURL.path(percentEncoded: false))
            )
            .navigationTitle(sourceURL.lastPathComponent)
        } else {
            ContentUnavailableView(
                "No Source Selected",
                systemImage: "sdcard",
                description: Text("Insert an SD card or choose a folder to start previewing.")
            )
            .navigationTitle("RawPreview")
        }
    }
}

private struct SourceSidebar: View {
    @Environment(LibraryViewModel.self) private var library

    var body: some View {
        let selection = Binding(
            get: { library.selectedVolumeID },
            set: { library.selectVolume(id: $0) }
        )
        let cards = library.volumes.filter(\.isRemovable)
        let others = library.volumes.filter { !$0.isRemovable }

        List(selection: selection) {
            if !cards.isEmpty {
                Section("Cards") {
                    ForEach(cards) { VolumeRow(volume: $0) }
                }
            }
            Section("Volumes") {
                ForEach(others) { VolumeRow(volume: $0) }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct VolumeRow: View {
    let volume: VolumeInfo

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(volume.name)
                if let free = volume.availableCapacity {
                    Text("\(free.formatted(.byteCount(style: .file))) free")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: volume.isRemovable ? "sdcard" : "internaldrive")
        }
        .tag(volume.id)
    }
}

#Preview {
    RootView()
        .environment(LibraryViewModel())
}
