import XCTest
@testable import QuizEditorCore

final class RichTextRoundTripTests: XCTestCase {
    private func writePackage(_ package: QTIPackage) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        for file in package.files {
            let url = directory.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return directory
    }

    private let richQuiz = Quiz(
        title: "Formatted",
        questions: [
            QuizQuestion(
                type: .multipleChoice,
                prompt: "<p>Which organ pumps <strong>blood</strong>?</p>",
                answers: [
                    QuizAnswer(text: "The <em>heart</em>", isCorrect: true),
                    QuizAnswer(text: "The liver", isCorrect: false)
                ],
                feedback: "<p>The <strong>heart</strong> circulates blood.</p>"
            )
        ]
    )

    func testClassicExportImportPreservesFormatting() throws {
        let package = try CanvasQTIExporter(engine: .classicQuizzes).makePackage(for: richQuiz)
        let directory = try writePackage(package)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imported = try QTIImporter(preserveFormatting: true).importQuiz(fromDirectory: directory)

        XCTAssertEqual(imported.questions[0].prompt, "<p>Which organ pumps <strong>blood</strong>?</p>")
        XCTAssertEqual(imported.questions[0].answers[0].text, "The <em>heart</em>")
        XCTAssertEqual(imported.questions[0].feedback, "<p>The <strong>heart</strong> circulates blood.</p>")
    }

    func testPlainImportStripsFormatting() throws {
        let package = try CanvasQTIExporter(engine: .classicQuizzes).makePackage(for: richQuiz)
        let directory = try writePackage(package)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imported = try QTIImporter(preserveFormatting: false).importQuiz(fromDirectory: directory)

        XCTAssertEqual(imported.questions[0].prompt, "Which organ pumps blood?")
        XCTAssertEqual(imported.questions[0].answers[0].text, "The heart")
        XCTAssertEqual(imported.questions[0].feedback, "The heart circulates blood.")
    }

    func testNewQuizzesExportEmbedsWellFormedXHTML() throws {
        let package = try CanvasQTIExporter(engine: .newQuizzes).makePackage(for: richQuiz)
        let item = try XCTUnwrap(package.file(named: "items/question-1.xml"))

        // The emphasis markup survives as real XHTML elements (not escaped text).
        XCTAssertTrue(item.contents.contains("<strong>blood</strong>"))
        XCTAssertTrue(item.contents.contains("<em>heart</em>"))
        // The whole item must remain valid XML.
        XCTAssertNoThrow(try XMLDocument(xmlString: item.contents, options: []))
    }

    func testClassicExportEscapesHTMLForTransport() throws {
        let package = try CanvasQTIExporter(engine: .classicQuizzes).makePackage(for: richQuiz)
        let item = try XCTUnwrap(package.file(named: "items/question-1.xml"))

        // Classic carries HTML entity-escaped inside text/html mattext.
        XCTAssertTrue(item.contents.contains("texttype=\"text/html\""))
        XCTAssertTrue(item.contents.contains("&lt;strong&gt;blood&lt;/strong&gt;"))
        XCTAssertNoThrow(try XMLDocument(xmlString: item.contents, options: []))
    }
}
