import XCTest
@testable import QuizEditorCore

final class QTIImporterTests: XCTestCase {
    func testImportsClassicQTIPackageWrittenByExporter() throws {
        let original = Quiz(
            title: "Imported Classic",
            questions: [
                QuizQuestion(
                    type: .multipleChoice,
                    prompt: "Which answer is correct?",
                    answers: [
                        QuizAnswer(text: "Right", isCorrect: true),
                        QuizAnswer(text: "Wrong", isCorrect: false)
                    ],
                    feedback: "Right is correct."
                )
            ]
        )
        let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        try QTIPackageWriter(engine: .classicQuizzes).writeZip(for: original, to: archiveURL)

        let imported = try QTIImporter().importQuiz(fromZipAt: archiveURL)

        XCTAssertEqual(imported.title, "Imported Classic")
        XCTAssertEqual(imported.questions.count, 1)
        XCTAssertEqual(imported.questions[0].type, .multipleChoice)
        XCTAssertEqual(imported.questions[0].prompt, "Which answer is correct?")
        XCTAssertEqual(imported.questions[0].answers.map(\.text), ["Right", "Wrong"])
        XCTAssertEqual(imported.questions[0].answers.map(\.isCorrect), [true, false])
        XCTAssertEqual(imported.questions[0].feedback, "Right is correct.")
    }

    func testImportsClassicPackageWithInlineItemsInSingleAssessment() throws {
        // Canvas classic exports embed every <item> inline in one assessment.xml
        // rather than emitting one file per question.
        let manifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <manifest identifier="m" xmlns="http://www.imsglobal.org/xsd/imscp_v1p1">
          <resources>
            <resource identifier="q" type="imsqti_xmlv1p2" href="assessment.xml">
              <file href="assessment.xml"/>
            </resource>
          </resources>
        </manifest>
        """
        let assessment = """
        <?xml version="1.0" encoding="UTF-8"?>
        <questestinterop xmlns="http://www.imsglobal.org/xsd/ims_qtiasiv1p2">
          <assessment ident="a" title="Inline Quiz">
            <section ident="s">
              <item ident="q1" title="One">
                <itemmetadata><qtimetadata><qtimetadatafield><fieldlabel>question_type</fieldlabel><fieldentry>multiple_choice_question</fieldentry></qtimetadatafield></qtimetadata></itemmetadata>
                <presentation><material><mattext texttype="text/plain">First question?</mattext></material>
                  <response_lid ident="response" rcardinality="Single"><render_choice>
                    <response_label ident="a"><material><mattext>Right</mattext></material></response_label>
                    <response_label ident="b"><material><mattext>Wrong</mattext></material></response_label>
                  </render_choice></response_lid>
                </presentation>
                <resprocessing><outcomes><decvar maxvalue="100" minvalue="0" varname="SCORE" vartype="Decimal"/></outcomes>
                  <respcondition continue="No"><conditionvar><varequal respident="response">a</varequal></conditionvar><setvar action="Set" varname="SCORE">100</setvar></respcondition>
                </resprocessing>
              </item>
              <item ident="q2" title="Two">
                <itemmetadata><qtimetadata><qtimetadatafield><fieldlabel>question_type</fieldlabel><fieldentry>multiple_choice_question</fieldentry></qtimetadatafield></qtimetadata></itemmetadata>
                <presentation><material><mattext texttype="text/plain">Second question?</mattext></material>
                  <response_lid ident="response" rcardinality="Single"><render_choice>
                    <response_label ident="a"><material><mattext>Nope</mattext></material></response_label>
                    <response_label ident="b"><material><mattext>Yep</mattext></material></response_label>
                  </render_choice></response_lid>
                </presentation>
                <resprocessing><outcomes><decvar maxvalue="100" minvalue="0" varname="SCORE" vartype="Decimal"/></outcomes>
                  <respcondition continue="No"><conditionvar><varequal respident="response">b</varequal></conditionvar><setvar action="Set" varname="SCORE">100</setvar></respcondition>
                </resprocessing>
              </item>
            </section>
          </assessment>
        </questestinterop>
        """

        let workingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try manifest.write(to: workingDirectory.appendingPathComponent("imsmanifest.xml"), atomically: true, encoding: .utf8)
        try assessment.write(to: workingDirectory.appendingPathComponent("assessment.xml"), atomically: true, encoding: .utf8)

        let imported = try QTIImporter().importQuiz(fromDirectory: workingDirectory)

        XCTAssertEqual(imported.title, "Inline Quiz")
        XCTAssertEqual(imported.questions.count, 2)
        XCTAssertEqual(imported.questions[0].prompt, "First question?")
        XCTAssertEqual(imported.questions[0].answers.map(\.text), ["Right", "Wrong"])
        XCTAssertEqual(imported.questions[0].answers.map(\.isCorrect), [true, false])
        XCTAssertEqual(imported.questions[1].prompt, "Second question?")
        XCTAssertEqual(imported.questions[1].answers.map(\.isCorrect), [false, true])
    }

    func testImportsNewQuizzesQTIPackageWrittenByExporter() throws {
        let original = Quiz(
            title: "Imported New Quiz",
            questions: [
                QuizQuestion(
                    type: .multipleAnswer,
                    prompt: "Select correct choices.",
                    answers: [
                        QuizAnswer(text: "A", isCorrect: true),
                        QuizAnswer(text: "B", isCorrect: true),
                        QuizAnswer(text: "C", isCorrect: false)
                    ],
                    feedback: "A and B are correct."
                )
            ]
        )
        let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        try QTIPackageWriter(engine: .newQuizzes).writeZip(for: original, to: archiveURL)

        let imported = try QTIImporter().importQuiz(fromZipAt: archiveURL)

        XCTAssertEqual(imported.title, "Imported New Quiz")
        XCTAssertEqual(imported.questions[0].type, .multipleAnswer)
        XCTAssertEqual(imported.questions[0].prompt, "Select correct choices.")
        XCTAssertEqual(imported.questions[0].answers.map(\.text), ["A", "B", "C"])
        XCTAssertEqual(imported.questions[0].answers.map(\.isCorrect), [true, true, false])
        XCTAssertEqual(imported.questions[0].feedback, "A and B are correct.")
    }
}
