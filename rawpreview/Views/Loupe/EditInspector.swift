//
//  EditInspector.swift
//  rawpreview
//

import SwiftUI

/// The sidebar's Edit page: a histogram of the photo as shown, then the
/// Light sliders. Changes preview on the photo straight away and last for
/// this session.
struct EditInspector: View {
    let item: PhotoItem?
    /// What the loupe is showing (edits included), for the histogram.
    let image: CGImage?

    @Environment(EditStore.self) private var edits
    @Environment(PresetStore.self) private var presets
    @AppStorage("editLightExpanded") private var isLightExpanded = true
    @State private var histogram: Histogram?
    @State private var isAutoRunning = false

    var body: some View {
        if let item, item.kind.isImage {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HistogramView(histogram: histogram)
                            .frame(height: 96)
                            .padding(12)
                        Divider()
                        lightSection(item)
                            .padding(12)
                    }
                }
                .scrollIndicators(.never)
                Divider()
                Text("Approximate preview · this session only · double-click a slider to reset it")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
            .task(id: image.map(ObjectIdentifier.init)) {
                guard let image else {
                    histogram = nil
                    return
                }
                let computed = await Task.detached(priority: .utility) { Histogram(image) }.value
                if !Task.isCancelled {
                    histogram = computed
                }
            }
        } else {
            ContentUnavailableView("Nothing to Edit", systemImage: "slider.horizontal.3")
        }
    }

    private func lightSection(_ item: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { isLightExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isLightExpanded ? 90 : 0))
                            .frame(width: 12)
                        Text("Light")
                            .font(.headline)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                Spacer()
                Button("Auto") {
                    Task { await autoTone(item) }
                }
                .buttonStyle(.link)
                .font(.caption)
                .focusable(false)
                .disabled(isAutoRunning)
                .help("Set the Light sliders for a balanced exposure")
                Button("Reset") {
                    edits.setAdjustments(LightAdjustments(), for: item.id)
                }
                .buttonStyle(.link)
                .font(.caption)
                .focusable(false)
                .disabled(!edits.hasAdjustments(item.id))
            }

            if isLightExpanded {
                ForEach(LightAdjustments.Slider.allCases) { slider in
                    AdjustmentSlider(slider: slider, value: binding(slider, for: item.id))
                }
            }
        }
    }

    /// Measures the photo as shot (no preset or edits: Auto replaces them),
    /// then solves the sliders on top of the applied preset.
    private func autoTone(_ item: PhotoItem) async {
        isAutoRunning = true
        defer { isAutoRunning = false }
        var original = PreviewService.shared.cachedImage(for: item.url)
        if original == nil {
            original = await ThumbnailService.shared.thumbnail(for: item.url, pixelSize: 1024)
        }
        guard let original else { return }
        let preset = presets.activePreset
        let light = await Task.detached(priority: .userInitiated) {
            Histogram(original).map { AutoTone.adjustments(for: $0, preset: preset) }
        }.value
        if let light {
            withAnimation(.easeOut(duration: 0.2)) {
                edits.setAdjustments(light, for: item.id)
            }
        }
    }

    private func binding(_ slider: LightAdjustments.Slider, for id: PhotoItem.ID) -> Binding<Double> {
        Binding(
            get: { edits.adjustments(for: id)[slider] },
            set: { value in
                var adjustments = edits.adjustments(for: id)
                adjustments[slider] = value
                edits.setAdjustments(adjustments, for: id)
            }
        )
    }
}

/// Red, green and blue overlaid additively, so where all three agree it
/// reads white, as in Lightroom.
private struct HistogramView: View {
    let histogram: Histogram?

    var body: some View {
        Canvas { context, size in
            guard let histogram else { return }
            context.blendMode = .plusLighter
            for (bins, color) in [(histogram.red, Color.red), (histogram.green, Color.green), (histogram.blue, Color.blue)] {
                context.fill(path(bins, in: size), with: .color(color.opacity(0.75)))
            }
        }
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            if histogram == nil {
                ProgressView().controlSize(.small)
            }
        }
        .accessibilityLabel("Histogram")
    }

    private func path(_ bins: [Double], in size: CGSize) -> Path {
        Path { path in
            let step = size.width / CGFloat(bins.count - 1)
            path.move(to: CGPoint(x: 0, y: size.height))
            for (index, value) in bins.enumerated() {
                path.addLine(to: CGPoint(x: CGFloat(index) * step, y: size.height * (1 - min(value, 1))))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
    }
}

/// Name and value above a slider that fills from zero, like Lightroom's.
private struct AdjustmentSlider: View {
    let slider: LightAdjustments.Slider
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(slider.title)
                Spacer()
                Text(slider.format(value))
                    .monospacedDigit()
                    .foregroundStyle(value == 0 ? .secondary : .primary)
            }
            .font(.callout)
            CenteredSlider(value: $value, range: slider.range, step: slider.step)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { value = 0 }
        .help("Drag to adjust · double-click to reset")
        .accessibilityRepresentation {
            Slider(value: $value, in: slider.range, step: slider.step) {
                Text(slider.title)
            }
        }
    }
}

/// A track with a fill from zero to the thumb. Dragging moves the value by
/// how far the pointer moves, so clicking the thumb never makes it jump.
private struct CenteredSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    @State private var dragStart: Double?
    private let thumbSize: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let usable = max(geometry.size.width - thumbSize, 1)
            let span = range.upperBound - range.lowerBound
            let x = thumbSize / 2 + usable * (value - range.lowerBound) / span
            let zeroX = thumbSize / 2 + usable * (0 - range.lowerBound) / span

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: 3)
                Rectangle()
                    .fill(.primary)
                    .frame(width: abs(x - zeroX), height: 3)
                    .offset(x: min(x, zeroX))
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(Circle().strokeBorder(.primary, lineWidth: 2))
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: x - thumbSize / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        let start = dragStart ?? value
                        dragStart = start
                        let moved = start + Double(drag.translation.width / usable) * span
                        value = min(max((moved / step).rounded() * step, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
        .frame(height: thumbSize + 2)
    }
}
