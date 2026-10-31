//
//  ToneLUT.swift
//  rawpreview
//

import Foundation

/// A preset's tone curves combined into one 8-bit table per channel, in the
/// order Lightroom applies them: parametric curve → point curve (RGB) →
/// per-channel point curves.
nonisolated struct ToneLUT: Sendable {
    let red: [UInt8]
    let green: [UInt8]
    let blue: [UInt8]

    /// Every table maps each value to itself, so rendering can be skipped.
    let isIdentity: Bool

    init(settings: [String: PresetValue]) {
        let parametric = ParametricCurve(settings: settings)
        let master = PointCurve(settings["ToneCurvePV2012"]?.list)
        let channels = ["Red", "Green", "Blue"].map { PointCurve(settings["ToneCurvePV2012\($0)"]?.list) }

        let tables = channels.map { channel in
            (0...255).map { index -> UInt8 in
                let value = channel(master(parametric(Double(index) / 255)))
                return UInt8((min(max(value, 0), 1) * 255).rounded())
            }
        }
        red = tables[0]
        green = tables[1]
        blue = tables[2]
        let identity = (0...255).map(UInt8.init)
        isIdentity = tables.allSatisfy { $0 == identity }
    }
}

/// Lightroom's point curve: a smooth spline through up to 16 points on a
/// 0–255 grid, flat beyond the first and last point.
private nonisolated struct PointCurve {
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
/// Shadows, with three movable split points). Adobe doesn't publish the exact
/// shape, so each slider lifts or lowers a smooth bump over its zone, reaching
/// half way into the neighbouring zones; black and white stay fixed.
private nonisolated struct ParametricCurve {
    /// (lower bound, upper bound, amount -1…1) per zone, darkest first.
    private let zones: [(lower: Double, upper: Double, amount: Double)]

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
            return (lower, upper, amounts[i])
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
