//
//  AppInfo.swift
//  rawpreview
//

import AppKit

/// Version and author, for the sidebar footer and the About panel.
enum AppInfo {
    static let author = "khanvt001"

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// The standard About panel, with the author and support link as credits.
    @MainActor
    static func showAboutPanel() {
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: center,
        ]
        let credits = NSMutableAttributedString(string: String(localized: "Made by \(author)") + "\n", attributes: base)
        var link = base
        link[.link] = SupportView.koFiURL
        credits.append(NSAttributedString(string: "ko-fi.com/khanvt001", attributes: link))

        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }
}
