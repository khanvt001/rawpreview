//
//  VolumeService.swift
//  rawpreview
//

import Foundation

/// Enumerates mounted volumes. Runs off the main actor (`@concurrent`) because
/// resource lookups on a slow or just-inserted card can block.
nonisolated struct VolumeService: Sendable {
    private static let resourceKeys: [URLResourceKey] = [
        .volumeNameKey,
        .volumeIsRemovableKey,
        .volumeIsEjectableKey,
        .volumeIsBrowsableKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey,
    ]

    @concurrent
    func mountedVolumes() async -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Self.resourceKeys,
            options: [.skipHiddenVolumes]
        ) ?? []

        return urls.compactMap { url -> VolumeInfo? in
            guard let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys)),
                  values.volumeIsBrowsable ?? true
            else { return nil }

            return VolumeInfo(
                url: url,
                name: values.volumeName ?? url.lastPathComponent,
                isRemovable: (values.volumeIsRemovable ?? false) || (values.volumeIsEjectable ?? false),
                totalCapacity: values.volumeTotalCapacity.map(Int64.init),
                availableCapacity: values.volumeAvailableCapacity.map(Int64.init)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isRemovable != rhs.isRemovable { return lhs.isRemovable }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
