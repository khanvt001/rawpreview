import Foundation
import Testing
@testable import rawpreview

@Suite struct XMPServiceTests {
    private func rating(_ body: String) -> Rating? {
        let xml = """
            <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="\(XMPService.rdfNamespace)">\(body)</rdf:RDF></x:xmpmeta>
            """
        return XMPService.rating(in: Data(xml.utf8))
    }

    private func sidecar(_ contents: String? = nil) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "DSC_0001.xmp")
        try contents?.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func readsARatingAttribute() {
        #expect(rating(#"<rdf:Description xmlns:xmp="\#(XMPService.xmpNamespace)" xmp:Rating="4"/>"#) == Rating(4))
    }

    @Test func readsARatingElement() {
        #expect(rating(#"<rdf:Description xmlns:xmp="\#(XMPService.xmpNamespace)"><xmp:Rating> 2 </xmp:Rating></rdf:Description>"#) == Rating(2))
    }

    @Test func readsARatingFromALaterDescription() {
        let body = #"<rdf:Description/><rdf:Description xmlns:xmp="\#(XMPService.xmpNamespace)" xmp:Rating="3"/>"#
        #expect(rating(body) == Rating(3))
    }

    @Test(arguments: ["-1", "6"])
    func treatsOutOfRangeRatingsAsUnrated(_ value: String) {
        #expect(rating(#"<rdf:Description xmlns:xmp="\#(XMPService.xmpNamespace)" xmp:Rating="\#(value)"/>"#) == Rating.none)
    }

    @Test func findsNoRatingInASidecarWithoutOne() {
        #expect(rating("<rdf:Description/>") == nil)
        #expect(XMPService.rating(in: Data("not xml".utf8)) == nil)
    }

    @Test func createsASidecarThatReadsBack() async throws {
        let url = try sidecar()
        try await XMPService().setRating(Rating(5), sidecar: url)
        #expect(XMPService.rating(in: try Data(contentsOf: url)) == Rating(5))
    }

    @Test func overwritesAnExistingRating() async throws {
        let url = try sidecar()
        let service = XMPService()
        try await service.setRating(Rating(5), sidecar: url)
        try await service.setRating(Rating(1), sidecar: url)
        #expect(XMPService.rating(in: try Data(contentsOf: url)) == Rating(1))
    }

    @Test func keepsWhatOtherAppsWrote() async throws {
        let url = try sidecar("""
            <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="\(XMPService.rdfNamespace)">
            <rdf:Description xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" crs:Exposure2012="+0.50">
            <crs:ToneCurvePV2012><rdf:Seq><rdf:li>0, 0</rdf:li></rdf:Seq></crs:ToneCurvePV2012>
            </rdf:Description></rdf:RDF></x:xmpmeta>
            """)
        try await XMPService().setRating(Rating(3), sidecar: url)
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(saved.contains(#"crs:Exposure2012="+0.50""#))
        #expect(saved.contains("<rdf:li>0, 0</rdf:li>"))
        #expect(XMPService.rating(in: Data(saved.utf8)) == Rating(3))
    }

    @Test(arguments: ["not xml at all", "<root/>"])
    func leavesAnUnreadableSidecarUntouched(_ contents: String) async throws {
        let url = try sidecar(contents)
        await #expect(throws: XMPService.XMPError.self) {
            try await XMPService().setRating(Rating(3), sidecar: url)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == contents)
    }
}
