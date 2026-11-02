import XCTest
@testable import SetlistCore

final class MatchScorerTests: XCTestCase {
    private func candidate(_ title: String, _ artists: [String], id: String = "x") -> TrackCandidate {
        TrackCandidate(id: id, service: .spotify, title: title, artists: artists)
    }

    func testExactMatchScoresHigh() {
        let entry = SetlistEntry(index: 1, artist: "Bicep", title: "Glue", rawLine: "Bicep - Glue")
        let match = MatchScorer.best(for: entry, among: [candidate("Glue", ["Bicep"])])
        XCTAssertGreaterThanOrEqual(match.score, 0.95)
        XCTAssertTrue(match.isConfident)
    }

    func testPrefersOriginalOverRemixWhenNoRemixRequested() {
        let entry = SetlistEntry(index: 1, artist: "Bicep", title: "Glue", rawLine: "")
        let original = candidate("Glue", ["Bicep"], id: "original")
        let remix = candidate("Glue - Kölsch Remix", ["Bicep", "Kölsch"], id: "remix")
        let match = MatchScorer.best(for: entry, among: [remix, original])
        XCTAssertEqual(match.candidate?.id, "original")
    }

    func testPrefersRequestedRemix() {
        let entry = SetlistEntry(index: 1, artist: "Bicep", title: "Glue (Kölsch Remix)", rawLine: "")
        let original = candidate("Glue", ["Bicep"], id: "original")
        let remix = candidate("Glue - Kölsch Remix", ["Bicep", "Kölsch"], id: "remix")
        let match = MatchScorer.best(for: entry, among: [original, remix])
        XCTAssertEqual(match.candidate?.id, "remix")
        XCTAssertTrue(match.isConfident)
    }

    func testExtendedMixCountsAsSameTrack() {
        let entry = SetlistEntry(index: 1, artist: "Ben Böhmer", title: "Beyond Beliefs", rawLine: "")
        let match = MatchScorer.best(for: entry, among: [candidate("Beyond Beliefs - Extended Mix", ["Ben Bohmer"])])
        XCTAssertTrue(match.isConfident)
    }

    func testWrongTrackIsNotConfident() {
        let entry = SetlistEntry(index: 1, artist: "Bicep", title: "Glue", rawLine: "")
        let match = MatchScorer.best(for: entry, among: [candidate("Apricots", ["Bicep"])])
        XCTAssertFalse(match.isConfident)
    }

    func testNoCandidatesYieldsNoMatch() {
        let entry = SetlistEntry(index: 1, artist: "Bicep", title: "Glue", rawLine: "")
        let match = MatchScorer.best(for: entry, among: [])
        XCTAssertNil(match.candidate)
        XCTAssertEqual(match.score, 0)
    }
}
