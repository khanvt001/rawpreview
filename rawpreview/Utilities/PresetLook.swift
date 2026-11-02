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
/// Adobe doesn't publish Camera Raw's maths. This is the display-referred
/// creative stage after the selected JPEG/RAW decode, so each operation is a
/// reasonable likeness of its Lightroom slider, not a reproduction. Working
/// values are gamma-encoded sRGB in 0…1; exposure and white balance are
/// applied in linear light.
nonisolated struct PresetLook: Sendable, Hashable {
    struct Vignette: Sendable, Hashable {
        /// -1 (dark corners) … 1 (light corners).
        let amount: Double
        /// 0…1: how far in the falloff starts.
        let midpoint: Double
        /// 0…1: how soft the falloff is.
        let feather: Double
        /// -1 (rectangular) … 0 (an ellipse following the frame) … 1 (a circle).
        var roundness: Double = 0
        var style: Style = .highlightPriority
        /// 0…1: how much Highlight Priority keeps bright areas bright.
        var highlightContrast: Double = 0

        /// Lightroom's PostCropVignetteStyle values.
        enum Style: Int, Sendable, Hashable {
            case highlightPriority = 1, colorPriority = 2, paintOverlay = 3
        }
    }

    struct Grain: Sendable, Hashable {
        /// 0…1.
        let amount: Double
        /// 0…1 (Lightroom's default 25 is 0.25).
        let size: Double
        /// 0…1 (Lightroom's Roughness, default 50): how uneven the grain is.
        var roughness: Double = 0.5
    }

    /// Black & white conversion with the B&W mix.
    let isMonochrome: Bool
    /// Local contrast, -1…1, at large (clarity) and fine (texture) scale.
    private(set) var clarity: Double
    private(set) var texture: Double
    /// -1…1, applied per region by the renderer from a haze estimate.
    private(set) var dehaze: Double
    private(set) var vignette: Vignette?
    private(set) var grain: Grain?
    /// Applying this look changes nothing.
    private(set) var isIdentity = false

    let linearGain: SIMD3<Double>
    private let contrast, highlights, shadows, whites, blacks: Double
    private let hasTone: Bool
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
    /// Camera Calibration's primaries, in linear light (nil: unchanged).
    private let calibration: ColorMath.Matrix?
    /// -1 (green) … 1 (magenta), in the shadows only.
    private let shadowTint: Double

    private struct Grade: Sendable, Hashable {
        enum Range: Hashable { case shadows, midtones, highlights, global }
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
        let settings = PresetNormalization.normalize(settings)
        func number(_ key: String, _ fallback: Double = 0) -> Double {
            let value = settings[key]?.number ?? fallback
            if key == "Exposure2012" { return min(16, max(-16, value)) }
            if key == "Temperature" { return min(50_000, max(2000, value)) }
            if key == "Tint" || key == "IncrementalTint" { return min(150, max(-150, value)) }
            if key.contains("Hue") && !key.hasPrefix("HueAdjustment") { return value.truncatingRemainder(dividingBy: 360) }
            return min(100, max(-100, value))
        }

        if case .bool(true) = settings["ConvertToGrayscale"] {
            isMonochrome = true
        } else {
            isMonochrome = false
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
        if mired == 0 && tint == 0 {
            linearGain = SIMD3(repeating: pow(2, number("Exposure2012")))
        } else {
            var gain = SIMD3(exp(mired * 0.0035), exp(-tint * 0.0025), exp(-mired * 0.0035))
            gain /= Self.luma(gain)
            linearGain = gain * pow(2, number("Exposure2012"))
        }

        // Dehaze is spatial (see DevelopRenderer), not part of the colour LUT.
        dehaze = number("Dehaze") / 100
        contrast = number("Contrast2012") / 100 + (isVivid ? 0.1 : 0)
        highlights = number("Highlights2012") / 100
        shadows = number("Shadows2012") / 100
        whites = number("Whites2012") / 100
        blacks = number("Blacks2012") / 100

        parametric = ParametricCurve(settings: settings)
        hasTone = contrast != 0 || highlights != 0 || shadows != 0 || whites != 0 || blacks != 0 || !parametric.isIdentity
        master = PointCurve(settings["ToneCurvePV2012"]?.list)
        red = PointCurve(settings["ToneCurvePV2012Red"]?.list)
        green = PointCurve(settings["ToneCurvePV2012Green"]?.list)
        blue = PointCurve(settings["ToneCurvePV2012Blue"]?.list)

        grayMix = Self.hueNames.map { number("GrayMixer\($0)") / 100 }
        hueShift = Self.hueNames.map { number("HueAdjustment\($0)") / 100 }
        saturationShift = Self.hueNames.map { number("SaturationAdjustment\($0)") / 100 }
        luminanceShift = Self.hueNames.map { number("LuminanceAdjustment\($0)") / 100 }
        hasHSL = (hueShift + saturationShift + luminanceShift).contains { $0 != 0 }
        saturation = (1 + number("Saturation") / 100) * (isVivid ? 1.12 : 1)
        vibrance = number("Vibrance") / 100

        // Aliases are normalized per component, not by choosing one whole
        // family. A modern midtone must not discard legacy shadows/highlights.
        func grade(_ range: Grade.Range, hue: String, saturation: String, luminance: String? = nil) -> Grade? {
            let strength = number(saturation) / 100
            let lum = luminance.map { number($0) / 100 } ?? 0
            guard strength != 0 || lum != 0 else { return nil }
            let color = Self.rgb(hue: number(hue), saturation: 1, value: 1)
            return Grade(range: range, tint: color - Self.luma(color), saturation: strength, luminance: lum)
        }
        grades = [
            grade(.shadows, hue: "ColorGradeShadowHue", saturation: "ColorGradeShadowSat", luminance: "ColorGradeShadowLum"),
            grade(.midtones, hue: "ColorGradeMidtoneHue", saturation: "ColorGradeMidtoneSat", luminance: "ColorGradeMidtoneLum"),
            grade(.highlights, hue: "ColorGradeHighlightHue", saturation: "ColorGradeHighlightSat", luminance: "ColorGradeHighlightLum"),
            grade(.global, hue: "ColorGradeGlobalHue", saturation: "ColorGradeGlobalSat", luminance: "ColorGradeGlobalLum"),
        ].compactMap(\.self)
        gradeBalance = number("ColorGradeBalance") / 100
        gradeBlending = number("ColorGradeBlending", 50) / 100
        calibration = Self.calibrationMatrix(
            hue: ["Red", "Green", "Blue"].map { number("\($0)Hue") / 100 },
            saturation: ["Red", "Green", "Blue"].map { number("\($0)Saturation") / 100 }
        )
        shadowTint = number("ShadowTint") / 100

        clarity = number("Clarity2012") / 100
        texture = number("Texture") / 100
        let vignetteAmount = number("PostCropVignetteAmount") / 100
        vignette = vignetteAmount == 0 ? nil : Vignette(
            amount: vignetteAmount,
            midpoint: number("PostCropVignetteMidpoint", 50) / 100,
            feather: number("PostCropVignetteFeather", 50) / 100,
            roundness: number("PostCropVignetteRoundness") / 100,
            style: Vignette.Style(rawValue: Int(number("PostCropVignetteStyle", 1).rounded())) ?? .highlightPriority,
            highlightContrast: max(0, number("PostCropVignetteHighlightContrast")) / 100
        )
        let grainAmount = number("GrainAmount") / 100
        // XMP stores Roughness as GrainFrequency.
        let roughness = settings["GrainFrequency"] != nil ? number("GrainFrequency", 50) : number("GrainRoughness", 50)
        grain = grainAmount <= 0 ? nil : Grain(amount: grainAmount, size: number("GrainSize", 25) / 100, roughness: roughness / 100)

        // Do not discard real edits based on half an 8-bit code value:
        // the production graph and 16-bit output have finer precision.
        isIdentity = clarity == 0 && texture == 0 && dehaze == 0 && vignette == nil && grain == nil
            && linearGain == SIMD3(repeating: 1) && !isMonochrome && !hasTone
            && master.isIdentity && red.isIdentity && green.isIdentity && blue.isIdentity
            && !hasHSL && saturation == 1 && vibrance == 0 && grades.isEmpty
            && calibration == nil && shadowTint == 0
    }

    /// Only per-pixel colour affects a LUT. Spatial effects and identity's
    /// sampling heuristic must not create different colour-cache entries.
    var colorKey: PresetLook {
        var key = self
        key.clarity = 0
        key.texture = 0
        key.dehaze = 0
        key.vignette = nil
        key.grain = nil
        key.isIdentity = false
        return key
    }

    // MARK: - Per-pixel colour

    func apply(_ input: SIMD3<Double>) -> SIMD3<Double> {
        var color = input

        // Calibration belongs to the profile, so it runs first.
        if calibration != nil || shadowTint != 0 { color = calibrate(color) }

        if linearGain != SIMD3(repeating: 1) {
            color = Self.toGamma(Self.toLinear(color) * linearGain)
            color = color.clamped(lowerBound: .zero, upperBound: SIMD3(repeating: 1))
        }

        if isMonochrome {
            let (hue, sat, _) = Self.hsv(color)
            let mix = zip(Self.hueWeights(hue), grayMix).reduce(0) { $0 + $1.0 * $1.1 }
            color = SIMD3(repeating: Self.luma(color) + mix * sat * 0.35)
        }

        // Basic/parametric tone works on luminance. Scaling linear RGB
        // together preserves chromaticity until gamut compression is needed.
        if hasTone {
            let luminance = ColorMath.luminance(ColorMath.linear(color))
            let mapped = parametric(tone(ColorMath.toGamma(max(0, luminance))))
            color = ColorMath.withLuminance(color, target: ColorMath.toLinear(min(1, max(0, mapped))))
        }
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
        return ColorMath.compressChroma(color, gray: Self.luma(color))
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
        let originalY = ColorMath.luminance(ColorMath.linear(color))
        let originalSat = sat
        hue += weighted(hueShift) * 30
        sat = min(max(sat * (1 + weighted(saturationShift)), 0), 1)
        value = max(0, min(1, value))
        var changed = Self.rgb(hue: hue, saturation: sat, value: value)
        // Hue/saturation sliders do not accidentally become a Value slider.
        changed = ColorMath.withLuminance(changed, target: originalY)
        let gammaY = ColorMath.toGamma(originalY)
        let target = gammaY + weighted(luminanceShift) * 0.5 * originalSat * sin(.pi * gammaY)
        return ColorMath.withLuminance(changed, target: ColorMath.toLinear(min(1, max(0, target))))
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
        return ColorMath.compressChroma(result, gray: Self.luma(result))
    }

    // MARK: - 3D lookup table

    /// RGBA float cube for `CIColorCubeWithColorSpace`, red varying fastest.
    func cubeData(dimension: Int) -> Data {
        Self.cubeData(dimension: dimension, apply)
    }

    /// The cube for any colour-to-colour function.
    /// Blue slices are filled in parallel: a 33³ table was ~560 ms on one
    /// core, building in place instead of appending per sample. Cancellation
    /// is checked around the build, as worker threads don't see the task.
    static func cubeData(dimension: Int, _ apply: (SIMD3<Double>) -> SIMD3<Double>) -> Data {
        guard !Task.isCancelled else { return Data() }
        let slice = dimension * dimension * 4
        var values = [Float](repeating: 1, count: dimension * slice)
        let scale = 1 / Double(dimension - 1)
        values.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let output = buffer
            DispatchQueue.concurrentPerform(iterations: dimension) { b in
                var index = b * slice
                for g in 0..<dimension {
                    for r in 0..<dimension {
                        let color = apply(SIMD3(Double(r), Double(g), Double(b)) * scale)
                        output[index] = Float(color.x)
                        output[index + 1] = Float(color.y)
                        output[index + 2] = Float(color.z)
                        index += 4
                    }
                }
            }
        }
        guard !Task.isCancelled else { return Data() }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    // MARK: - Colour maths

    /// Each primary's Hue moves it towards the next one (red → yellow,
    /// green → cyan, blue → purple) or back; Saturation scales it about its
    /// own luminance. Rows are rescaled so white stays white. An
    /// approximation of Lightroom's Calibration panel, not its profile maths.
    private static func calibrationMatrix(hue: [Double], saturation: [Double]) -> ColorMath.Matrix? {
        guard (hue + saturation).contains(where: { $0 != 0 }) else { return nil }
        let weights = ColorMath.sRGBToXYZ.g
        var columns: [SIMD3<Double>] = []
        for index in 0..<3 {
            func primary(_ i: Int) -> SIMD3<Double> {
                var unit = SIMD3<Double>(repeating: 0)
                unit[(i + 3) % 3] = 1
                return unit
            }
            var column = primary(index)
            let shift = hue[index]
            column += (shift > 0 ? primary(index + 1) : primary(index - 1)) * abs(shift) * 0.35
            let luminance = ColorMath.dot(column, weights)
            column = SIMD3(repeating: luminance) + (column - luminance) * (1 + saturation[index] * 0.5)
            columns.append(column)
        }
        let rows = (0..<3).map { row in
            let values = SIMD3(columns[0][row], columns[1][row], columns[2][row])
            return values / (values.x + values.y + values.z)
        }
        return ColorMath.Matrix(r: rows[0], g: rows[1], b: rows[2])
    }

    private func calibrate(_ color: SIMD3<Double>) -> SIMD3<Double> {
        var linear = Self.toLinear(color)
        if let calibration { linear = calibration.apply(linear) }
        if shadowTint != 0 {
            let shadows = 1 - Self.smoothstep(0, 0.5, Self.luma(color))
            let tint = shadowTint * shadows
            linear *= SIMD3(exp(tint * 0.15), exp(-tint * 0.3), exp(tint * 0.15))
        }
        return Self.toGamma(linear.clamped(lowerBound: .zero, upperBound: SIMD3(repeating: 1)))
    }

    /// Display-domain luma for creative saturation/grading, using sRGB's
    /// declared primary weights; Basic tone uses linear luminance instead.
    private static func luma(_ color: SIMD3<Double>) -> Double {
        ColorMath.dot(color, ColorMath.sRGBToXYZ.g)
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
private nonisolated struct PointCurve: Sendable, Hashable {
    private let xs: [Double]
    private let ys: [Double]
    /// Shape-preserving Hermite slopes. Monotone input nodes must not
    /// introduce an overshoot, a reversal or a halo in a smooth gradient.
    private let slopes: [Double]
    let isIdentity: Bool

    init(_ flat: [Double]?) {
        var points: [(x: Double, y: Double)] = []
        if let flat, flat.count >= 4, flat.count.isMultiple(of: 2), flat.allSatisfy({ $0.isFinite && (0...255).contains($0) }) {
            for pair in stride(from: 0, to: flat.count, by: 2) {
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
        slopes = Self.tangents(xs: xs, ys: ys)
        isIdentity = xs.first == 0 && xs.last == 1 && zip(xs, ys).allSatisfy { pair in pair.0 == pair.1 }
    }

    func callAsFunction(_ x: Double) -> Double {
        if isIdentity { return x }
        if x <= xs[0] { return ys[0] }
        if x >= xs[xs.count - 1] { return ys[ys.count - 1] }
        var i = 0
        while x > xs[i + 1] { i += 1 }
        let h = xs[i + 1] - xs[i]
        let t = (x - xs[i]) / h
        return (2 * t * t * t - 3 * t * t + 1) * ys[i]
            + (t * t * t - 2 * t * t + t) * h * slopes[i]
            + (-2 * t * t * t + 3 * t * t) * ys[i + 1]
            + (t * t * t - t * t) * h * slopes[i + 1]
    }

    private static func tangents(xs: [Double], ys: [Double]) -> [Double] {
        let n = xs.count
        let h = (0..<(n - 1)).map { xs[$0 + 1] - xs[$0] }
        let d = (0..<(n - 1)).map { (ys[$0 + 1] - ys[$0]) / h[$0] }
        guard n > 2 else { return [d[0], d[0]] }
        var slopes = Array(repeating: 0.0, count: n)
        for i in 1..<(n - 1) where d[i - 1] * d[i] > 0 {
            let w1 = 2 * h[i] + h[i - 1], w2 = h[i] + 2 * h[i - 1]
            slopes[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
        }
        func endpoint(_ h0: Double, _ h1: Double, _ d0: Double, _ d1: Double) -> Double {
            let slope = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
            if slope * d0 <= 0 { return 0 }
            return d0 * d1 < 0 && abs(slope) > abs(3 * d0) ? 3 * d0 : slope
        }
        slopes[0] = endpoint(h[0], h[1], d[0], d[1])
        slopes[n - 1] = endpoint(h[n - 2], h[n - 3], d[n - 2], d[n - 3])
        return slopes
    }
}

/// Approximates Lightroom's parametric curve (Highlights / Lights / Darks /
/// Shadows, with three movable split points). Each slider lifts or lowers a
/// smooth bump over its zone, reaching half way into the neighbouring zones;
/// black and white stay fixed.
private nonisolated struct ParametricCurve: Sendable, Hashable {
    private struct Zone: Sendable, Hashable {
        let lower: Double
        let upper: Double
        /// -1…1.
        let amount: Double
    }

    private let samples: [Double]
    let isIdentity: Bool

    init(settings: [String: PresetValue]) {
        func number(_ key: String, _ fallback: Double) -> Double {
            settings[key]?.number ?? fallback
        }
        let middle = [number("ParametricShadowSplit", 25), number("ParametricMidtoneSplit", 50), number("ParametricHighlightSplit", 75)]
            .map { min(99, max(1, $0)) / 100 }.sorted()
        let splits = [0] + middle + [1]
        let amounts = ["ParametricShadows", "ParametricDarks", "ParametricLights", "ParametricHighlights"]
            .map { min(100, max(-100, number($0, 0))) / 100 }

        let zones: [Zone] = amounts.indices.compactMap { i in
            guard amounts[i] != 0 else { return nil }
            let lower = i == 0 ? 0 : splits[i] - (splits[i] - splits[i - 1]) / 2
            let upper = i == 3 ? 1 : splits[i + 1] + (splits[i + 2] - splits[i + 1]) / 2
            return Zone(lower: lower, upper: upper, amount: amounts[i])
        }
        isIdentity = zones.isEmpty
        if zones.isEmpty { samples = []; return }
        let raw = (0...1024).map { index -> Double in
            let x = Double(index) / 1024
            var y = x
            for zone in zones where x > zone.lower && x < zone.upper {
                let t = (x - zone.lower) / (zone.upper - zone.lower)
                let bump = sin(.pi * t)
                y += zone.amount * bump * bump * (zone.upper - zone.lower) * 0.35
            }
            return min(max(y, 0), 1)
        }
        samples = ColorMath.monotoneProjection(raw)
    }

    func callAsFunction(_ x: Double) -> Double {
        guard !isIdentity else { return x }
        let position = min(1, max(0, x)) * Double(samples.count - 1)
        let lower = min(samples.count - 2, Int(position))
        let fraction = position - Double(lower)
        return samples[lower] + (samples[lower + 1] - samples[lower]) * fraction
    }
}
