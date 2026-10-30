//
//  Rating.swift
//  rawpreview
//

import Foundation

/// Star rating, 0 (unrated) to 5. Maps 1:1 to `xmp:Rating`.
nonisolated struct Rating: RawRepresentable, Hashable, Comparable, Sendable {
    static let maxStars = 5
    static let none = Rating(0)

    let rawValue: Int

    init(_ stars: Int) {
        rawValue = min(max(stars, 0), Self.maxStars)
    }

    init?(rawValue: Int) {
        guard (0...Self.maxStars).contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    var isRated: Bool { rawValue > 0 }

    static func < (lhs: Rating, rhs: Rating) -> Bool { lhs.rawValue < rhs.rawValue }
}
