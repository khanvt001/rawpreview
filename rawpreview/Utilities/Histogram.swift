//
//  Histogram.swift
//  rawpreview
//

import CoreGraphics

/// Red, green and blue histograms of an image as displayed, 256 bins each,
/// plus a luminance one for `AutoTone`.
nonisolated struct Histogram: Sendable {
    /// Bin heights scaled so the tallest inner bin is 1. The end bins (pure
    /// black / clipped white) are left out of that maximum so a spike there
    /// doesn't flatten everything else; they may exceed 1.
    let red: [Double]
    let green: [Double]
    let blue: [Double]
    /// Share of pixels at each luma level (Rec. 601 on gamma-encoded values,
    /// like `PresetLook`); sums to 1.
    let luminance: [Double]

    /// Counts a copy shrunk to at most `sampleSize` px on its long side:
    /// plenty for 256 bins, and a few ms even for a 20 MP photo.
    init?(_ image: CGImage, sampleSize: Int = 512) {
        let scale = min(1, Double(sampleSize) / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }

        var red = [Int](repeating: 0, count: 256)
        var green = red, blue = red, luma = red
        let rowBytes = context.bytesPerRow
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            let row = pixels + y * rowBytes
            for x in 0..<width {
                let pixel = row + x * 4
                red[Int(pixel[0])] += 1
                green[Int(pixel[1])] += 1
                blue[Int(pixel[2])] += 1
                // 0.299 / 0.587 / 0.114 in 256ths.
                luma[(77 * Int(pixel[0]) + 150 * Int(pixel[1]) + 29 * Int(pixel[2])) >> 8] += 1
            }
        }

        let peak = Double(max([red, green, blue].flatMap { $0[1...254] }.max() ?? 1, 1))
        self.red = red.map { Double($0) / peak }
        self.green = green.map { Double($0) / peak }
        self.blue = blue.map { Double($0) / peak }
        luminance = luma.map { Double($0) / Double(width * height) }
    }
}
