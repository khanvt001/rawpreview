import Testing
@testable import rawpreview

@Suite struct MediaKindTests {
    @Test(arguments: [
        ("NEF", MediaKind.raw), ("cr3", .raw), ("dng", .raw), ("Jpg", .jpeg), ("HIF", .heif), ("MOV", .video), ("xmp", .other), ("", .other),
    ])
    func classifiesExtensionsInAnyCase(_ ext: String, _ kind: MediaKind) {
        #expect(MediaKind(fileExtension: ext) == kind)
    }

    @Test func listsNineteenRawFormats() {
        #expect(MediaKind.rawExtensions.count == 19)
    }

    @Test func treatsVideoAsNotAnImage() {
        #expect(MediaKind.raw.isImage)
        #expect(!MediaKind.video.isImage)
    }

    @Test func clampsRatingsToTheStarRange() {
        #expect(Rating(9).rawValue == Rating.maxStars)
        #expect(Rating(-1) == Rating.none)
        #expect(Rating(rawValue: 6) == nil)
    }
}
