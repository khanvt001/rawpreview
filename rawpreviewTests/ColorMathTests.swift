import Testing
@testable import rawpreview

@Suite struct ColorMathTests {
    private func isClose(_ a: Double, _ b: Double, within tolerance: Double = 1e-9) -> Bool {
        abs(a - b) <= tolerance
    }

    private func isClose(_ a: SIMD3<Double>, _ b: SIMD3<Double>, within tolerance: Double = 1e-9) -> Bool {
        isClose(a.x, b.x, within: tolerance) && isClose(a.y, b.y, within: tolerance) && isClose(a.z, b.z, within: tolerance)
    }

    @Test(arguments: [0, 0.003, 0.04, 0.05, 0.18, 0.5, 1])
    func gammaAndLinearAreInverses(_ value: Double) {
        #expect(isClose(ColorMath.toGamma(ColorMath.toLinear(value)), value))
    }

    @Test func middleGrayHasTheExpectedLinearValue() {
        #expect(isClose(ColorMath.toLinear(0.5), 0.21404, within: 1e-5))
    }

    @Test func aMatrixTimesItsInverseIsTheIdentity() {
        let product = ColorMath.sRGBToRec2020.multiplied(by: ColorMath.rec2020ToSRGB)
        let identity = ColorMath.Matrix.identity
        #expect(isClose(product.r, identity.r) && isClose(product.g, identity.g) && isClose(product.b, identity.b))
    }

    @Test func whiteStaysWhiteBetweenColorSpaces() {
        #expect(isClose(ColorMath.sRGBToRec2020.apply(SIMD3(1, 1, 1)), SIMD3(1, 1, 1)))
    }

    @Test func sRGBWhiteHasALuminanceOfOne() {
        #expect(isClose(ColorMath.luminance(SIMD3(1, 1, 1)), 1))
    }

    @Test func aNeutralGainStaysDiagonal() {
        #expect(ColorMath.workingGain(SIMD3(2, 2, 2)) == ColorMath.Matrix(r: SIMD3(2, 0, 0), g: SIMD3(0, 2, 0), b: SIMD3(0, 0, 2)))
    }

    @Test func chromaCompressionStaysInGamutAroundTheGray() {
        let result = ColorMath.compressChroma(SIMD3(1.4, 0.5, -0.2), gray: 0.5)
        #expect(result.min() >= -1e-12 && result.max() <= 1 + 1e-12)
        #expect(result.x > result.y && result.y > result.z)
    }

    @Test func colorsInGamutPassThroughChromaCompression() {
        let color = SIMD3(0.6, 0.5, 0.4)
        #expect(isClose(ColorMath.compressChroma(color, gray: 0.5), color))
    }

    @Test func withLuminanceHitsTheTarget() {
        let result = ColorMath.withLuminance(SIMD3(0.8, 0.3, 0.2), target: 0.25)
        #expect(isClose(ColorMath.luminance(ColorMath.linear(result)), 0.25, within: 1e-6))
    }

    @Test func monotoneProjectionAveragesOutDips() {
        #expect(ColorMath.monotoneProjection([1, 3, 2, 4]) == [1, 2.5, 2.5, 4])
    }

    @Test func monotoneProjectionKeepsSortedValues() {
        #expect(ColorMath.monotoneProjection([0, 1, 1, 2]) == [0, 1, 1, 2])
    }
}
