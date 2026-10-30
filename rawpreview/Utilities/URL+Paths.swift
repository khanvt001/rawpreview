//
//  URL+Paths.swift
//  rawpreview
//

import Foundation

nonisolated extension URL {
    /// `true` when `self` is `ancestor` or lives somewhere beneath it.
    /// Compares whole path components, so `/Volumes/SD2` is not inside `/Volumes/SD`.
    func isContained(in ancestor: URL) -> Bool {
        let own = standardizedFileURL.pathComponents
        let base = ancestor.standardizedFileURL.pathComponents
        return own.count >= base.count && Array(own.prefix(base.count)) == base
    }
}
