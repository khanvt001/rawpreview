//
//  LibraryViewModel.swift
//  rawpreview
//

import AppKit
import Observation

/// App-wide state: available volumes and the currently selected source folder.
/// Scanning, filtering, selection and ratings are added in later phases.
@Observable
final class LibraryViewModel {
    private(set) var volumes: [VolumeInfo] = []
    private(set) var sourceURL: URL?

    @ObservationIgnored private let volumeService = VolumeService()
    @ObservationIgnored private var mountObservers: [any NSObjectProtocol] = []

    init() {
        observeMounts()
    }

    /// The volume that contains `sourceURL` (deepest match wins, so an SD card
    /// beats the boot volume mounted at `/`).
    var selectedVolumeID: VolumeInfo.ID? {
        guard let sourceURL else { return nil }
        return volumes
            .filter { sourceURL.isContained(in: $0.url) }
            .max { $0.url.pathComponents.count < $1.url.pathComponents.count }?
            .id
    }

    func refreshVolumes() async {
        volumes = await volumeService.mountedVolumes()
        // Auto-pick the first card on launch / insert so the user can start immediately.
        if sourceURL == nil, let card = volumes.first(where: \.isRemovable) {
            sourceURL = card.preferredSourceURL
        }
    }

    func selectVolume(id: VolumeInfo.ID?) {
        guard let volume = volumes.first(where: { $0.id == id }) else { return }
        sourceURL = volume.preferredSourceURL
    }

    func setSource(_ url: URL) {
        sourceURL = url
    }

    /// Lets the user pick any folder. Not needed for permissions (the app is not
    /// sandboxed), only for navigating to a folder that isn't a volume root.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.directoryURL = sourceURL ?? URL(filePath: "/Volumes", directoryHint: .isDirectory)
        if panel.runModal() == .OK, let url = panel.url {
            sourceURL = url
        }
    }

    // MARK: - Mount / unmount

    private func observeMounts() {
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let volumeURL = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
                let didUnmount = note.name == NSWorkspace.didUnmountNotification
                MainActor.assumeIsolated {
                    self?.handleMountChange(volumeURL: volumeURL, didUnmount: didUnmount)
                }
            }
            mountObservers.append(token)
        }
    }

    private func handleMountChange(volumeURL: URL?, didUnmount: Bool) {
        if didUnmount, let volumeURL, let sourceURL, sourceURL.isContained(in: volumeURL) {
            self.sourceURL = nil
        }
        Task { await refreshVolumes() }
    }
}
