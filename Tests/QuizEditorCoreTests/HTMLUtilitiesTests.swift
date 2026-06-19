import XCTest
@testable import QuizEditorCore

final class HTMLUtilitiesTests: XCTestCase {
    private let html = HTMLUtilities()

    func testPlainTextStripsTagsAndDecodesEntities() {
        let input = "<p>Which <strong>organ</strong> pumps blood &amp; oxygen?</p>"
        XCTAssertEqual(html.plainText(fromHTML: input), "Which organ pumps blood & oxygen?")
    }

    func testPlainTextInsertsLineBreaksForBlocks() {
        let input = "<p>First line</p><p>Second line</p>"
        XCTAssertEqual(html.plainText(fromHTML: input), "First line\nSecond line")
    }

    func testIsPlainTextDetection() {
        XCTAssertTrue(html.isPlainText("Just words, 1 < 2 spoken aloud"))
        XCTAssertFalse(html.isPlainText("Has <em>markup</em>"))
    }

    func testImagesMissingAltCounting() {
        let withAlt = "<img src=\"a.png\" alt=\"A heart\">"
        let decorative = "<img src=\"line.png\" alt=\"\">"
        let missing = "<img src=\"b.png\">"
        let emptyButPresentSingleQuote = "<img src='c.png' alt='labelled'>"

        XCTAssertEqual(html.imagesMissingAlt(in: withAlt), 0)
        XCTAssertEqual(html.imagesMissingAlt(in: decorative), 0)
        XCTAssertEqual(html.imagesMissingAlt(in: missing), 1)
        XCTAssertEqual(html.imagesMissingAlt(in: emptyButPresentSingleQuote), 0)
        XCTAssertEqual(html.imagesMissingAlt(in: missing + withAlt + missing), 2)
    }

    func testXHTMLFragmentClosesVoidElementsAndStaysWellFormed() {
        let fragment = html.xhtmlFragment(from: "Line<br>break and an <img src=\"a.png\" alt=\"x\"> image")
        XCTAssertNotNil(fragment)
        // Void elements must be closed to be valid XML.
        XCTAssertTrue(fragment!.contains("</br>"))
        XCTAssertTrue(fragment!.contains("</img>"))
        // The output must parse as XML.
        let wrapped = "<root>\(fragment!)</root>"
        XCTAssertNoThrow(try XMLDocument(xmlString: wrapped, options: []))
    }

    func testXHTMLFragmentPreservesTables() {
        let table = "<table><tr><td>A</td><td>B</td></tr></table>"
        let fragment = html.xhtmlFragment(from: table)
        XCTAssertNotNil(fragment)
        XCTAssertTrue(fragment!.contains("<table"))
        XCTAssertTrue(fragment!.contains("<td>A"))
        XCTAssertTrue(fragment!.contains("B"))
        XCTAssertNoThrow(try XMLDocument(xmlString: "<root>\(fragment!)</root>", options: []))
    }

    func testValidatorFindsMissingAltAcrossFields() {
        let quiz = Quiz(
            title: "T",
            questions: [
                QuizQuestion(type: .multipleChoice, prompt: "<p>Fine prompt</p>", answers: [QuizAnswer(text: "ok", isCorrect: true)]),
                QuizQuestion(type: .multipleChoice, prompt: "<img src=\"x.png\">", answers: [QuizAnswer(text: "ok", isCorrect: true)])
            ]
        )

        let issues = QuizAccessibilityValidator().imagesMissingAltText(in: quiz)
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].contains("Question 2"))
    }
}
