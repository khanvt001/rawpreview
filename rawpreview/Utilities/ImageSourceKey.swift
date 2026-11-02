import Foundation

/// Phase 1 still uses ImageIO's current decode policy. Changing that policy
/// or the rendering algorithm must change the version, too.
nonisolated enum ImageSourceKey {
    static let pipelineVersion = 1

    static func file(_ url: URL) -> String {
        let url = url.standardizedFileURL
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey])
        return "\(url.path(percentEncoded: false))|\(values?.fileSize ?? -1)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(String(describing: values?.fileResourceIdentifier))"
    }

    static func display(_ url: URL, size: String) -> String {
        "v\(pipelineVersion)|imageio|\(size)|display\(DisplayColorSpace.generation)|\(file(url))"
    }
}
