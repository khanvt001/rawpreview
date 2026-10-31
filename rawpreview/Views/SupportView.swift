//
//  SupportView.swift
//  rawpreview
//

import SwiftUI

/// "Buy me a coffee": a VietQR bank transfer for Vietnam, Ko-fi everywhere
/// else. Opens on the one that fits the Mac's region; either can be chosen.
struct SupportView: View {
    enum Method: Hashable {
        case vietQR, koFi
    }

    static let windowID = "support"
    static let koFiURL = URL(string: "https://ko-fi.com/khanvt001")!
    static let accountName = "khanvt001"
    static let accountNumber = "REMOVED"
    static let bankName = "REMOVED"

    // The region, not the language: plenty of Macs in Vietnam run in English.
    @State private var method: Method = Locale.current.region?.identifier == "VN" ? .vietQR : .koFi
    @State private var copiedNumber = false
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

            Picker("Payment Method", selection: $method) {
                Text(verbatim: "VietQR").tag(Method.vietQR)
                Text(verbatim: "Ko-fi").tag(Method.koFi)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)

            switch method {
            case .vietQR: vietQR
            case .koFi: koFi
            }
        }
        .padding(28)
        .frame(width: 460)
        // Ideal size is the minimum too, so switching methods resizes the
        // window instead of squeezing the QR code to nothing.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var vietQR: some View {
        VStack(spacing: 10) {
            Image("VietQR")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 340, height: 340 * 730 / 646)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text("Scan with any Vietnamese banking app and enter any amount.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 2) {
                Text(Self.accountName).fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(verbatim: "\(Self.bankName) · \(Self.accountNumber)")
                        .monospacedDigit()
                        .textSelection(.enabled)
                    Button(copiedNumber ? "Copied" : "Copy", systemImage: copiedNumber ? "checkmark" : "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.accountNumber, forType: .string)
                        copiedNumber = true
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Copy account number")
                }
            }
            .font(.callout)
        }
    }

    private var koFi: some View {
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
}

/// App menu item that opens the support window.
struct SupportMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Support RawPreview…") { openWindow(id: SupportView.windowID) }
    }
}
