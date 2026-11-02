//
//  AutoTone.swift
//  rawpreview
//

import Foundation

/// The Light section's Auto button: slider values that give a photo a
/// balanced exposure and use the full tonal range.
///
/// A histogram heuristic, in the spirit of Lightroom's pre-2017 Auto rather
/// than its trained model. Exposure is solved: grey levels are run through
/// the same `PresetLook` the preview renders with, on top of the applied
/// preset, until the median tone moves part of the way to mid-grey. The
/// other sliders are set in proportion to how far one measurement is from
/// a typical photo (the spread of tones for Contrast, how many pixels crowd
/// each end for Highlights and Shadows, where the ends sit for Whites and
/// Blacks), within caps. Matching those measurements exactly would pin most
/// sliders at ±100 on night shots and silhouettes.
///
/// Measured on 512 px grey levels, so it takes a few ms.
nonisolated enum AutoTone {
    static func adjustments(for histogram: Histogram, preset: DevelopPreset?) -> LightAdjustments {
        let solver = Solver(bins: histogram.luminance, preset: preset)
        var light = LightAdjustments()

        // Exposure: the median part of the way to a little under mid-grey,
        // without clipping more of the photo than already is. A mostly dark
        // photo (night, silhouette) is meant to be dark: it gets less, and
        // at most +0.7.
        let median = solver.index(atPercentile: 0.5)
        let isDark = median < 40
        light[.exposure] = solver.solve(
            .exposure, in: -1.5...(isDark ? 0.7 : 1.5), light: light, target: 0.42, strength: isDark ? 0.35 : 0.7
        ) { $0[median] }
        let allowedClipping = max(solver.clipped(solver.curve(LightAdjustments())), 0.005)
        if solver.clipped(solver.curve(light)) > allowedClipping {
            light[.exposure] = solver.solve(.exposure, in: -1.5...light[.exposure], light: light, target: allowedClipping, strength: 1) {
                solver.clipped($0)
            }
        }

        // Contrast: a typical photo's tones have a standard deviation of
        // about 0.22; flatter ones get more contrast, harsher ones less.
        let exposed = solver.curve(light)
        light[.contrast] = clamp((0.22 - solver.standardDeviation(exposed)) * 150, -20, 30)

        // Highlights / Shadows: only when many pixels crowd an end.
        let curve = solver.curve(light)
        light[.highlights] = -clamp((solver.share(curve) { $0 > 0.85 } - 0.05) * 300, 0, 60)
        light[.shadows] = clamp((solver.share(curve) { $0 < 0.12 } - 0.2) * 80, 0, 30)

        // Whites / Blacks: move the end points towards the ends of the range.
        // Already clipped whites are never pulled back to grey, and blacks
        // are only ever deepened: lifting them fades the photo.
        let white = solver.index(atPercentile: 0.995)
        let whiteGap = 0.95 - curve[white]
        light[.whites] = white >= 254 ? 0 : clamp(whiteGap * 150, -30, 30)
        let blackLevel = curve[solver.index(atPercentile: 0.005)]
        light[.blacks] = -clamp((blackLevel - 0.03) * 400, 0, 30)

        // Rounded like the sliders step.
        for slider in LightAdjustments.Slider.allCases where slider != .exposure {
            light[slider] = light[slider].rounded()
        }
        return light
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private struct Solver {
        /// Share of pixels at each input luma level.
        let bins: [Double]
        let preset: DevelopPreset?

        /// Output luma of each input grey level with `light` applied.
        func curve(_ light: LightAdjustments) -> [Double] {
            guard let combined = DevelopState(processing: .init(), preset: preset, light: light).effectivePreset else {
                return (0..<256).map { Double($0) / 255 }
            }
            return (0..<256).map { level in
                let output = combined.apply(SIMD3(repeating: Double(level) / 255))
                return 0.299 * output.x + 0.587 * output.y + 0.114 * output.z
            }
        }

        /// The input level below which `percentile` of the pixels fall.
        func index(atPercentile percentile: Double) -> Int {
            var total = 0.0
            for (level, share) in bins.enumerated() {
                total += share
                if total >= percentile { return level }
            }
            return 255
        }

        /// Share of pixels whose output level passes `test`.
        func share(_ curve: [Double], where test: (Double) -> Bool) -> Double {
            zip(bins, curve).reduce(0) { $0 + (test($1.1) ? $1.0 : 0) }
        }

        func standardDeviation(_ curve: [Double]) -> Double {
            let mean = zip(bins, curve).reduce(0) { $0 + $1.0 * $1.1 }
            let variance = zip(bins, curve).reduce(0) { $0 + $1.0 * ($1.1 - mean) * ($1.1 - mean) }
            return variance.squareRoot()
        }

        /// Share of pixels that come out pure white.
        func clipped(_ curve: [Double]) -> Double {
            zip(bins, curve).reduce(0) { $0 + ($1.1 >= 0.995 ? $1.0 : 0) }
        }

        /// The value of `slider` in `range` that moves `measure` the
        /// `strength` share of the way from where it is to `target`, by
        /// bisection: every measure used rises with its slider. The nearer
        /// end of `range` if that is out of reach.
        func solve(
            _ slider: LightAdjustments.Slider,
            in range: ClosedRange<Double>,
            light: LightAdjustments,
            target goal: Double,
            strength: Double = 0.6,
            measure: ([Double]) -> Double
        ) -> Double {
            func value(at x: Double) -> Double {
                var candidate = light
                candidate[slider] = x
                return measure(curve(candidate))
            }
            guard range.lowerBound < range.upperBound else { return range.lowerBound }
            let current = value(at: min(max(light[slider], range.lowerBound), range.upperBound))
            let target = current + (goal - current) * strength
            if value(at: range.lowerBound) >= target { return range.lowerBound }
            if value(at: range.upperBound) <= target { return range.upperBound }
            var low = range.lowerBound, high = range.upperBound
            while high - low > slider.step {
                let middle = (low + high) / 2
                if value(at: middle) < target { low = middle } else { high = middle }
            }
            return ((low + high) / 2 / slider.step).rounded() * slider.step
        }
    }
}
