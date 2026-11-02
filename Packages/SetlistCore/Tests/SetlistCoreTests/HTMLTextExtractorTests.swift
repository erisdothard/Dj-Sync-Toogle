import XCTest
@testable import SetlistCore

final class HTMLTextExtractorTests: XCTestCase {
    func testExtractsTitleDescriptionAndBody() {
        let html = """
        <html><head>
        <title>Boiler Room Set | Free Listening on SoundCloud</title>
        <meta property="og:description" content="Tracklist:\\n1. Bicep - Glue\\n2. K&ouml;lsch - Grey" />
        <style>.x{}</style><script>var a = "<b>";</script>
        </head><body>
        <div>Tracklist:</div>
        <ul><li>1. Bicep - Glue</li><li>2. K&#246;lsch &ndash; Grey</li></ul>
        <p>Thanks &amp; see you</p>
        </body></html>
        """
        let page = HTMLTextExtractor.extract(from: html)
        XCTAssertEqual(page.title, "Boiler Room Set | Free Listening on SoundCloud")
        XCTAssertEqual(page.description, "Tracklist:\n1. Bicep - Glue\n2. Kölsch - Grey")
        XCTAssertFalse(page.bodyText.contains("var a"))
        XCTAssertTrue(page.bodyText.contains("1. Bicep - Glue\n2. Kölsch – Grey"))
        XCTAssertTrue(page.bodyText.contains("Thanks & see you"))

        let setlist = SetlistDetector.best(from: page.candidateTexts, title: page.title)
        XCTAssertEqual(setlist.entries.count, 2)
    }

    func testMetaWithReversedAttributeOrder() {
        let html = #"<meta content="Hello &quot;there&quot;" name="description">"#
        XCTAssertEqual(HTMLTextExtractor.extract(from: html).description, "Hello \"there\"")
    }

    func testCleanTitle() {
        XCTAssertEqual(SetlistDetector.cleanTitle("Boiler Room Set | Free Listening on SoundCloud"), "Boiler Room Set")
        XCTAssertEqual(SetlistDetector.cleanTitle("Some Mix - YouTube"), "Some Mix")
        XCTAssertNil(SetlistDetector.cleanTitle("   "))
    }

    func testSoleURL() {
        XCTAssertNotNil(SetlistDetector.soleURL(in: " https://soundcloud.com/a/b \n"))
        XCTAssertNil(SetlistDetector.soleURL(in: "check https://soundcloud.com/a/b"))
    }
}
