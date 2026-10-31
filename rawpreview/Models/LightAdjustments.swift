//
//  LightAdjustments.swift
//  rawpreview
//

import Foundation

/// The Edit sidebar's Light sliders for one photo, in Lightroom's units:
/// Exposure in stops, the rest -100…100.
///
/// Rendered after the applied preset (see `DevelopPreset.combining`),
/// through the same `PresetLook` tone curve presets use.
nonisolated struct LightAdjustments: Hashable, Sendable {
    enum Slider: CaseIterable, Identifiable {
        case exposure, contrast, highlights, shadows, whites, blacks

        var id: Self { self }

        var title: String {
            switch self {
            case .exposure: "Exposure"
            case .contrast: "Contrast"
            case .highlights: "Highlights"
            case .shadows: "Shadows"
            case .whites: "Whites"
            case .blacks: "Blacks"
            }
        }

        var range: ClosedRange<Double> {
            self == .exposure ? -5...5 : -100...100
        }

        var step: Double {
            self == .exposure ? 0.01 : 1
        }

        /// The Lightroom (Process Version 2012) setting it adds to.
        var settingsKey: String {
            switch self {
            case .exposure: "Exposure2012"
            case .contrast: "Contrast2012"
            case .highlights: "Highlights2012"
            case .shadows: "Shadows2012"
            case .whites: "Whites2012"
            case .blacks: "Blacks2012"
            }
        }

        /// "+0.04", "-16", "0".
        func format(_ value: Double) -> String {
            guard abs(value) >= step / 2 else { return self == .exposure ? "0.00" : "0" }
            return self == .exposure ? String(format: "%+.2f", value) : String(format: "%+.0f", value)
        }
    }

    /// Only non-zero sliders, so two untouched photos compare equal.
    private var values: [Slider: Double] = [:]

    subscript(slider: Slider) -> Double {
        get { values[slider] ?? 0 }
        set {
            let clamped = min(max(newValue, slider.range.lowerBound), slider.range.upperBound)
            values[slider] = abs(clamped) < slider.step / 2 ? nil : clamped
        }
    }

    var isZero: Bool {
        values.isEmpty
    }
}
