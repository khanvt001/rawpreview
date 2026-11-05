import Foundation
import Testing
@testable import rawpreview

@Suite struct PresetLoadingTests {
    private func file(_ name: String, _ contents: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func xmp(attributes: String = "", children: String = "") -> String {
        """
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" crs:Exposure2012="0.5" \(attributes)>\(children)</rdf:Description>
        </rdf:RDF></x:xmpmeta>
        """
    }

    @Test func loadsAnLrtemplate() throws {
        let url = try file("Warm.lrtemplate", """
            s = {
                title = "Warm Look",
                type = "Develop",
                value = {
                    settings = {
                        Exposure2012 = 0.5,
                        ToneCurvePV2012 = { 0, 0, 255, 255 },
                    },
                },
            }
            """)
        let preset = try DevelopPreset.load(from: url)
        #expect(preset.id == "Warm.lrtemplate")
        #expect(preset.title == "Warm Look")
        #expect(preset.settings["Exposure2012"] == .number(0.5))
        #expect(preset.settings["ToneCurvePV2012"] == .list([0, 0, 255, 255]))
    }

    @Test func usesTheDefaultTextOfALocalizedTitle() throws {
        let url = try file("a.lrtemplate", #"s = { title = "$$$/Presets/Warm=Warm Look", value = { settings = { Exposure2012 = 1 } } }"#)
        #expect(try DevelopPreset.load(from: url).title == "Warm Look")
    }

    @Test func rejectsAnLrtemplateThatIsNotADevelopPreset() throws {
        let url = try file("a.lrtemplate", #"s = { type = "Export", value = { settings = { } } }"#)
        #expect(throws: DevelopPreset.LoadError.self) { try DevelopPreset.load(from: url) }
    }

    @Test func loadsAnXMP() throws {
        let url = try file("Cool.xmp", xmp(children: """
            <crs:Name><rdf:Alt><rdf:li xml:lang="fr">Froid</rdf:li><rdf:li xml:lang="x-default">Cool</rdf:li></rdf:Alt></crs:Name>
            <crs:ToneCurvePV2012><rdf:Seq><rdf:li>0, 0</rdf:li><rdf:li>255, 255</rdf:li></rdf:Seq></crs:ToneCurvePV2012>
            """))
        let preset = try DevelopPreset.load(from: url)
        #expect(preset.title == "Cool")
        #expect(preset.settings["Exposure2012"] == .number(0.5))
        #expect(preset.settings["ToneCurvePV2012"] == .list([0, 0, 255, 255]))
    }

    @Test func fallsBackToTheFileNameForATitle() throws {
        #expect(try DevelopPreset.load(from: file("My Look.xmp", xmp())).title == "My Look")
    }

    @Test func rejectsAnXMPThatIsNotADevelopPreset() throws {
        let url = try file("a.xmp", xmp(attributes: #"crs:PresetType="Look""#))
        #expect(throws: DevelopPreset.LoadError.self) { try DevelopPreset.load(from: url) }
    }

    @Test func rejectsFilesItCannotRead() throws {
        #expect(throws: DevelopPreset.LoadError.self) { try DevelopPreset.load(from: file("a.xmp", "not xml")) }
        #expect(throws: DevelopPreset.LoadError.self) { try DevelopPreset.load(from: file("a.lrtemplate", "{")) }
        #expect(throws: DevelopPreset.LoadError.self) { try DevelopPreset.load(from: file("a.txt", "")) }
    }

    @Test func fillsColorGradingFromLegacySplitToning() {
        let result = PresetNormalization.normalize(["SplitToningShadowHue": .number(30)])
        #expect(result["ColorGradeShadowHue"] == .number(30))
    }

    @Test func prefersColorGradingOverLegacySplitToning() {
        let result = PresetNormalization.normalize([
            "SplitToningShadowHue": .number(30),
            "ColorGradeShadowHue": .number(200),
        ])
        #expect(result["ColorGradeShadowHue"] == .number(200))
    }

    @Test(arguments: [
        ["Treatment": PresetValue.string("Black & White")],
        ["CameraProfile": .string("Camera Monochrome")],
        ["Look": .object(["Name": .string("Adobe Monochrome")])],
        ["Look": .object(["Name": .array([.string("Adobe Monochrome")])])],
    ])
    func convertsMonochromePresetsToGrayscale(_ settings: [String: PresetValue]) {
        #expect(PresetNormalization.normalize(settings)["ConvertToGrayscale"] == .bool(true))
    }

    @Test func leavesColorPresetsInColor() {
        let result = PresetNormalization.normalize(["Treatment": .string("Color")])
        #expect(result["ConvertToGrayscale"] == nil)
    }
}
