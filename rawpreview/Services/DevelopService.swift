import CoreGraphics
import CoreImage
import Foundation
import os

/// Source-aware previews. All bases are before the creative look and display
/// transform; RAW bases are materialized RGBA half-float, byte-bounded.
nonisolated enum DevelopService {
    private struct BaseKey: Hashable, Sendable {
        let url: URL
        let fingerprint: String
        let raw: Bool
        let whiteBalance: DevelopState.WhiteBalance?
        /// RAW sharpening/noise reduction happen in the decoder.
        let detail: DevelopState.Detail?
        let longEdge: Int?
        let version: Int
        let memoryGeneration: Int
    }
    private struct RenderKey: Hashable, Sendable {
        let base: BaseKey
        let look: DevelopPreset.RenderKey?
        let whiteBalance: DevelopState.WhiteBalance
        let displayGeneration: Int
        let tile: Bool
        /// The rendered size: a RAW base can be larger (see `baseKey`).
        let outputEdge: Int?
        /// Rendered from a cached RAW base decoded at another white balance.
        var approximate = false
    }
    private struct WorkKey: Hashable, Sendable {
        let key: RenderKey
        let interactive: Bool
    }
    private static let bases = BoundedCache<BaseKey, DevelopImage>(byteLimit: 128 * 1024 * 1024, countLimit: 4)
    /// One full-size base (zoomed in), on its own: a 20 MP half-float base is
    /// ~170 MB, more than `bases` holds, and slider changes would re-decode it.
    private static let fullBases = BoundedCache<BaseKey, DevelopImage>(byteLimit: 512 * 1024 * 1024, countLimit: 1)
    /// Room for one full-size 8-bit render of a 45 MP photo (~180 MB) next
    /// to the 2048 px ones; cleared under memory pressure like the rest.
    private static let selected = BoundedCache<RenderKey, CGImage>(byteLimit: 256 * 1024 * 1024, countLimit: 6)
    private static let transient = BoundedCache<RenderKey, CGImage>(byteLimit: 16 * 1024 * 1024, countLimit: 24)
    private static let decoding = SharedWork<BaseKey, Result<DevelopImage, any Error>>()
    private static let rendering = SharedWork<WorkKey, Result<CGImage, any Error>>()
    private static let generation = OSAllocatedUnfairLock(initialState: 0)
    static let sourceReady = Notification.Name("RawPreviewDevelopSourceReady")
    private static let pressure: any DispatchSourceMemoryPressure = {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler {
            removeAll()
            PresetRenderer.removeAll()
            ThumbnailService.shared.removeAll()
            PreviewService.shared.removeAll()
        }
        source.resume()
        return source
    }()

    static func observeMemoryPressure() { _ = pressure }

    /// Peek at a finished result without starting a render or a RAW decode.
    static func cachedPreview(url: URL, state: DevelopState, longEdge: Int?, purpose: PresetRenderer.Purpose = .selected) -> CGImage? {
        let key = renderKey(url, state: state, longEdge: longEdge, purpose: purpose)
        return selected[key] ?? transient[key]
    }

    /// `url` is already resolved for the shot. cacheOnly is mandatory for
    /// hover/tiles in RAW mode: no hover action ever starts a RAW decoder.
    static func preview(url: URL, state: DevelopState, longEdge: Int?, purpose: PresetRenderer.Purpose = .selected,
                        cacheOnly: Bool = false) async throws -> CGImage? {
        observeMemoryPressure()
        try Task.checkCancellation()
        let baseKey = baseKey(url, state: state, longEdge: longEdge)
        var key = renderKey(url, state: state, longEdge: longEdge, purpose: purpose)
        if let hit = selected[key] ?? transient[key] {
            PipelineMetrics.event("develop.hit")
            return hit
        }
        let baseCache = cache(for: baseKey)
        let base: DevelopImage
        var extraGain = SIMD3<Double>(repeating: 1)
        if let hit = baseCache[baseKey] { base = hit }
        else if cacheOnly {
            // Hover and tiles never decode a RAW: borrow a cached base decoded
            // at another white balance and shift it, as an approximation.
            guard let (standInKey, standIn) = standInBase(for: baseKey), let neutral = standIn.neutral else { return nil }
            base = standIn
            extraGain = neutral.gain(to: state.whiteBalance)
            key = RenderKey(base: standInKey, look: key.look, whiteBalance: key.whiteBalance,
                            displayGeneration: key.displayGeneration, tile: key.tile, outputEdge: key.outputEdge, approximate: true)
            if let hit = transient[key] { return hit }
        } else {
            let result = await decoding.run(baseKey) {
                await RenderCoordinator.run(.high) {
                    if let hit = baseCache[baseKey] { return .success(hit) }
                    return Result {
                        let base = try DevelopDecoder.decode(url, state: state, longEdge: baseKey.longEdge)
                        try Task.checkCancellation()
                        if generation.withLock({ $0 }) == baseKey.memoryGeneration {
                            baseCache.insert(base, for: baseKey, cost: base.image.bytesPerRow * base.image.height)
                            NotificationCenter.default.post(name: sourceReady, object: url)
                        }
                        return base
                    }
                }
            }
            guard let result else { throw CancellationError() }
            base = try result.get()
        }
        try Task.checkCancellation()
        let interactive = purpose != .tile
        let renderKey = key
        let gain = extraGain
        // The base may be larger than asked for: a stand-in, or a RAW.
        let targetEdge = key.outputEdge
        let request = RenderCoordinator.nextRequestID()
        let space = DisplayColorSpace.target
        let result = await rendering.run(
            WorkKey(key: renderKey, interactive: interactive), priority: interactive ? .userInitiated : .utility,
            latest: interactive ? .init(lane: "develop", id: request) : nil
        ) {
            await RenderCoordinator.run(interactive ? .high : .low, latest: interactive ? "develop.render" : nil, requestID: request) {
                if let hit = selected[renderKey] ?? transient[renderKey] { return .success(hit) }
                return Result {
                    PipelineMetrics.event("develop.miss")
                    let input = try targetEdge.map { try DevelopRenderer.resized(base, longEdge: $0) } ?? base
                    let image = try DevelopRenderer.render(input, state: state, outputSpace: space, extraGain: gain)
                    try Task.checkCancellation()
                    if generation.withLock({ $0 }) == renderKey.base.memoryGeneration {
                        let cache = purpose == .selected ? selected : transient
                        cache.insert(image, for: renderKey, cost: image.bytesPerRow * image.height) {
                            purpose == .selected && $0.base.url == renderKey.base.url && $0.outputEdge == renderKey.outputEdge
                        }
                    }
                    return image
                }
            }
        }
        guard let result else { throw CancellationError() }
        return try result.get()
    }

    /// A tile can use the current RAW navigation base, without decoding a
    /// separate RAW for every preset or baking display pixels into its source.
    static func tile(url: URL, state: DevelopState) async throws -> CGImage? {
        if state.processing.usesRAW(for: url) {
            return try await preview(url: url, state: state, longEdge: 1024, purpose: .tile, cacheOnly: true)
        }
        return try await preview(url: url, state: state, longEdge: 256, purpose: .tile)
    }

    static func removeAll() {
        generation.withLock { $0 += 1 }
        bases.removeAll()
        fullBases.removeAll()
        selected.removeAll()
        transient.removeAll()
        DevelopDecoder.context.clearCaches()
    }

    static func removeDisplayResults() {
        selected.removeAll()
        transient.removeAll()
    }

    private static let rawBaseEdge = 2048

    private static func cache(for key: BaseKey) -> BoundedCache<BaseKey, DevelopImage> {
        key.longEdge == nil ? fullBases : bases
    }

    /// A cached RAW base of the same file at any white balance, at least as
    /// large as `key` asks for: the same size first, then a larger one.
    private static func standInBase(for key: BaseKey) -> (BaseKey, DevelopImage)? {
        guard key.raw else { return nil }
        @Sendable func sameFile(_ other: BaseKey) -> Bool {
            other.url == key.url && other.fingerprint == key.fingerprint && other.raw
                && other.version == key.version && other.memoryGeneration == key.memoryGeneration
        }
        if let hit = bases.last(where: { sameFile($0) && $0.longEdge == key.longEdge }) { return hit }
        if let wanted = key.longEdge {
            if let hit = bases.last(where: { sameFile($0) && ($0.longEdge ?? .max) > wanted }) { return hit }
        }
        return fullBases.last(where: sameFile)
    }

    private static func renderKey(_ url: URL, state: DevelopState, longEdge: Int?, purpose: PresetRenderer.Purpose) -> RenderKey {
        RenderKey(base: baseKey(url, state: state, longEdge: longEdge), look: state.effectivePreset?.renderKey,
                  whiteBalance: state.whiteBalance, displayGeneration: DisplayColorSpace.generation, tile: purpose == .tile,
                  outputEdge: purpose == .tile ? 256 : longEdge)
    }

    private static func baseKey(_ url: URL, state: DevelopState, longEdge: Int?) -> BaseKey {
        let raw = state.processing.usesRAW(for: url)
        // A RAW decodes at 2048 px for anything up to that: demosaicing at
        // 1024 costs about the same (~140 vs ~155 ms on a Z 50 NEF) and
        // halving a cached 2048 base takes ~8 ms, so the quick preview, the
        // settled one and the preset tiles share one decode.
        let longEdge = raw ? longEdge.map { max($0, rawBaseEdge) } : longEdge
        return BaseKey(url: url, fingerprint: ImageSourceKey.file(url), raw: raw,
                       whiteBalance: raw ? state.whiteBalance : nil, detail: raw ? state.detail(isRAW: true) : nil, longEdge: longEdge,
                       version: DevelopState.pipelineVersion, memoryGeneration: generation.withLock { $0 })
    }
}
