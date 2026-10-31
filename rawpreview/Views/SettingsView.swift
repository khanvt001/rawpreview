//
//  SettingsView.swift
//  rawpreview
//

import SwiftUI

/// The app's Settings window (⌘,).
struct SettingsView: View {
    @AppStorage(Analytics.enabledKey) private var sharesUsage = true

    var body: some View {
        Form {
            Section {
                Toggle("Share anonymous usage statistics", isOn: $sharesUsage)
            } footer: {
                Text("Counts app launches and how many photos are copied or shared, with the app and macOS version. Never file names, folders or photos.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onChange(of: sharesUsage) { _, on in
            if on { Analytics.start() }
        }
    }
}
