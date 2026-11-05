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
///
/// The app key comes from the `APTABASE_APP_KEY` build setting. A build without
/// one, such as a fork's, has no analytics and hides the Settings toggle.
nonisolated enum Analytics {
    static let enabledKey = "shareAnonymousUsage"
    private static let appKey = Bundle.main.object(forInfoDictionaryKey: "AptabaseAppKey") as? String ?? ""
    private static let started = OSAllocatedUnfairLock(initialState: false)

    static var isAvailable: Bool { !appKey.isEmpty }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Call at launch and when the user turns sharing back on.
    static func start() {
        guard isAvailable, isEnabled else { return }
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
