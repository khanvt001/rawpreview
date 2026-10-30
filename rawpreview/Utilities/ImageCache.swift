//
//  ImageCache.swift
//  rawpreview
//

import CoreGraphics
import Foundation

/// Thread-safe, memory-bounded cache of decoded images. `NSCache` is internally
/// synchronized and evicts under memory pressure; this wrapper adds a typed,
/// `Sendable` API with byte-accurate costs.
nonisolated final class ImageCache: @unchecked Sendable {
    private final class Entry {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private let storage = NSCache<NSString, Entry>()

    init(name: String, totalCostLimitMB: Int, countLimit: Int = 0) {
        storage.name = name
        storage.totalCostLimit = totalCostLimitMB * 1024 * 1024
        storage.countLimit = countLimit
    }

    subscript(key: String) -> CGImage? {
        get { storage.object(forKey: key as NSString)?.image }
        set {
            if let newValue {
                storage.setObject(Entry(newValue), forKey: key as NSString, cost: newValue.bytesPerRow * newValue.height)
            } else {
                storage.removeObject(forKey: key as NSString)
            }
        }
    }

    func removeAll() {
        storage.removeAllObjects()
    }
}
