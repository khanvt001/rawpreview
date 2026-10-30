//
//  CopySheet.swift
//  rawpreview
//

import AppKit
import SwiftUI

/// Progress while a batch copy runs, then a summary.
struct CopySheet: View {
    @Environment(LibraryViewModel.self) private var library
    @State private var startDate = Date.now

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch library.copyState {
            case .idle:
                EmptyView()
            case .running(let progress):
                running(progress)
            case .finished(let report):
                finished(report)
            case .failed(let message):
                failed(message)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { startDate = .now }
    }

    // MARK: - Running

    private func running(_ progress: CopyService.Progress) -> some View {
        Group {
            Label {
                Text("Copying \(progress.completedFiles) of \(progress.totalFiles)")
                    .font(.headline)
            } icon: {
                Image(systemName: "doc.on.doc")
            }

            ProgressView(value: progress.fraction)

            HStack {
                Text("\(progress.completedBytes.formatted(.byteCount(style: .file))) of \(progress.totalBytes.formatted(.byteCount(style: .file)))")
                Spacer()
                if let remaining = timeRemaining(progress) {
                    Text(remaining)
                }
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)

            if let destination = library.copyDestination {
                Text("To \(destination.path(percentEncoded: false))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { library.cancelCopy() }
                    .keyboardShortcut(.cancelAction)
                    .help("Stops after the files in progress finish; nothing is left half-copied")
            }
        }
    }

    private func timeRemaining(_ progress: CopyService.Progress) -> String? {
        let elapsed = Date.now.timeIntervalSince(startDate)
        guard progress.completedBytes > 0, elapsed > 2 else { return nil }
        let rate = Double(progress.completedBytes) / elapsed
        let seconds = Double(progress.totalBytes - progress.completedBytes) / rate
        let speed = Int64(rate).formatted(.byteCount(style: .file))
        let left = Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
        return "\(speed)/s · \(left) left"
    }

    // MARK: - Finished

    private func finished(_ report: CopyService.Report) -> some View {
        Group {
            Label {
                Text(library.copyInterruption != nil ? "Copy Interrupted"
                     : report.wasCancelled ? "Copy Cancelled"
                     : report.failures.isEmpty ? "Copy Complete" : "Copy Finished with Errors")
                    .font(.headline)
            } icon: {
                Image(systemName: report.failures.isEmpty && !report.wasCancelled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(report.failures.isEmpty && !report.wasCancelled ? .green : .orange)
            }

            // Shown however the copy ended: when a card is pulled, the files
            // in flight often fail before the removal notice cancels the rest.
            if let reason = library.copyInterruption {
                Text(reason)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                summaryRow("\(report.copied) copied", detail: "\(report.copiedBytes.formatted(.byteCount(style: .file))) in \(report.duration.formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)))")
                if report.skipped > 0 {
                    summaryRow("\(report.skipped) already there", detail: "skipped (same name and size)")
                }
                if report.renamed > 0 {
                    summaryRow("\(report.renamed) renamed", detail: "a different file had the same name")
                }
                if !report.failures.isEmpty {
                    summaryRow("\(report.failures.count) failed", detail: nil)
                }
            }
            .font(.callout)

            if !report.failures.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(report.failures, id: \.fileName) { failure in
                            Text("\(failure.fileName): \(failure.reason)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }

            HStack {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([report.destination])
                }
                Spacer()
                if report.failures.isEmpty && !report.wasCancelled {
                    Button("Clear Marks") {
                        library.clearChecked()
                        library.dismissCopyResult()
                    }
                    .help("Unmark the copied photos")
                }
                Button("Done") { library.dismissCopyResult() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func summaryRow(_ title: String, detail: String?) -> some View {
        HStack(spacing: 6) {
            Text(title).fontWeight(.medium)
            if let detail {
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Failed before starting

    private func failed(_ message: String) -> some View {
        Group {
            Label {
                Text("Couldn't Start Copy").font(.headline)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
            HStack {
                Button("Choose Another Folder…") {
                    library.dismissCopyResult()
                    if library.chooseCopyDestination() {
                        library.startCopy()
                    }
                }
                Spacer()
                Button("OK") { library.dismissCopyResult() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
