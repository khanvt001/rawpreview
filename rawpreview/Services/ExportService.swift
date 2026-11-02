import CoreGraphics
import Foundation

/// Shared edited-output path for Copy/Export, Share and AirDrop. Call while
/// holding RenderCoordinator's export permit; never switches source on error.
nonisolated enum ExportService {
    static func write(source: URL, to destination: URL, state: DevelopState, settings: ExportSettings, rating: Rating? = nil) throws {
        DevelopService.observeMemoryPressure()
        try Task.checkCancellation()
        let decoded = try DevelopDecoder.decode(source, state: state, longEdge: settings.longEdge)
        let image = try DevelopRenderer.render(decoded, state: state, outputSpace: CGColorSpace(name: CGColorSpace.sRGB)!, sixteenBit: settings.writes16Bit)
        try Task.checkCancellation()
        try ImageWriter.write(image, to: destination, type: settings.format.type, original: source,
                              quality: settings.quality, keepsLocation: settings.keepsLocation, rating: rating)
        try Task.checkCancellation()
    }
}
