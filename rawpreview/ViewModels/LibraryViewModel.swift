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

    enum CopyState: Equatable {
        case idle
        case running(CopyService.Progress)
        case finished(CopyService.Report)
        case failed(String)
    }

    /// Star filter chip: which ratings `visibleItems` keeps.
    enum RatingFilter: Hashable {
        case unrated
        case atLeast(Rating)

        func matches(_ rating: Rating) -> Bool {
            switch self {
            case .unrated: !rating.isRated
            case .atLeast(let minimum): rating >= minimum
            }
        }
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
            guard sourceURL != oldValue else { return }
            searchText = ""
            rescan()
        }
    }

    private(set) var items: [PhotoItem] = [] {
        didSet { updateVisibleItems() }
    }
    private(set) var isScanning = false
    private(set) var scanError: String?

    /// `items` minus hidden extensions, search misses, and files the Marked or
    /// star filter excludes. Stored, not computed, so the grid's
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
    /// Grid search box text; matches file names case- and diacritic-insensitively.
    var searchText = "" {
        didSet {
            if searchText != oldValue { updateVisibleItems() }
        }
    }
    /// While the search box has the keyboard, filtering must not pull key
    /// focus back to the grid.
    var isSearchFocused = false

    var viewMode: ViewMode = .grid

    /// Single Image mode's sidebar; remembered across launches.
    var showsInspector: Bool = UserDefaults.standard.object(forKey: "showsInspector") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsInspector, forKey: "showsInspector") }
    }

    enum InspectorTab: String {
        case info
        case presets
    }

    /// Which page the sidebar shows; remembered across launches.
    var inspectorTab: InspectorTab = UserDefaults.standard.string(forKey: "inspectorTab").flatMap(InspectorTab.init) ?? .info {
        didSet { UserDefaults.standard.set(inspectorTab.rawValue, forKey: "inspectorTab") }
    }
    /// Folder marked files are copied into; remembered across launches.
    private(set) var copyDestination: URL? = UserDefaults.standard.string(forKey: "copyDestination")
        .map { URL(filePath: $0, directoryHint: .isDirectory) } {
        didSet { UserDefaults.standard.set(copyDestination?.path(percentEncoded: false), forKey: "copyDestination") }
    }
    /// Copy each shot into a `YYYY-MM-DD` subfolder of the destination;
    /// remembered across launches.
    var copiesIntoDateFolders: Bool = UserDefaults.standard.bool(forKey: "copiesIntoDateFolders") {
        didSet { UserDefaults.standard.set(copiesIntoDateFolders, forKey: "copiesIntoDateFolders") }
    }
    private(set) var copyState: CopyState = .idle
    /// The preset the current / last copy exported JPEGs with; `nil` when it
    /// copied the original files.
    private(set) var copyPreset: DevelopPreset?
    /// Why the last copy stopped early, when it wasn't the user's Cancel.
    private(set) var copyInterruption: String?
    /// Volume currently being ejected (for the sidebar spinner).
    private(set) var ejectingVolumeID: VolumeInfo.ID?
    var ejectError: String?
    @ObservationIgnored private var copyTask: Task<Void, Never>?
    @ObservationIgnored private let copier = CopyService()

    /// Latest zoom command for the loupe (Z, ⌘+, ⌘−, ⌘0).
    private(set) var zoomRequest: ZoomRequest?

    /// The image the keyboard acts on and the loupe shows.
    var focusedID: PhotoItem.ID?
    /// Files ticked for batch copy.
    private(set) var checkedIDs: Set<PhotoItem.ID> = [] {
        didSet {
            if showsOnlyChecked { updateVisibleItems() }
        }
    }
    /// Star filter; `nil` shows every rating.
    var ratingFilter: RatingFilter? {
        didSet {
            if ratingFilter != oldValue { updateVisibleItems() }
        }
    }
    /// "Marked" filter chip: narrows `visibleItems` to the ticked files.
    var showsOnlyChecked = false {
        didSet {
            if showsOnlyChecked != oldValue { updateVisibleItems() }
        }
    }
    /// Keyed by sidecar URL so both files of a RAW+JPEG pair share a rating.
    private(set) var ratings: [URL: Rating] = [:] {
        didSet {
            if ratingFilter != nil { updateVisibleItems() }
        }
    }
    /// Last sidecar write failure (e.g. card write-protected), for an alert.
    var ratingSaveError: String?
    /// Files waiting for the user to confirm Delete.
    var pendingDeletion: [PhotoItem]?
    /// Why the last Delete failed, for an alert.
    var deleteError: String?
    /// Delete sheet checkbox: also delete the other half of a RAW+JPEG pair;
    /// remembered across launches.
    var deletesPairedFiles: Bool = UserDefaults.standard.bool(forKey: "deletesPairedFiles") {
        didSet { UserDefaults.standard.set(deletesPairedFiles, forKey: "deletesPairedFiles") }
    }
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
        Task { await ShareService.purgeOldExports() }
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

    private func isVisible(_ item: PhotoItem) -> Bool {
        guard !hiddenExtensions.contains(item.fileExtension) else { return false }
        guard !showsOnlyChecked || checkedIDs.contains(item.id) else { return false }
        if let ratingFilter, !ratingFilter.matches(rating(for: item.id)) { return false }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || item.fileName.localizedStandardContains(query)
    }

    // MARK: - Navigation

    func toggleViewMode() {
        guard focusedID != nil else { return }
        viewMode = viewMode == .grid ? .loupe : .grid
    }

    /// I / P and the toolbar buttons: opens the sidebar on `tab`, or closes it
    /// if it's already showing that tab.
    func toggleInspector(_ tab: InspectorTab) {
        if showsInspector, inspectorTab == tab {
            showsInspector = false
        } else {
            inspectorTab = tab
            showsInspector = true
        }
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
        var target = index + delta
        // Down from a tile with nothing directly below it lands on the last
        // item when the last row is shorter, so the arrows can reach every
        // file. Otherwise a jump past either end stays put, like Finder.
        if direction == .down, target >= visibleItems.count, index / row < (visibleItems.count - 1) / row {
            target = visibleItems.count - 1
        }
        guard visibleItems.indices.contains(target) else { return }
        focusedID = visibleItems[target].id
    }

    /// The photos around the focused one, for the loupe's filmstrip. Bounded
    /// so the strip's layout cost doesn't grow with the size of the card.
    /// `radius` photos either side of the focused one, plus `extraBefore` /
    /// `extraAfter` more once the strip has been scrolled towards an end.
    func filmstripItems(radius: Int, extraBefore: Int = 0, extraAfter: Int = 0) -> ArraySlice<PhotoItem> {
        guard let index = focusedIndex else { return visibleItems.prefix(radius * 2 + 1 + extraAfter) }
        let lower = max(0, index - radius - extraBefore)
        let upper = min(visibleItems.count, index + radius + 1 + extraAfter)
        return visibleItems[lower..<upper]
    }

    /// Items just past the last visible one, for warming thumbnails before
    /// the user scrolls there: `rowsAhead` rows below and one row above.
    func prefetchCandidates(visible ids: [PhotoItem.ID], rowsAhead: Int) -> [PhotoItem] {
        let visibleSet = Set(ids)
        let indices = visibleItems.indices.filter { visibleSet.contains(visibleItems[$0].id) }
        guard let first = indices.first, let last = indices.last else { return [] }
        let row = max(1, columnCount)
        let below = (last + 1)..<min(visibleItems.count, last + 1 + row * rowsAhead)
        let above = max(0, first - row)..<first
        return (Array(below) + Array(above)).map { visibleItems[$0] }
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

    /// What a right-click (or the toolbar Share menu) acts on: every marked
    /// file when the clicked one is among several marked, otherwise just it.
    func actionTargets(for item: PhotoItem) -> [PhotoItem] {
        guard checkedIDs.contains(item.id), checkedIDs.count > 1 else { return [item] }
        return items.filter { checkedIDs.contains($0.id) }
    }

    func clearChecked() {
        checkedIDs = []
    }

    // MARK: - Delete

    /// ⌘⌫ / context menu / Single Image toolbar: asks before deleting
    /// (handled by `RootView`).
    func requestDelete(_ targets: [PhotoItem]) {
        guard !targets.isEmpty else { return }
        guard !isCopying else {
            deleteError = "A copy is in progress. Wait for it to finish, or cancel it, before deleting."
            return
        }
        pendingDeletion = targets
    }

    func requestDeleteForFocused() {
        if let focusedItem { requestDelete(actionTargets(for: focusedItem)) }
    }

    /// Same-name files of the same shots (the JPEG of a NEF and vice versa)
    /// not already in `targets`, including ones the filter hides.
    func pairedFiles(of targets: [PhotoItem]) -> [PhotoItem] {
        let ids = Set(targets.map(\.id))
        let shots = Set(targets.map(\.sidecarURL))
        return items.filter { !ids.contains($0.id) && shots.contains($0.sidecarURL) }
    }

    /// Delete sheet's button: the targets plus, when ticked, their pairs.
    func confirmDeletion() {
        guard let targets = pendingDeletion else { return }
        delete(deletesPairedFiles ? targets + pairedFiles(of: targets) : targets)
    }

    /// Permanently deletes `targets` (no Trash, so the card's space is freed
    /// at once). A RAW's sidecar goes too once no file of that shot is left.
    func delete(_ targets: [PhotoItem]) {
        pendingDeletion = nil
        let doomed = Set(targets.map(\.id))
        let remainingSidecars = Set(items.filter { !doomed.contains($0.id) }.map(\.sidecarURL))
        let orphanedSidecars = Set(targets.map(\.sidecarURL)).subtracting(remainingSidecars)

        Task {
            let failures = await Self.removeFiles(targets.map(\.url), sidecars: Array(orphanedSidecars))
            let deleted = doomed.subtracting(failures.map(\.url))

            // Land on the nearest surviving neighbour, not the top of the grid.
            if let focusedID, deleted.contains(focusedID), let index = focusedIndex {
                let after = visibleItems[index...].first { !deleted.contains($0.id) }
                let before = visibleItems[..<index].last { !deleted.contains($0.id) }
                self.focusedID = (after ?? before)?.id
            }
            checkedIDs.subtract(deleted)
            let keptSidecars = Set(failures.map { PhotoItem.sidecarURL(for: $0.url) })
            for sidecar in orphanedSidecars.subtracting(keptSidecars) {
                ratings[sidecar] = nil
                rawSidecars.remove(sidecar)
            }
            items.removeAll { deleted.contains($0.id) }

            if let first = failures.first {
                let more = failures.count > 1 ? " (and \(failures.count - 1) more)" : ""
                deleteError = "Couldn't delete \(first.url.lastPathComponent)\(more): \(first.reason)"
            }
        }
    }

    @concurrent
    private static func removeFiles(_ urls: [URL], sidecars: [URL]) async -> [(url: URL, reason: String)] {
        let fileManager = FileManager.default
        var failures: [(url: URL, reason: String)] = []
        for url in urls {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                failures.append((url, error.localizedDescription))
            }
        }
        // A shot with a file that couldn't be deleted keeps its rating.
        let keptSidecars = Set(failures.map { PhotoItem.sidecarURL(for: $0.url) })
        for sidecar in sidecars where !keptSidecars.contains(sidecar)
            && fileManager.fileExists(atPath: sidecar.path(percentEncoded: false)) {
            try? fileManager.removeItem(at: sidecar)
        }
        return failures
    }

    // MARK: - Batch copy

    var isCopying: Bool {
        if case .running = copyState { return true }
        return false
    }

    /// Asks for the destination folder. Returns `false` if the user cancelled.
    @discardableResult
    func chooseCopyDestination() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Copy Here"
        panel.message = "Choose where marked photos are copied. Use New Folder to make one."
        let dateFolders = NSButton(checkboxWithTitle: "Sort into date folders (YYYY-MM-DD)", target: nil, action: nil)
        dateFolders.state = copiesIntoDateFolders ? .on : .off
        panel.accessoryView = dateFolders
        panel.isAccessoryViewDisclosed = true
        panel.directoryURL = copyDestination
            ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        copyDestination = url
        copiesIntoDateFolders = dateFolders.state == .on
        return true
    }

    /// ⌘Return: copies every marked file (including ones hidden by the filter,
    /// matching the "N marked" count) to the destination. With a preset, each
    /// marked shot is exported as a JPEG with it applied instead.
    func startCopy(applying preset: DevelopPreset? = nil) {
        guard !isCopying else { return }
        guard !checkedIDs.isEmpty else {
            NSSound.beep()
            return
        }
        if copyDestination == nil, !chooseCopyDestination() { return }
        guard let destination = copyDestination else { return }

        let marked = items.filter { checkedIDs.contains($0.id) }
        copyInterruption = nil
        let ratings = ratings
        let pendingRatingWrite = lastSidecarWrite
        let sourceRoot = sourceURL
        let intoDateFolders = copiesIntoDateFolders
        copyPreset = preset
        copyState = .running(CopyService.Progress(totalFiles: marked.count))

        copyTask = Task {
            // Let queued rating writes land on the card first so the copied
            // sidecars carry the latest stars.
            await pendingRatingWrite?.value
            do {
                let plans = try await copier.plan(
                    marked, to: destination, from: sourceRoot,
                    intoDateFolders: intoDateFolders, preset: preset
                )
                let report = await copier.copy(plans, to: destination, ratings: ratings) { progress in
                    Task { @MainActor [weak self] in
                        // A late progress update must not overwrite the result.
                        guard let self, self.isCopying else { return }
                        self.copyState = .running(progress)
                    }
                }
                copyState = .finished(report)
            } catch {
                copyState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelCopy() {
        copyTask?.cancel()
    }

    func dismissCopyResult() {
        guard !isCopying else { return }
        copyState = .idle
    }

    func toggleCheckedForFocused() {
        if let focusedID { toggleChecked(focusedID) }
    }

    func setRatingForFocused(_ rating: Rating) {
        if let focusedID { setRating(rating, for: focusedID) }
    }

    private func updateVisibleItems() {
        let isFiltering = showsOnlyChecked || ratingFilter != nil || !hiddenExtensions.isEmpty || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        visibleItems = isFiltering ? items.filter(isVisible) : items

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
        if !isVisible(items[allIndex]) {
            let after = items[allIndex...].first(where: isVisible)
            let before = items[..<allIndex].last(where: isVisible)
            self.focusedID = (after ?? before)?.id
        }
    }

    func rescan() {
        scanTask?.cancel()
        items = []
        scanError = nil
        focusedID = nil
        viewMode = .grid
        showsOnlyChecked = false
        ratingFilter = nil
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
        if didUnmount, let volumeURL {
            if isCopying {
                if sourceURL?.isContained(in: volumeURL) == true {
                    copyInterruption = "The card was removed during the copy. Files that finished are complete; reinsert the card, mark the photos and copy again — files already copied are skipped."
                    cancelCopy()
                } else if copyDestination?.isContained(in: volumeURL) == true {
                    copyInterruption = "The destination drive was disconnected during the copy. Reconnect it and copy again — files already copied are skipped."
                    cancelCopy()
                }
            }
            if let sourceURL, sourceURL.isContained(in: volumeURL) {
                self.sourceURL = nil
            }
        }
        Task {
            await refreshVolumes()
            // A card just inserted is what the user wants to look at, even if
            // another one is already showing (but never switch mid-copy).
            if !didUnmount, let volumeURL, !isCopying,
               let card = volumes.first(where: { $0.isRemovable && $0.url.standardizedFileURL.path == volumeURL.standardizedFileURL.path }) {
                selectVolume(id: card.id)
            }
        }
    }

    // MARK: - Eject

    func eject(_ volume: VolumeInfo) {
        guard !isCopying else {
            ejectError = "A copy is in progress. Wait for it to finish, or cancel it, before ejecting."
            return
        }
        guard ejectingVolumeID == nil else { return }
        ejectingVolumeID = volume.id

        let pendingRatingWrite = lastSidecarWrite
        let wasBrowsing = sourceURL?.isContained(in: volume.url) == true
        // Stop reading from the card (scans, thumbnail decodes) before unmounting.
        if wasBrowsing { sourceURL = nil }

        Task {
            await pendingRatingWrite?.value
            do {
                try await Self.unmountAndEject(volume.url)
            } catch {
                ejectError = "Couldn't eject “\(volume.name)”: \(error.localizedDescription)"
                if wasBrowsing { sourceURL = volume.preferredSourceURL }
            }
            ejectingVolumeID = nil
        }
    }

    /// Unmounts all partitions and ejects the device. Retries once: a
    /// thumbnail decode that was mid-read can briefly keep the card busy.
    @concurrent
    private static func unmountAndEject(_ url: URL) async throws {
        do {
            try await FileManager.default.unmountVolume(at: url, options: [.allPartitionsAndEjectDisk])
        } catch {
            try await Task.sleep(for: .milliseconds(800))
            try await FileManager.default.unmountVolume(at: url, options: [.allPartitionsAndEjectDisk])
        }
    }
}
