import Foundation

/// Colour-space arithmetic, not an Adobe camera/profile implementation.
nonisolated enum ColorMath {
    struct Matrix: Sendable, Hashable {
        let r, g, b: SIMD3<Double>
        static let identity = Matrix(r: SIMD3(1, 0, 0), g: SIMD3(0, 1, 0), b: SIMD3(0, 0, 1))

        func apply(_ v: SIMD3<Double>) -> SIMD3<Double> {
            SIMD3(dot(r, v), dot(g, v), dot(b, v))
        }
        func multiplied(by other: Matrix) -> Matrix {
            let c0 = SIMD3(other.r.x, other.g.x, other.b.x)
            let c1 = SIMD3(other.r.y, other.g.y, other.b.y)
            let c2 = SIMD3(other.r.z, other.g.z, other.b.z)
            return Matrix(r: SIMD3(dot(r, c0), dot(r, c1), dot(r, c2)),
                          g: SIMD3(dot(g, c0), dot(g, c1), dot(g, c2)),
                          b: SIMD3(dot(b, c0), dot(b, c1), dot(b, c2)))
        }
        var inverse: Matrix {
            let a = r.x, c = r.z, d = g.x, e = g.y, f = g.z, h = b.y, i = b.z, j = r.y, k = b.x
            let determinant = a * (e * i - f * h) - j * (d * i - f * k) + c * (d * h - e * k)
            return Matrix(r: SIMD3(e * i - f * h, c * h - j * i, j * f - c * e) / determinant,
                          g: SIMD3(f * k - d * i, a * i - c * k, c * d - a * f) / determinant,
                          b: SIMD3(d * h - e * k, j * k - a * h, a * e - j * d) / determinant)
        }
    }

    static func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
    static let d65 = SIMD3(0.3127 / 0.3290, 1, (1 - 0.3127 - 0.3290) / 0.3290)
    static let sRGBToXYZ = matrix(primaries: [(0.64, 0.33), (0.30, 0.60), (0.15, 0.06)])
    static let rec2020ToXYZ = matrix(primaries: [(0.708, 0.292), (0.170, 0.797), (0.131, 0.046)])
    static let sRGBToRec2020 = rec2020ToXYZ.inverse.multiplied(by: sRGBToXYZ)
    static let rec2020ToSRGB = sRGBToRec2020.inverse

    private static func matrix(primaries: [(Double, Double)]) -> Matrix {
        let columns = primaries.map { x, y in SIMD3(x / y, 1, (1 - x - y) / y) }
        let unscaled = Matrix(r: SIMD3(columns[0].x, columns[1].x, columns[2].x),
                              g: SIMD3(1, 1, 1), b: SIMD3(columns[0].z, columns[1].z, columns[2].z))
        let factors = unscaled.inverse.apply(d65)
        return Matrix(r: unscaled.r * factors, g: unscaled.g * factors, b: unscaled.b * factors)
    }

    /// JPEG temperature gains are defined in linear sRGB, not Rec.2020 RGB.
    /// Change their basis before applying them to the wide working-space graph.
    static func workingGain(_ gain: SIMD3<Double>) -> Matrix {
        let diagonal = Matrix(r: SIMD3(gain.x, 0, 0), g: SIMD3(0, gain.y, 0), b: SIMD3(0, 0, gain.z))
        if gain.x == gain.y && gain.y == gain.z { return diagonal }
        return sRGBToRec2020.multiplied(by: diagonal).multiplied(by: rec2020ToSRGB)
    }

    static func toLinear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
    static func toGamma(_ value: Double) -> Double { value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055 }
    static func linear(_ color: SIMD3<Double>) -> SIMD3<Double> { SIMD3(toLinear(color.x), toLinear(color.y), toLinear(color.z)) }
    static func gamma(_ color: SIMD3<Double>) -> SIMD3<Double> { SIMD3(toGamma(color.x), toGamma(color.y), toGamma(color.z)) }
    static func luminance(_ color: SIMD3<Double>) -> Double { dot(color, sRGBToXYZ.g) }

    /// Retain luminance and hue direction by compressing all chroma together,
    /// rather than clipping three channels independently at the gamut boundary.
    static func compressChroma(_ color: SIMD3<Double>, gray: Double) -> SIMD3<Double> {
        let y = min(1, max(0, gray))
        let chroma = color - SIMD3(repeating: y)
        var factor = 1.0
        for component in [chroma.x, chroma.y, chroma.z] {
            if component > 0 { factor = min(factor, (1 - y) / component) }
            if component < 0 { factor = min(factor, -y / component) }
        }
        return SIMD3(repeating: y) + chroma * max(0, factor)
    }

    static func withLuminance(_ color: SIMD3<Double>, target: Double) -> SIMD3<Double> {
        let linear = linear(color)
        let old = luminance(linear)
        let y = min(1, max(0, target))
        let scaled = old > 1e-12 ? linear * (y / old) : SIMD3(repeating: y)
        return gamma(compressChroma(scaled, gray: y))
    }

    /// Closest non-decreasing samples in squared error (equal-weight PAVA).
    /// Only the global parametric approximation uses this, not user RGB curves.
    static func monotoneProjection(_ values: [Double]) -> [Double] {
        var levels: [Double] = [], counts: [Int] = []
        for value in values {
            levels.append(value)
            counts.append(1)
            while levels.count > 1 && levels[levels.count - 2] > levels[levels.count - 1] {
                let last = levels.removeLast(), lastCount = counts.removeLast()
                let previous = levels.removeLast(), previousCount = counts.removeLast()
                let count = lastCount + previousCount
                levels.append((last * Double(lastCount) + previous * Double(previousCount)) / Double(count))
                counts.append(count)
            }
        }
        return zip(levels, counts).flatMap { level, count in Array(repeating: level, count: count) }
    }

    static func labD65(_ sRGB: SIMD3<Double>) -> SIMD3<Double> {
        let xyz = sRGBToXYZ.apply(linear(sRGB)) / d65
        func f(_ x: Double) -> Double { x > 216.0 / 24389 ? cbrt(x) : (24389.0 / 27 * x + 16) / 116 }
        return SIMD3(116 * f(xyz.y) - 16, 500 * (f(xyz.x) - f(xyz.y)), 200 * (f(xyz.y) - f(xyz.z)))
    }
}
