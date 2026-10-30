//
//  LibraryViewModel.swift
//  rawpreview
//

import AppKit
import Observation

/// App-wide state: available volumes, the selected source folder, its files and
/// the user's culling decisions (checked for copy, star ratings).
@Observable
final class LibraryViewModel {
    enum ViewMode {
        case grid
        case loupe
    }

    enum MoveDirection {
        case left, right, up, down
    }

    /// Where a photo's rating is kept.
    enum RatingStorage: Equatable {
        /// Written to this sidecar, which Lightroom / Capture One read.
        case sidecar(URL)
        /// No RAW file in the shot (e.g. a lone JPEG): Lightroom ignores
        /// sidecars for those, so the rating lives only in this session.
        case sessionOnly
    }

    private(set) var volumes: [VolumeInfo] = []
    private(set) var sourceURL: URL? {
        didSet {
            if sourceURL != oldValue { rescan() }
        }
    }

    private(set) var items: [PhotoItem] = [] {
        didSet { updateVisibleItems() }
    }
    private(set) var isScanning = false
    private(set) var scanError: String?

    /// `items` minus hidden extensions. Stored, not computed, so the grid's
    /// `ForEach` doesn't refilter on every body evaluation.
    private(set) var visibleItems: [PhotoItem] = []
    /// Upper-cased extensions (e.g. `"MP4"`) excluded from `visibleItems`.
    /// Remembered across launches: hiding videos once should stick.
    private(set) var hiddenExtensions: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(hiddenExtensions.sorted(), forKey: Self.hiddenExtensionsKey)
            updateVisibleItems()
        }
    }

    var viewMode: ViewMode = .grid

    /// Single Image mode's EXIF sidebar; remembered across launches.
    var showsInspector: Bool = UserDefaults.standard.object(forKey: "showsInspector") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsInspector, forKey: "showsInspector") }
    }
    /// Latest zoom command for the loupe (Z, ⌘+, ⌘−, ⌘0).
    private(set) var zoomRequest: ZoomRequest?

    /// The image the keyboard acts on and the loupe shows.
    var focusedID: PhotoItem.ID?
    /// Files ticked for batch copy.
    private(set) var checkedIDs: Set<PhotoItem.ID> = []
    /// Keyed by sidecar URL so both files of a RAW+JPEG pair share a rating.
    private(set) var ratings: [URL: Rating] = [:]
    /// Last sidecar write failure (e.g. card write-protected), for an alert.
    var ratingSaveError: String?
    /// Sidecars of shots that include a RAW file, i.e. the ones worth writing.
    @ObservationIgnored private var rawSidecars: Set<URL> = []
    /// Tail of the sidecar write chain; each write waits for the previous one so
    /// quick 3-then-5 presses can't land on disk as 3.
    @ObservationIgnored private var lastSidecarWrite: Task<Void, Never>?
    /// Columns currently laid out by the grid; Up/Down move by this many items.
    var columnCount = 1

    @ObservationIgnored private let volumeService = VolumeService()
    @ObservationIgnored private let scanner = FileScanner()
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var mountObservers: [any NSObjectProtocol] = []

    private static let hiddenExtensionsKey = "hiddenExtensions"

    init() {
        hiddenExtensions = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenExtensionsKey) ?? [])
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

    /// File count per extension (e.g. `["NEF": 481, "JPG": 484]`), for filter chips.
    var extensionCounts: [(ext: String, count: Int)] {
        Dictionary(grouping: items, by: \.fileExtension)
            .map { (ext: $0.key, count: $0.value.count) }
            .sorted { $0.ext < $1.ext }
    }

    var focusedItem: PhotoItem? {
        focusedIndex.map { visibleItems[$0] }
    }

    var focusedIndex: Int? {
        guard let focusedID else { return nil }
        return visibleItems.firstIndex { $0.id == focusedID }
    }

    // MARK: - Filtering

    func isExtensionHidden(_ ext: String) -> Bool {
        hiddenExtensions.contains(ext)
    }

    func toggleExtension(_ ext: String) {
        if hiddenExtensions.remove(ext) == nil {
            hiddenExtensions.insert(ext)
        }
    }

    func showAllExtensions() {
        hiddenExtensions = []
    }

    // MARK: - Navigation

    func toggleViewMode() {
        guard focusedID != nil else { return }
        viewMode = viewMode == .grid ? .loupe : .grid
    }

    func requestZoom(_ command: ZoomRequest.Command) {
        guard viewMode == .loupe else { return }
        zoomRequest = ZoomRequest(command: command, serial: (zoomRequest?.serial ?? 0) + 1)
    }

    /// Arrow-key movement. In the grid Up/Down jump a row; in the loupe (one
    /// image, horizontal filmstrip) they act like Left/Right.
    func moveFocus(_ direction: MoveDirection) {
        guard !visibleItems.isEmpty else { return }
        guard let index = focusedIndex else {
            focusedID = visibleItems.first?.id
            return
        }
        let row = viewMode == .grid ? max(1, columnCount) : 1
        let delta = switch direction {
        case .left: -1
        case .right: 1
        case .up: -row
        case .down: row
        }
        let target = index + delta
        // A row jump past either end stays put, like Finder; a single step clamps.
        guard visibleItems.indices.contains(target) else { return }
        focusedID = visibleItems[target].id
    }

    /// Visible items within `radius` of `id`, nearest first, for prefetching.
    func neighbours(of id: PhotoItem.ID, radius: Int) -> [PhotoItem] {
        guard let index = visibleItems.firstIndex(where: { $0.id == id }) else { return [] }
        return (1...max(1, radius)).flatMap { offset in
            [index + offset, index - offset].filter(visibleItems.indices.contains).map { visibleItems[$0] }
        }
    }

    // MARK: - Culling

    func isChecked(_ id: PhotoItem.ID) -> Bool {
        checkedIDs.contains(id)
    }

    func toggleChecked(_ id: PhotoItem.ID) {
        if checkedIDs.remove(id) == nil {
            checkedIDs.insert(id)
        }
    }

    func rating(for id: PhotoItem.ID) -> Rating {
        ratings[PhotoItem.sidecarURL(for: id)] ?? .none
    }

    func ratingStorage(for id: PhotoItem.ID) -> RatingStorage {
        let sidecar = PhotoItem.sidecarURL(for: id)
        return rawSidecars.contains(sidecar) ? .sidecar(sidecar) : .sessionOnly
    }

    /// Updates the UI immediately; the sidecar write happens in the background.
    func setRating(_ rating: Rating, for id: PhotoItem.ID) {
        let sidecar = PhotoItem.sidecarURL(for: id)
        guard ratings[sidecar, default: .none] != rating else { return }
        ratings[sidecar] = rating.isRated ? rating : nil

        guard rawSidecars.contains(sidecar) else { return }
        let previous = lastSidecarWrite
        lastSidecarWrite = Task {
            await previous?.value
            do {
                try await XMPService.shared.setRating(rating, sidecar: sidecar)
            } catch {
                ratingSaveError = "Couldn't save the rating for \(id.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    func toggleCheckedForFocused() {
        if let focusedID { toggleChecked(focusedID) }
    }

    func setRatingForFocused(_ rating: Rating) {
        if let focusedID { setRating(rating, for: focusedID) }
    }

    private func updateVisibleItems() {
        visibleItems = hiddenExtensions.isEmpty
            ? items
            : items.filter { !hiddenExtensions.contains($0.fileExtension) }

        guard !visibleItems.isEmpty else {
            focusedID = nil
            viewMode = .grid
            return
        }
        guard let focusedID, let allIndex = items.firstIndex(where: { $0.id == focusedID }) else {
            focusedID = visibleItems.first?.id
            return
        }
        // If the focused file was just filtered out, move to the nearest visible
        // file after it (or before, at the end) instead of jumping to the top.
        if hiddenExtensions.contains(items[allIndex].fileExtension) {
            let after = items[allIndex...].first { !hiddenExtensions.contains($0.fileExtension) }
            let before = items[..<allIndex].last { !hiddenExtensions.contains($0.fileExtension) }
            self.focusedID = (after ?? before)?.id
        }
    }

    func rescan() {
        scanTask?.cancel()
        items = []
        scanError = nil
        focusedID = nil
        viewMode = .grid
        checkedIDs = []
        ratings = [:]
        rawSidecars = []

        guard let sourceURL else {
            isScanning = false
            clearCaches()
            return
        }

        isScanning = true
        scanTask = Task {
            do {
                let found = try await scanner.scan(sourceURL)
                let sidecars = Set(found.filter { $0.kind == .raw }.map(\.sidecarURL))
                // Pick up ratings made earlier (here, in Lightroom or Capture One)
                // before showing the grid, so stars appear with the thumbnails.
                let existing = await XMPService.shared.readRatings(Array(sidecars))
                guard !Task.isCancelled else { return }
                rawSidecars = sidecars
                ratings = existing
                items = found
            } catch is CancellationError {
                return
            } catch {
                scanError = error.localizedDescription
            }
            isScanning = false
        }
    }

    private func clearCaches() {
        ThumbnailService.shared.removeAll()
        PreviewService.shared.removeAll()
        MetadataService.shared.removeAll()
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
