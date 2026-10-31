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
                // On the detail column, not next to the copy sheet: two
                // `.sheet`s on one view fight over presentation.
                .sheet(isPresented: Binding(
                    get: { library.pendingDeletion != nil },
                    set: { if !$0 { library.pendingDeletion = nil } }
                )) {
                    DeleteSheet()
                        .environment(library)
                }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Open Folder…", systemImage: "folder") {
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
            "Couldn't Delete",
            isPresented: Binding(
                get: { library.deleteError != nil },
                set: { if !$0 { library.deleteError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.deleteError ?? "")
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
            ContentUnavailableView {
                Label("No Source Selected", systemImage: "sdcard")
            } description: {
                Text("Insert an SD card or choose a folder to start previewing.")
            } actions: {
                Button("Open Folder…") { library.chooseFolder() }
            }
            .navigationTitle("RawPreview")
        }
    }
}

private struct SourceSidebar: View {
    @Environment(LibraryViewModel.self) private var library

    var body: some View {
        let recents = library.availableRecentFolders
        // Volume and recent-folder rows are both tagged by URL.
        let selection = Binding<URL?>(
            get: {
                if let source = library.sourceURL, recents.contains(source) { return source }
                return library.selectedVolumeID
            },
            set: { url in
                guard let url else { return }
                if recents.contains(url) {
                    library.openRecentFolder(url)
                } else {
                    library.selectVolume(id: url)
                }
            }
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
            if !recents.isEmpty {
                Section("Recent Folders") {
                    ForEach(recents, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: "folder")
                            .help(url.path(percentEncoded: false))
                            .tag(url)
                            .contextMenu {
                                Button("Show in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                                Button("Remove from Recents") { library.removeRecentFolder(url) }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { SidebarFooter() }
    }
}

/// App version and a quiet support link on one line, pinned under the
/// volumes; the support window is also in the app menu and Settings.
private struct SidebarFooter: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 8) {
            Button("Version \(AppInfo.version)") { AppInfo.showAboutPanel() }
                .buttonStyle(.plain)
                .help("About RawPreview")
            Spacer()
            Button("Buy Me a Coffee", systemImage: "cup.and.saucer") {
                openWindow(id: SupportView.windowID)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .help("Support RawPreview")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
        .environment(PresetStore())
        .environment(EditStore())
}
