//
//  Analytics.swift
//  rawpreview
//

@preconcurrency import Aptabase
import Foundation
import os

/// Anonymous usage counts sent to Aptabase (aptabase.com): launches (which
/// gives daily / monthly users, app and macOS versions, locale), and how
/// many photos are copied or shared. Never file names, paths or image data.
///
/// On by default; the Settings window turns it off, after which nothing is
/// sent. Debug builds are tagged as such and show up separately in the
/// dashboard.
nonisolated enum Analytics {
    static let enabledKey = "shareAnonymousUsage"
    private static let appKey = "A-US-9515763086"
    private static let started = OSAllocatedUnfairLock(initialState: false)

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Call at launch and when the user turns sharing back on.
    static func start() {
        guard isEnabled else { return }
        started.withLockUnchecked { started in
            guard !started else { return }
            Aptabase.shared.initialize(appKey: appKey)
            started = true
        }
    }

    static func track(_ event: String, _ props: [String: any Value] = [:]) {
        guard isEnabled, started.withLock({ $0 }) else { return }
        Aptabase.shared.trackEvent(event, with: props)
    }
}
