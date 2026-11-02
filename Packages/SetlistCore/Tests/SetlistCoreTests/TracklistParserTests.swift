import XCTest
@testable import SetlistCore

final class TracklistParserTests: XCTestCase {
    let parser = TracklistParser()

    func testParsesSoundCloudStyleDescription() {
        let text = """
        Recorded live at Printworks, London.

        Tracklist:
        1. Kölsch - Grey
        2. Bicep - Glue
        3. ID - ID
        4. Ben Böhmer - Beyond Beliefs (Extended Mix) [Anjunadeep]
        5. Lane 8 feat. Fractures - Little Voices
        w/ Bonobo - Cirrus (Acapella)

        Follow me on Instagram
        """
        let setlist = parser.parse(text, title: "Printworks Set")

        XCTAssertEqual(setlist.entries.count, 6)
        XCTAssertEqual(setlist.entries[0].artist, "Kölsch")
        XCTAssertEqual(setlist.entries[0].title, "Grey")
        XCTAssertTrue(setlist.entries[2].isUnidentified)
        XCTAssertEqual(setlist.entries[3].label, "Anjunadeep")
        XCTAssertEqual(setlist.entries[3].title, "Beyond Beliefs (Extended Mix)")
        XCTAssertEqual(setlist.entries[4].artist, "Lane 8 feat. Fractures")
        XCTAssertTrue(setlist.entries[5].isMashupContinuation)
        XCTAssertEqual(setlist.entries[5].artist, "Bonobo")
        XCTAssertTrue(setlist.isLikelySetlist)
        XCTAssertEqual(setlist.searchableEntries.count, 5)
    }

    func testParsesTimestampsInSeveralShapes() {
        XCTAssertEqual(parser.parseLine("[00:00] Artist - Title", index: 1)?.timestamp, "00:00")
        XCTAssertEqual(parser.parseLine("1:23:45 Artist - Title", index: 1)?.timestamp, "1:23:45")
        XCTAssertEqual(parser.parseLine("12:30 - Artist - Title", index: 1)?.artist, "Artist")
        XCTAssertEqual(parser.parseLine("Artist - Title @ 45:10", index: 1)?.timestamp, "45:10")
        XCTAssertEqual(parser.parseLine("Artist - Title [1:02:00]", index: 1)?.timestamp, "1:02:00")
        XCTAssertEqual(parser.parseLine("[00:00] 03. Artist - Title", index: 1)?.artist, "Artist")
    }

    func testStripsIndexesWithoutEatingTimestamps() {
        XCTAssertEqual(parser.parseLine("01. Artist - Title", index: 1)?.artist, "Artist")
        XCTAssertEqual(parser.parseLine("(7) Artist - Title", index: 1)?.artist, "Artist")
        XCTAssertEqual(parser.parseLine("#12 Artist - Title", index: 1)?.artist, "Artist")
        XCTAssertEqual(parser.parseLine("01:23 Artist - Title", index: 1)?.artist, "Artist")
        XCTAssertEqual(parser.parseLine("2 Unlimited - No Limit", index: 1)?.artist, "2 Unlimited")
    }

    func testHandlesEnDashAndEmDash() {
        XCTAssertEqual(parser.parseLine("Artist – Title", index: 1)?.title, "Title")
        XCTAssertEqual(parser.parseLine("Artist — Title", index: 1)?.title, "Title")
        XCTAssertEqual(parser.parseLine("Jean-Michel Jarre - Oxygène, Pt. 4", index: 1)?.artist, "Jean-Michel Jarre")
    }

    func testUnidentifiedVariants() {
        for line in ["ID - ID", "id – id", "? - ?", "ID - ID (Kölsch Edit)", "Artist - ID", "ID - Known Title"] {
            let entry = parser.parseLine(line, index: 1)
            XCTAssertNotNil(entry, line)
            XCTAssertTrue(entry?.isUnidentified ?? false, line)
        }
    }

    func testRejectsProseAndCredits() {
        XCTAssertNil(parser.parseLine("Thanks for listening, see you next time!", index: 1))
        XCTAssertNil(parser.parseLine("Mixed by DJ Someone", index: 1))
        XCTAssertNil(parser.parseLine("https://soundcloud.com/someone/set", index: 1))
        XCTAssertNil(parser.parseLine("Tracklist:", index: 1))
    }

    func testByFormIsAccepted() {
        let entry = parser.parseLine("Glue by Bicep", index: 1)
        XCTAssertEqual(entry?.artist, "Bicep")
        XCTAssertEqual(entry?.title, "Glue")
    }

    func testConfidenceDropsForProse() {
        let prose = """
        This was a great night - thanks to everyone.
        We played until 6am - what a crowd.
        Next show is in Berlin.
        Tickets on sale now.
        """
        let setlist = parser.parse(prose)
        XCTAssertFalse(setlist.isLikelySetlist)
    }

    func testOCRStyleOutputWithBullets() {
        let text = """
        • Fred again.. - Marea (we've lost dancing)
        • Overmono - So U Kno
        • Joy Orbison - flight fm
        """
        let setlist = parser.parse(text)
        XCTAssertEqual(setlist.entries.map(\.artist), ["Fred again..", "Overmono", "Joy Orbison"])
    }
}
