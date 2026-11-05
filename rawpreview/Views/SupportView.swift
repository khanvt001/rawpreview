//
//  SupportView.swift
//  rawpreview
//

import SwiftUI

/// "Buy me a coffee": a link to Ko-fi.
struct SupportView: View {
    static let windowID = "support"
    static let koFiURL = URL(string: "https://ko-fi.com/khanvt001")!

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 34))
                .foregroundStyle(.brown)
            VStack(spacing: 6) {
                Text("Enjoying RawPreview?")
                    .font(.title2.weight(.semibold))
                Text("It's made by one person in their spare time. If it saves you time, a coffee helps keep it going. Thank you!")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button {
                    openURL(Self.koFiURL)
                } label: {
                    Label("Buy Me a Coffee on Ko-fi", systemImage: "heart.fill")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Text("Card or PayPal, no account needed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
        .padding(28)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// App menu item that opens the support window.
struct SupportMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Support RawPreview…") { openWindow(id: SupportView.windowID) }
    }
}
