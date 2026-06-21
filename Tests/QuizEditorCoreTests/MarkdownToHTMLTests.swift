import XCTest
@testable import QuizEditorCore

final class MarkdownToHTMLTests: XCTestCase {
    private let renderer = MarkdownToHTML()

    func testHeadings() {
        XCTAssertEqual(renderer.bodyHTML(from: "# Title"), "<h1>Title</h1>")
        XCTAssertEqual(renderer.bodyHTML(from: "### Sub"), "<h3>Sub</h3>")
        XCTAssertEqual(renderer.bodyHTML(from: "###### Six"), "<h6>Six</h6>")
        // 7+ hashes is not a heading (CommonMark) — render as a paragraph.
        XCTAssertTrue(renderer.bodyHTML(from: "####### Deep").contains("<p>"))
    }

    func testInlineBoldItalicCode() {
        XCTAssertEqual(renderer.bodyHTML(from: "This is **bold**."), "<p>This is <strong>bold</strong>.</p>")
        XCTAssertEqual(renderer.bodyHTML(from: "An *italic* word."), "<p>An <em>italic</em> word.</p>")
        XCTAssertEqual(renderer.bodyHTML(from: "Use `code` here."), "<p>Use <code>code</code> here.</p>")
    }

    func testLinks() {
        XCTAssertEqual(
            renderer.bodyHTML(from: "See [Canvas](https://canvas.example.com)."),
            "<p>See <a href=\"https://canvas.example.com\">Canvas</a>.</p>"
        )
    }

    func testUnorderedList() {
        let html = renderer.bodyHTML(from: "- First\n- Second")
        XCTAssertEqual(html, "<ul>\n<li>First</li>\n<li>Second</li>\n</ul>")
    }

    func testOrderedList() {
        let html = renderer.bodyHTML(from: "1. One\n2. Two")
        XCTAssertEqual(html, "<ol>\n<li>One</li>\n<li>Two</li>\n</ol>")
    }

    func testListThenParagraphClosesList() {
        let html = renderer.bodyHTML(from: "- item\n\nAfter.")
        XCTAssertEqual(html, "<ul>\n<li>item</li>\n</ul>\n<p>After.</p>")
    }

    func testFencedCodeBlockIsNotFormattedInside() {
        let md = "```\nlet x = **not bold**\n```"
        let html = renderer.bodyHTML(from: md)
        XCTAssertTrue(html.contains("<pre><code>"))
        XCTAssertTrue(html.contains("let x = **not bold**"))
        XCTAssertFalse(html.contains("<strong>"))
    }

    func testHTMLIsEscaped() {
        let html = renderer.bodyHTML(from: "A <script>alert(1)</script> tag")
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    func testBlockquoteAndHorizontalRule() {
        XCTAssertEqual(renderer.bodyHTML(from: "> quoted"), "<blockquote>quoted</blockquote>")
        XCTAssertEqual(renderer.bodyHTML(from: "---"), "<hr>")
    }

    func testFullDocumentWraps() {
        let doc = renderer.document(from: "# Hi")
        XCTAssertTrue(doc.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(doc.contains("<h1>Hi</h1>"))
        XCTAssertTrue(doc.contains("color-scheme"))
    }

    func testRealisticAIResponse() {
        let md = """
        ## Review Summary

        The quiz is **mostly solid**, but a few items need work:

        - Question 2 has *no correct answer* marked.
        - Question 4 uses `all of the above`.

        Overall: good alignment.
        """
        let html = renderer.bodyHTML(from: md)
        XCTAssertTrue(html.contains("<h2>Review Summary</h2>"))
        XCTAssertTrue(html.contains("<strong>mostly solid</strong>"))
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertTrue(html.contains("<em>no correct answer</em>"))
        XCTAssertTrue(html.contains("<code>all of the above</code>"))
    }
}
