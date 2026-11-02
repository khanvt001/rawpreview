import Foundation

nonisolated enum ProcessingSource: String, CaseIterable, Sendable, Codable {
    case embedded
    case raw

    static let defaultsKey = "imageProcessingSource"
    static let fallbackKey = "rawEmbeddedFallbacks"

    var title: String {
        switch self {
        case .embedded: String(localized: "Embedded Preview — Fast")
        case .raw: String(localized: "Original RAW — High Quality")
        }
    }
}

/// Immutable at the time of an action, including explicitly accepted fallback
/// files. A failed RAW decode never mutates this configuration.
nonisolated struct ProcessingConfiguration: Hashable, Sendable {
    var source: ProcessingSource = .embedded
    var embeddedFallbacks: Set<String> = []

    static var current: Self {
        let defaults = UserDefaults.standard
        return Self(
            source: ProcessingSource(rawValue: defaults.string(forKey: ProcessingSource.defaultsKey) ?? "") ?? .embedded,
            embeddedFallbacks: decodeFallbacks(defaults.data(forKey: ProcessingSource.fallbackKey) ?? Data())
        )
    }

    static func decodeFallbacks(_ data: Data) -> Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: data)) ?? [])
    }

    static func acceptEmbeddedFallback(for url: URL) {
        var fallbacks = current.embeddedFallbacks
        fallbacks.insert(ImageSourceKey.file(url))
        // Limit stored decisions as well as image caches.
        let kept = Array(fallbacks.sorted().suffix(256))
        UserDefaults.standard.set(try? JSONEncoder().encode(kept), forKey: ProcessingSource.fallbackKey)
    }

    func usesRAW(for url: URL) -> Bool {
        source == .raw && MediaKind(fileExtension: url.pathExtension) == .raw
            && !embeddedFallbacks.contains(ImageSourceKey.file(url))
    }
}
