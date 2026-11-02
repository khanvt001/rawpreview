import Foundation

/// A shot resolves consistently: camera JPEG/preview in Fast, RAW in RAW mode.
/// Directory indexes are bounded and invalidated when the directory changes.
nonisolated enum PhotoSourceResolver {
    private struct Index: Sendable {
        var raws: [String: URL] = [:]
        var jpegs: [String: URL] = [:]
    }
    private static let directories = BoundedCache<String, Index>(byteLimit: 4 * 1024 * 1024, countLimit: 8)

    @concurrent static func resolve(_ url: URL, processing: ProcessingConfiguration) async -> URL { resolveNow(url, processing: processing) }

    static func resolveNow(_ url: URL, processing: ProcessingConfiguration) -> URL {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        guard MediaKind(fileExtension: url.pathExtension).isImage else { return url }
        let folder = url.deletingLastPathComponent()
        let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let key = "\(folder.path)|\(modified?.timeIntervalSince1970 ?? 0)"
        let index: Index
        if let hit = directories[key] {
            index = hit
        } else {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            var result = Index()
            for candidate in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let file = candidate.standardizedFileURL.resolvingSymlinksInPath()
                let shot = file.deletingPathExtension().lastPathComponent.lowercased()
                switch MediaKind(fileExtension: file.pathExtension) {
                case .raw: if result.raws[shot] == nil { result.raws[shot] = file }
                case .jpeg, .heif: if result.jpegs[shot] == nil { result.jpegs[shot] = file }
                default: break
                }
            }
            directories.insert(result, for: key, cost: (result.raws.count + result.jpegs.count) * 256)
            index = result
        }
        let shot = url.deletingPathExtension().lastPathComponent.lowercased()
        guard let raw = index.raws[shot] else { return url }
        // Fast mode uses the camera's paired JPEG/HEIF when present, otherwise
        // its embedded RAW preview. Both members of a pair make this choice.
        return processing.usesRAW(for: raw) ? raw : index.jpegs[shot] ?? raw
    }
}
