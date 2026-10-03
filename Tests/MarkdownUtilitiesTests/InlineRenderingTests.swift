import XCTest
import MarkdownUtilities

final class InlineRenderingTests: XCTestCase {
  func testIdentifiersAreNotEmphasis() {
    let html = MarkdownRenderer.render("read_internet_archive_item(etymologicaldict0000unse_h1z8) and foo__bar__baz")
    XCTAssertTrue(html.contains("read_internet_archive_item(etymologicaldict0000unse_h1z8)"))
    XCTAssertTrue(html.contains("foo__bar__baz"))
    XCTAssertFalse(html.contains("<em>"))
    XCTAssertFalse(html.contains("<strong>"))
  }
  func testMarkdownStillRendersAndCodeIsLiteral() {
    let html = MarkdownRenderer.render("# Plan\n\n1. *Look* at **the title page** with `view_canvas` and `a*b_c__d`.\n2. _Check_ __the imprint__.")
    XCTAssertTrue(html.contains("<h1"))
    XCTAssertTrue(html.contains("<ol>"))
    XCTAssertTrue(html.contains("<em>Look</em>"))
    XCTAssertTrue(html.contains("<strong>the title page</strong>"))
    XCTAssertTrue(html.contains("<code>view_canvas</code>"))
    XCTAssertTrue(html.contains("<code>a*b_c__d</code>"))
    XCTAssertTrue(html.contains("<em>Check</em>"))
    XCTAssertTrue(html.contains("<strong>the imprint</strong>"))
  }
  func testMultilingualTextAndEscapesStayIntact() {
    let html = MarkdownRenderer.render(#"العربية ελληνικά 漢字 नाम \_literal\_ <script>"#)
    XCTAssertTrue(html.contains("العربية ελληνικά 漢字 नाम _literal_"))
    XCTAssertFalse(html.contains("<script>"))
    XCTAssertFalse(html.contains("<em>"))
  }
  func testLinksProtectDestinationsAndRejectScriptURLs() {
    let html = MarkdownRenderer.render("[Archive](https://archive.org/details/example_item) and [unsafe](javascript:alert(1))")
    XCTAssertTrue(html.contains("href=\"https://archive.org/details/example_item\""))
    XCTAssertFalse(html.contains("href=\"javascript:"))
  }

}
