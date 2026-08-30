import XCTest
@testable import QuizEditorCore

/// Fill-in-blank and short-answer items were exported with a choice-style key:
/// the correct response was the identifier "answer_1" rather than the text the
/// student is expected to type, so a correct answer graded as wrong in both
/// targets.
final class TextEntryAnswerKeyTests: XCTestCase {
    private func quiz(_ type: QuizQuestionType) -> Quiz {
        Quiz(
            title: "Text entry",
            questions: [
                QuizQuestion(
                    type: type,
                    prompt: "<p>Gametes come from ____.</p>",
                    // The second spelling is left unchecked on purpose: for these
                    // types every row is an accepted answer.
                    answers: [
                        QuizAnswer(text: "meiosis", isCorrect: true),
                        QuizAnswer(text: "meiotic division", isCorrect: false)
                    ],
                    points: 1
                )
            ]
        )
    }

    private func itemXML(_ type: QuizQuestionType, _ target: QTIExportTarget) throws -> String {
        let package = try QTIExporter(target: target).makePackage(for: quiz(type))
        let item = package.files.first { $0.contents.contains("Gametes come from") }
        return try XCTUnwrap(item?.contents)
    }

    func testClassicGradesAgainstTheAnswerText() throws {
        for type in [QuizQuestionType.fillInBlank, .shortAnswer] {
            let xml = try itemXML(type, .qti12)
            XCTAssertTrue(
                xml.contains("<varequal respident=\"response1\">meiosis</varequal>"),
                "\(type) should grade against the typed answer, got:\n\(xml)"
            )
            XCTAssertFalse(xml.contains("answer_1"), "\(type) must not key on a choice identifier")
        }
    }

    func testClassicAcceptsEveryAnswerRow() throws {
        let xml = try itemXML(.shortAnswer, .qti12)
        XCTAssertTrue(xml.contains(">meiosis<"))
        XCTAssertTrue(xml.contains(">meiotic division<"), "an unchecked row is still an accepted answer")
    }

    func testNewQuizzesDeclaresAStringResponse() throws {
        for type in [QuizQuestionType.fillInBlank, .shortAnswer] {
            let xml = try itemXML(type, .qti21)
            XCTAssertTrue(xml.contains("baseType=\"string\""), "\(type) needs a string response, got:\n\(xml)")
            XCTAssertTrue(xml.contains("<value>meiosis</value>"))
            XCTAssertFalse(xml.contains("answer_1"))
        }
    }

    func testNewQuizzesMapsEveryAcceptedSpelling() throws {
        let xml = try itemXML(.fillInBlank, .qti21)
        XCTAssertTrue(xml.contains("mapKey=\"meiosis\""))
        XCTAssertTrue(xml.contains("mapKey=\"meiotic division\""))
    }

    /// Author metadata must not ride along: the accepted answers are the only
    /// thing added here.
    func testMisconceptionTagsStillDoNotExport() throws {
        var q = quiz(.shortAnswer)
        q.questions[0].answers[1].misconceptionTag = "Confuses meiosis with mitosis"
        let package = try QTIExporter(target: .qti12).makePackage(for: q)
        for file in package.files {
            XCTAssertFalse(file.contents.contains("Confuses meiosis"), "in \(file.path)")
        }
    }
}
