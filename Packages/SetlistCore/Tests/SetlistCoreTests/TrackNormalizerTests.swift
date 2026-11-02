import XCTest
@testable import SetlistCore

final class TrackNormalizerTests: XCTestCase {
    func testStripsVersionNoise() {
        let query = TrackNormalizer.query(artist: "Ben Böhmer", title: "Beyond Beliefs (Extended Mix)")
        XCTAssertEqual(query.title, "Beyond Beliefs")
        XCTAssertNil(query.remixTag)
        XCTAssertEqual(query.artists, ["Ben Böhmer"])
    }

    func testKeepsRemixTag() {
        let query = TrackNormalizer.query(artist: "Bicep", title: "Glue (Kölsch Remix) [Ninja Tune]")
        XCTAssertEqual(query.title, "Glue")
        XCTAssertEqual(query.remixTag, "Kölsch Remix")
        XCTAssertEqual(query.searchTerm, "Bicep Glue Kölsch Remix")
    }

    func testSpotifyStyleDashSuffix() {
        let remix = TrackNormalizer.query(artist: "Bicep", title: "Glue - Kölsch Remix")
        XCTAssertEqual(remix.title, "Glue")
        XCTAssertEqual(remix.remixTag, "Kölsch Remix")

        let extended = TrackNormalizer.query(artist: "Bicep", title: "Glue - Extended Mix")
        XCTAssertEqual(extended.title, "Glue")
        XCTAssertNil(extended.remixTag)

        let plain = TrackNormalizer.query(artist: "Someone", title: "Chapter 1 - The Beginning")
        XCTAssertEqual(plain.title, "Chapter 1 - The Beginning")
    }

    func testFeaturedArtists() {
        let inline = TrackNormalizer.query(artist: "Lane 8 feat. Fractures", title: "Little Voices")
        XCTAssertEqual(inline.artists, ["Lane 8"])
        XCTAssertEqual(inline.featuredArtists, ["Fractures"])

        let grouped = TrackNormalizer.query(artist: "Rüfüs Du Sol", title: "Underwater (feat. Someone & Other)")
        XCTAssertEqual(grouped.title, "Underwater")
        XCTAssertEqual(grouped.featuredArtists, ["Someone", "Other"])

        let withIsNotFeat = TrackNormalizer.query(artist: "Ultravox", title: "Dancing With Tears In My Eyes")
        XCTAssertEqual(withIsNotFeat.title, "Dancing With Tears In My Eyes")
    }

    func testSplitsArtistCollaborations() {
        XCTAssertEqual(TrackNormalizer.splitArtists("Above & Beyond"), ["Above", "Beyond"])
        XCTAssertEqual(TrackNormalizer.splitArtists("Camelphat x Elderbrook"), ["Camelphat", "Elderbrook"])
        XCTAssertEqual(TrackNormalizer.splitArtists("A, B and C"), ["A", "B", "C"])
        XCTAssertEqual(TrackNormalizer.splitArtists("Andhim"), ["Andhim"])
        XCTAssertEqual(TrackNormalizer.splitArtists("Band of Horses"), ["Band of Horses"])
    }

    func testNormalizedTokensFoldDiacriticsAndPunctuation() {
        XCTAssertEqual(TrackNormalizer.normalizedTokens("Kölsch – Grey!"), ["kolsch", "grey"])
        XCTAssertEqual(TrackNormalizer.normalizedTokens("Above & Beyond"), ["above", "and", "beyond"])
        XCTAssertEqual(TrackNormalizer.normalizedTokens("Fred again.."), ["fred", "again"])
    }
}
