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
        .background(WindowFrameGuard())
        .background(ScreenColorSpaceObserver())
        .task {
            await library.refreshVolumes()
        }
        .sheet(isPresented: Binding(
            get: { library.copyState != .idle },
            set: { if !$0 { library.dismissCopyResult() } }
        )) {
            CopySheet()
                .environment(library)
                .interactiveDismissDisabled(library.isCopying)
        }
        .alert(
            "Couldn't Eject",
            isPresented: Binding(
                get: { library.ejectError != nil },
                set: { if !$0 { library.ejectError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.ejectError ?? "")
        }
        .alert(
            "Rating Not Saved",
            isPresented: Binding(
                get: { library.ratingSaveError != nil },
                set: { if !$0 { library.ratingSaveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.ratingSaveError ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let sourceURL = library.sourceURL {
            Group {
                if library.isScanning {
                    ProgressView("Scanning \(sourceURL.lastPathComponent)…")
                } else if let error = library.scanError {
                    ContentUnavailableView("Couldn't Read Folder", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if library.items.isEmpty {
                    ContentUnavailableView(
                        "No Photos",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("This folder has no RAW, JPEG, HEIF or video files.")
                    )
                } else {
                    LibraryContentView()
                }
            }
            .navigationTitle(sourceURL.lastPathComponent)
            .navigationSubtitle(sourceURL.path(percentEncoded: false))
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
                    ForEach(cards) { volume in
                        VolumeRow(volume: volume)
                            .contextMenu {
                                Button("Eject “\(volume.name)”") { library.eject(volume) }
                            }
                    }
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
    @Environment(LibraryViewModel.self) private var library
    let volume: VolumeInfo

    var body: some View {
        HStack(spacing: 4) {
            label
            if volume.isRemovable {
                Spacer(minLength: 0)
                if library.ejectingVolumeID == volume.id {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Eject", systemImage: "eject.fill") { library.eject(volume) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Eject “\(volume.name)”")
                }
            }
        }
        .tag(volume.id)
    }

    private var label: some View {
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
    }
}

#Preview {
    RootView()
        .environment(LibraryViewModel())
}
