import XCTest
@testable import SetlistCore

final class EmbeddedJSONExtractorTests: XCTestCase {
    func testYouTubeShortDescriptionIsPreferredOverTruncatedMeta() {
        let html = #"""
        <html><head><title>Summer Mix 2024 - YouTube</title>
        <meta name="description" content="Tracklist: 0:00 Bicep - Glue 3:45 Kölsch - Grey ...">
        </head><body><script>var ytInitialPlayerResponse = {"videoDetails":{"videoId":"abc","title":"Summer Mix 2024","shortDescription":"Summer vibes & good times.\n\nTracklist:\n0:00 Bicep - Glue\n3:45 Kölsch - Grey\n7:10 Ben Böhmer - Beyond Beliefs\n11:00 ID - ID\n\nFollow me: https://instagram.com/x","isLiveContent":false}};</script></body></html>
        """#

        let page = HTMLTextExtractor.extract(from: html)
        XCTAssertEqual(page.embeddedDescriptions.count, 1)
        XCTAssertTrue(page.embeddedDescriptions[0].hasPrefix("Summer vibes & good times."))

        let setlist = SetlistDetector.best(from: page.candidateTexts, title: SetlistDetector.cleanTitle(page.title))
        XCTAssertEqual(setlist.title, "Summer Mix 2024")
        XCTAssertEqual(setlist.entries.count, 4)
        XCTAssertEqual(setlist.entries[1].artist, "Kölsch")
        XCTAssertEqual(setlist.entries[1].timestamp, "3:45")
        XCTAssertEqual(setlist.entries[2].title, "Beyond Beliefs")
        XCTAssertTrue(setlist.entries[3].isUnidentified)
        XCTAssertTrue(setlist.isLikelySetlist)
    }

    func testHandlesEscapedQuotesAndBackslashes() {
        let html = #"{"description":"He said \"hi\" \\ bye\nSecond line"}"#
        XCTAssertEqual(EmbeddedJSONExtractor.strings(forKey: "description", in: html), ["He said \"hi\" \\ bye\nSecond line"])
    }

    func testIgnoresNonJSONOccurrences() {
        let html = "<p>\"description\":\"not json because of a raw\nnewline</p>"
        XCTAssertEqual(EmbeddedJSONExtractor.strings(forKey: "description", in: html), [])
    }

    func testDeduplicatesAndSortsLongestFirst() {
        let html = #"{"description":"short"} {"description":"a much longer description"} {"description":"short"}"#
        XCTAssertEqual(EmbeddedJSONExtractor.strings(forKey: "description", in: html), ["a much longer description", "short"])
    }
}
