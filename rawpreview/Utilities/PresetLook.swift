//
//  PresetLook.swift
//  rawpreview
//

import Foundation

/// A develop preset's settings turned into image operations.
///
/// Everything that changes a pixel's colour on its own (white balance,
/// exposure, the Basic tone sliders, curves, B&W mix, HSL, saturation, colour
/// grading) is one function from colour to colour, `apply`, which
/// `PresetRenderer` bakes into a 3D lookup table. Clarity, texture, vignette
/// and grain depend on neighbouring pixels or position, so they're kept as
/// parameters for the renderer.
///
/// Adobe doesn't publish Camera Raw's maths, and we start from the camera's
/// processed JPEG rather than raw data, so every operation here is a
/// reasonable likeness of its Lightroom slider, not a reproduction. Working
/// values are gamma-encoded sRGB in 0…1; exposure and white balance are
/// applied in linear light.
nonisolated struct PresetLook: Sendable {
    struct Vignette: Sendable {
        /// -1 (dark corners) … 1 (light corners).
        let amount: Double
        /// 0…1: how far in the falloff starts.
        let midpoint: Double
        /// 0…1: how soft the falloff is.
        let feather: Double
    }

    struct Grain: Sendable {
        /// 0…1.
        let amount: Double
        /// 0…1 (Lightroom's default 25 is 0.25).
        let size: Double
    }

    /// Black & white conversion with the B&W mix.
    let isMonochrome: Bool
    /// Local contrast, -1…1, at large (clarity) and fine (texture) scale.
    let clarity: Double
    let texture: Double
    let vignette: Vignette?
    let grain: Grain?
    /// Applying this look changes nothing.
    private(set) var isIdentity = false

    private let linearGain: SIMD3<Double>
    private let contrast, highlights, shadows, whites, blacks: Double
    private let parametric: ParametricCurve
    private let master: PointCurve
    private let red, green, blue: PointCurve
    /// Per hue band (see `hueCenters`), -1…1.
    private let grayMix: [Double]
    private let hueShift, saturationShift, luminanceShift: [Double]
    private let hasHSL: Bool
    /// Overall saturation multiplier (Saturation slider and profile).
    private let saturation: Double
    private let vibrance: Double
    private let grades: [Grade]
    private let gradeBalance: Double
    private let gradeBlending: Double

    private struct Grade {
        enum Range { case shadows, midtones, highlights, global }
        let range: Range
        /// Chroma (colour minus its own luma) of the tint at full strength.
        let tint: SIMD3<Double>
        let saturation: Double
        let luminance: Double
    }

    /// Lightroom's eight HSL / B&W mix bands, in degrees.
    private static let hueCenters: [Double] = [0, 30, 60, 120, 180, 240, 270, 300]
    private static let hueNames = ["Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta"]

    init(settings: [String: PresetValue]) {
        func number(_ key: String, _ fallback: Double = 0) -> Double {
            settings[key]?.number ?? fallback
        }

        if case .bool(true) = settings["ConvertToGrayscale"] {
            isMonochrome = true
        } else {
            isMonochrome = number("Saturation") <= -100
        }
        let profile = settings["CameraProfile"]?.string ?? ""
        let isVivid = profile == "Adobe Vivid"

        // White balance as a shift from the photo's own: absolute Kelvin
        // presets are measured against daylight (5500 K), since the as-shot
        // value of a processed JPEG is unknown.
        var mired = number("IncrementalTemperature") * 0.5
        var tint = number("IncrementalTint")
        if let whiteBalance = settings["WhiteBalance"]?.string, whiteBalance != "As Shot" {
            if let kelvin = settings["Temperature"]?.number, kelvin > 0 {
                mired += 1_000_000 / 5500 - 1_000_000 / kelvin
            }
            tint += number("Tint")
        }
        var gain = SIMD3(exp(mired * 0.0035), exp(-tint * 0.0025), exp(-mired * 0.0035))
        gain /= Self.luma(gain)
        linearGain = gain * pow(2, number("Exposure2012"))

        // Dehaze, globally rather than by estimating haze per region: more
        // contrast, deeper blacks, a little more colour (or the reverse).
        let dehaze = number("Dehaze") / 100
        contrast = number("Contrast2012") / 100 + (isVivid ? 0.1 : 0) + dehaze * 0.35
        highlights = number("Highlights2012") / 100
        shadows = number("Shadows2012") / 100
        whites = number("Whites2012") / 100
        blacks = number("Blacks2012") / 100 - dehaze * 0.3

        parametric = ParametricCurve(settings: settings)
        master = PointCurve(settings["ToneCurvePV2012"]?.list)
        red = PointCurve(settings["ToneCurvePV2012Red"]?.list)
        green = PointCurve(settings["ToneCurvePV2012Green"]?.list)
        blue = PointCurve(settings["ToneCurvePV2012Blue"]?.list)

        grayMix = Self.hueNames.map { number("GrayMixer\($0)") / 100 }
        hueShift = Self.hueNames.map { number("HueAdjustment\($0)") / 100 }
        saturationShift = Self.hueNames.map { number("SaturationAdjustment\($0)") / 100 }
        luminanceShift = Self.hueNames.map { number("LuminanceAdjustment\($0)") / 100 }
        hasHSL = (hueShift + saturationShift + luminanceShift).contains { $0 != 0 }
        saturation = (1 + number("Saturation") / 100) * (isVivid ? 1.12 : 1) * (1 + dehaze * 0.2)
        vibrance = number("Vibrance") / 100

        // Color Grading, or the older Split Toning it replaced.
        func grade(_ range: Grade.Range, hue: String, saturation: String, luminance: String? = nil) -> Grade? {
            let strength = number(saturation) / 100
            let lum = luminance.map { number($0) / 100 } ?? 0
            guard strength != 0 || lum != 0 else { return nil }
            let color = Self.rgb(hue: number(hue), saturation: 1, value: 1)
            return Grade(range: range, tint: color - Self.luma(color), saturation: strength, luminance: lum)
        }
        var grades = [
            grade(.shadows, hue: "ColorGradeShadowHue", saturation: "ColorGradeShadowSat", luminance: "ColorGradeShadowLum"),
            grade(.midtones, hue: "ColorGradeMidtoneHue", saturation: "ColorGradeMidtoneSat", luminance: "ColorGradeMidtoneLum"),
            grade(.highlights, hue: "ColorGradeHighlightHue", saturation: "ColorGradeHighlightSat", luminance: "ColorGradeHighlightLum"),
            grade(.global, hue: "ColorGradeGlobalHue", saturation: "ColorGradeGlobalSat", luminance: "ColorGradeGlobalLum"),
        ].compactMap(\.self)
        if grades.isEmpty {
            grades = [
                grade(.shadows, hue: "SplitToningShadowHue", saturation: "SplitToningShadowSaturation"),
                grade(.highlights, hue: "SplitToningHighlightHue", saturation: "SplitToningHighlightSaturation"),
            ].compactMap(\.self)
            gradeBalance = number("SplitToningBalance") / 100
        } else {
            gradeBalance = number("ColorGradeBalance") / 100
        }
        self.grades = grades
        gradeBlending = number("ColorGradeBlending", 50) / 100

        clarity = number("Clarity2012") / 100
        texture = number("Texture") / 100
        let vignetteAmount = number("PostCropVignetteAmount") / 100
        vignette = vignetteAmount == 0 ? nil : Vignette(
            amount: vignetteAmount,
            midpoint: number("PostCropVignetteMidpoint", 50) / 100,
            feather: number("PostCropVignetteFeather", 50) / 100
        )
        let grainAmount = number("GrainAmount") / 100
        grain = grainAmount <= 0 ? nil : Grain(amount: grainAmount, size: number("GrainSize", 25) / 100)

        isIdentity = clarity == 0 && texture == 0 && vignette == nil && grain == nil && Self.samples.allSatisfy { sample in
            let difference = apply(sample) - sample
            return max(abs(difference.x), abs(difference.y), abs(difference.z)) < 0.5 / 255
        }
    }

    private static let samples: [SIMD3<Double>] = {
        let steps = [0, 0.2, 0.45, 0.7, 1.0]
        return steps.flatMap { r in steps.flatMap { g in steps.map { b in SIMD3(r, g, b) } } }
    }()

    // MARK: - Per-pixel colour

    func apply(_ input: SIMD3<Double>) -> SIMD3<Double> {
        var color = input

        if linearGain != SIMD3(repeating: 1) {
            color = Self.toGamma(Self.toLinear(color) * linearGain)
            color = color.clamped(lowerBound: .zero, upperBound: SIMD3(repeating: 1))
        }

        if isMonochrome {
            let (hue, sat, _) = Self.hsv(color)
            let mix = zip(Self.hueWeights(hue), grayMix).reduce(0) { $0 + $1.0 * $1.1 }
            color = SIMD3(repeating: Self.luma(color) + mix * sat * 0.35)
        }

        color = SIMD3(tone(color.x), tone(color.y), tone(color.z))
        color = SIMD3(parametric(color.x), parametric(color.y), parametric(color.z))
        color = SIMD3(red(master(color.x)), green(master(color.y)), blue(master(color.z)))
        color = color.clamped(lowerBound: .zero, upperBound: SIMD3(repeating: 1))

        if !isMonochrome {
            if hasHSL { color = adjustHSL(color) }
            if saturation != 1 || vibrance != 0 {
                let gray = Self.luma(color)
                let chroma = color.max() - color.min()
                // Vibrance favours the less saturated colours.
                let factor = saturation * (1 + vibrance * (1 - chroma))
                color = SIMD3(repeating: gray) + (color - gray) * max(factor, 0)
            }
        }

        if !grades.isEmpty { color = applyGrades(color) }
        return color.clamped(lowerBound: .zero, upperBound: SIMD3(repeating: 1))
    }

    /// Contrast, Highlights, Shadows, Whites and Blacks as one tone curve.
    private func tone(_ x: Double) -> Double {
        var y = x
        if contrast != 0 {
            // An S-curve pivoting on mid-grey with fixed ends; ±100 changes
            // the mid-tone slope by ±60%.
            let s = y - sin(2 * .pi * y) / (2 * .pi)
            y += contrast * 0.6 * (s - y)
        }
        y += highlights * 0.18 * Self.bump(y, from: 0.35, to: 1.05)
        y += shadows * 0.18 * Self.bump(y, from: -0.05, to: 0.6)
        y += whites * 0.12 * Self.smoothstep(0.45, 1, y)
        y += blacks * 0.12 * (1 - Self.smoothstep(0, 0.55, y))
        return y
    }

    private func adjustHSL(_ color: SIMD3<Double>) -> SIMD3<Double> {
        var (hue, sat, value) = Self.hsv(color)
        guard sat > 0.001 else { return color }
        let weights = Self.hueWeights(hue)
        func weighted(_ values: [Double]) -> Double {
            zip(weights, values).reduce(0) { $0 + $1.0 * $1.1 }
        }
        hue += weighted(hueShift) * 30
        sat = min(sat * (1 + weighted(saturationShift)), 1)
        value = min(value * (1 + weighted(luminanceShift) * 0.5 * sat), 1)
        return Self.rgb(hue: hue, saturation: sat, value: value)
    }

    private func applyGrades(_ color: SIMD3<Double>) -> SIMD3<Double> {
        let lum = Self.luma(color)
        // Balance moves the shadow / highlight split; Blending widens the overlap.
        let pivot = 0.5 - gradeBalance * 0.3
        let width = 0.15 + 0.7 * gradeBlending
        let highlightWeight = Self.smoothstep(pivot - width / 2, pivot + width / 2, lum)
        var result = color
        for grade in grades {
            let weight = switch grade.range {
            case .shadows: 1 - highlightWeight
            case .highlights: highlightWeight
            case .midtones: 4 * lum * (1 - lum)
            case .global: 1.0
            }
            result += grade.tint * grade.saturation * weight * 0.3 + SIMD3(repeating: grade.luminance * weight * 0.2)
        }
        return result
    }

    // MARK: - 3D lookup table

    /// RGBA float cube for `CIColorCubeWithColorSpace`, red varying fastest.
    func cubeData(dimension: Int) -> Data {
        Self.cubeData(dimension: dimension, apply)
    }

    /// The cube for any colour-to-colour function.
    static func cubeData(dimension: Int, _ apply: (SIMD3<Double>) -> SIMD3<Double>) -> Data {
        var values: [Float] = []
        values.reserveCapacity(dimension * dimension * dimension * 4)
        let scale = 1 / Double(dimension - 1)
        for b in 0..<dimension {
            for g in 0..<dimension {
                for r in 0..<dimension {
                    let color = apply(SIMD3(Double(r), Double(g), Double(b)) * scale)
                    values += [Float(color.x), Float(color.y), Float(color.z), 1]
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    // MARK: - Colour maths

    /// Rec. 601 weights on gamma-encoded values: close to how Lightroom's
    /// default black & white conversion weighs the channels.
    private static func luma(_ color: SIMD3<Double>) -> Double {
        0.299 * color.x + 0.587 * color.y + 0.114 * color.z
    }

    private static func toLinear(_ color: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(toLinear(color.x), toLinear(color.y), toLinear(color.z))
    }

    private static func toLinear(_ x: Double) -> Double {
        x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }

    private static func toGamma(_ color: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(toGamma(color.x), toGamma(color.y), toGamma(color.z))
    }

    private static func toGamma(_ x: Double) -> Double {
        x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055
    }

    private static func hsv(_ color: SIMD3<Double>) -> (hue: Double, saturation: Double, value: Double) {
        let maximum = color.max(), minimum = color.min(), delta = maximum - minimum
        guard delta > 0 else { return (0, 0, maximum) }
        var hue: Double
        if maximum == color.x {
            hue = (color.y - color.z) / delta
        } else if maximum == color.y {
            hue = 2 + (color.z - color.x) / delta
        } else {
            hue = 4 + (color.x - color.y) / delta
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (hue, delta / maximum, maximum)
    }

    private static func rgb(hue: Double, saturation: Double, value: Double) -> SIMD3<Double> {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let chroma = value * saturation
        let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let base: SIMD3<Double> = switch Int(h) {
        case 0: SIMD3(chroma, x, 0)
        case 1: SIMD3(x, chroma, 0)
        case 2: SIMD3(0, chroma, x)
        case 3: SIMD3(0, x, chroma)
        case 4: SIMD3(x, 0, chroma)
        default: SIMD3(chroma, 0, x)
        }
        return base + (value - chroma)
    }

    /// How much each of the eight bands owns `hue`: a smooth hand-over
    /// between the two nearest band centres.
    private static func hueWeights(_ hue: Double) -> [Double] {
        var weights = Array(repeating: 0.0, count: hueCenters.count)
        let i = hueCenters.lastIndex { $0 <= hue } ?? hueCenters.count - 1
        let next = (i + 1) % hueCenters.count
        let start = hueCenters[i]
        let end = next == 0 ? 360 : hueCenters[next]
        let t = smoothstep(0, 1, (hue - start) / (end - start))
        weights[i] = 1 - t
        weights[next] += t
        return weights
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// 0 outside `from…to`, rising smoothly to 1 in the middle.
    private static func bump(_ x: Double, from lower: Double, to upper: Double) -> Double {
        guard x > lower, x < upper else { return 0 }
        let s = sin(.pi * (x - lower) / (upper - lower))
        return s * s
    }
}

/// Lightroom's point curve: a smooth spline through up to 16 points on a
/// 0–255 grid, flat beyond the first and last point.
private nonisolated struct PointCurve: Sendable {
    private let xs: [Double]
    private let ys: [Double]
    /// Second derivatives at each point (natural cubic spline).
    private let m: [Double]

    init(_ flat: [Double]?) {
        var points: [(x: Double, y: Double)] = []
        if let flat {
            for pair in stride(from: 0, to: flat.count - 1, by: 2) {
                points.append((flat[pair] / 255, flat[pair + 1] / 255))
            }
        }
        points.sort { $0.x < $1.x }
        // Two points with the same x would divide by zero below.
        points = points.reduce(into: []) { result, point in
            if let last = result.last, point.x - last.x < 1e-6 { return }
            result.append(point)
        }
        if points.count < 2 { points = [(0, 0), (1, 1)] }

        xs = points.map(\.x)
        ys = points.map(\.y)
        m = Self.secondDerivatives(xs: xs, ys: ys)
    }

    func callAsFunction(_ x: Double) -> Double {
        if x <= xs[0] { return ys[0] }
        if x >= xs[xs.count - 1] { return ys[ys.count - 1] }
        var i = 0
        while x > xs[i + 1] { i += 1 }
        let h = xs[i + 1] - xs[i]
        let a = (xs[i + 1] - x) / h
        let b = (x - xs[i]) / h
        return a * ys[i] + b * ys[i + 1] + ((a * a * a - a) * m[i] + (b * b * b - b) * m[i + 1]) * h * h / 6
    }

    /// Solves the tridiagonal system for a natural spline (zero curvature at
    /// both ends). Two points give all zeros: a straight line.
    private static func secondDerivatives(xs: [Double], ys: [Double]) -> [Double] {
        let n = xs.count
        var m = Array(repeating: 0.0, count: n)
        guard n > 2 else { return m }
        var u = Array(repeating: 0.0, count: n)
        for i in 1..<(n - 1) {
            let sig = (xs[i] - xs[i - 1]) / (xs[i + 1] - xs[i - 1])
            let p = sig * m[i - 1] + 2
            m[i] = (sig - 1) / p
            let slopeChange = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) - (ys[i] - ys[i - 1]) / (xs[i] - xs[i - 1])
            u[i] = (6 * slopeChange / (xs[i + 1] - xs[i - 1]) - sig * u[i - 1]) / p
        }
        m[n - 1] = 0
        for i in stride(from: n - 2, through: 0, by: -1) {
            m[i] = m[i] * m[i + 1] + u[i]
        }
        return m
    }
}

/// Approximates Lightroom's parametric curve (Highlights / Lights / Darks /
/// Shadows, with three movable split points). Each slider lifts or lowers a
/// smooth bump over its zone, reaching half way into the neighbouring zones;
/// black and white stay fixed.
private nonisolated struct ParametricCurve: Sendable {
    private struct Zone {
        let lower: Double
        let upper: Double
        /// -1…1.
        let amount: Double
    }

    private let zones: [Zone]

    init(settings: [String: PresetValue]) {
        func number(_ key: String, _ fallback: Double) -> Double {
            settings[key]?.number ?? fallback
        }
        let splits = [
            0,
            number("ParametricShadowSplit", 25) / 100,
            number("ParametricMidtoneSplit", 50) / 100,
            number("ParametricHighlightSplit", 75) / 100,
            1,
        ]
        let amounts = ["ParametricShadows", "ParametricDarks", "ParametricLights", "ParametricHighlights"]
            .map { number($0, 0) / 100 }

        zones = amounts.indices.compactMap { i in
            guard amounts[i] != 0 else { return nil }
            let lower = i == 0 ? 0 : splits[i] - (splits[i] - splits[i - 1]) / 2
            let upper = i == 3 ? 1 : splits[i + 1] + (splits[i + 2] - splits[i + 1]) / 2
            return Zone(lower: lower, upper: upper, amount: amounts[i])
        }
    }

    func callAsFunction(_ x: Double) -> Double {
        var y = x
        for zone in zones where x > zone.lower && x < zone.upper {
            let t = (x - zone.lower) / (zone.upper - zone.lower)
            let bump = sin(.pi * t)
            // Full slider moves the middle of its zone by about a third of the zone's width.
            y += zone.amount * bump * bump * (zone.upper - zone.lower) * 0.35
        }
        return min(max(y, 0), 1)
    }
}
