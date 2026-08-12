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

    // Canvas escapes apostrophes and smart quotes as numeric character references
    // rather than named entities, so these have to decode too.
    func testDecodesNumericCharacterReferences() {
        XCTAssertEqual(xmlUnescape("the cell&#x27;s nucleus"), "the cell's nucleus")
        XCTAssertEqual(xmlUnescape("It&#8217;s here"), "It\u{2019}s here")
        XCTAssertEqual(xmlUnescape("2 &#60; 3"), "2 < 3")
        XCTAssertEqual(xmlUnescape("caf&#233;"), "caf\u{e9}")
        XCTAssertEqual(xmlUnescape("&#X27;"), "'", "hex marker is case-insensitive")
        XCTAssertEqual(xmlUnescape("&#x1F600;"), "\u{1F600}", "astral plane scalars decode")
    }

    func testLeavesNonEntityTextAlone() {
        XCTAssertEqual(xmlUnescape("100% &#; &# &#x; a#5;"), "100% &#; &# &#x; a#5;")
        XCTAssertEqual(xmlUnescape("&#xD800;"), "&#xD800;", "unpaired surrogates are not valid scalars")
        XCTAssertEqual(xmlUnescape("&#999999999999;"), "&#999999999999;", "out-of-range values stay literal")
    }

    // A literal "&#x27;" in the source is written &amp;#x27;, and must survive as
    // text rather than being decoded into an apostrophe.
    func testDoesNotDecodeEscapedAmpersandSequences() {
        XCTAssertEqual(xmlUnescape("&amp;#x27;"), "&#x27;")
        XCTAssertEqual(xmlUnescape("&amp;amp;"), "&amp;")
    }

    // End to end against Canvas-shaped XML: the prompt, an answer, and the quiz
    // title all carry numeric references the way a real Canvas export does.
    func testDecodesNumericReferencesInImportedQuestionText() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let item = """
        <item ident="q1" title="q1">
          <itemmetadata><qtimetadata><qtimetadatafield><fieldlabel>question_type</fieldlabel><fieldentry>multiple_choice_question</fieldentry></qtimetadatafield></qtimetadata></itemmetadata>
          <presentation>
            <material><mattext texttype="text/html">Which organelle holds the cell&#x27;s DNA?</mattext></material>
            <response_lid ident="response1" rcardinality="Single"><render_choice>
              <response_label ident="a"><material><mattext texttype="text/html">The cell&#8217;s nucleus</mattext></material></response_label>
              <response_label ident="b"><material><mattext texttype="text/html">Ribosome</mattext></material></response_label>
            </render_choice></response_lid>
          </presentation>
          <resprocessing><outcomes><decvar/></outcomes><respcondition><conditionvar><varequal respident="response1">a</varequal></conditionvar></respcondition></resprocessing>
        </item>
        """
        let quiz = "<questestinterop><assessment ident=\"a1\" title=\"Marta&#x27;s Quiz\"><section ident=\"root\">\(item)</section></assessment></questestinterop>"
        try quiz.write(to: directory.appendingPathComponent("quiz1.xml"), atomically: true, encoding: .utf8)
        let manifest = """
        <manifest><resources>
          <resource identifier="r1" type="imsqti_xmlv1p2/imscc_xmlv1p1/assessment" href="quiz1.xml"><file href="quiz1.xml"/></resource>
        </resources></manifest>
        """
        try manifest.write(to: directory.appendingPathComponent("imsmanifest.xml"), atomically: true, encoding: .utf8)

        let sections = try QTIImporter().importSections(fromDirectory: directory)

        XCTAssertEqual(sections[0].title, "Marta's Quiz")
        XCTAssertEqual(sections[0].questions[0].prompt, "Which organelle holds the cell's DNA?")
        XCTAssertEqual(sections[0].questions[0].answers[0].text, "The cell\u{2019}s nucleus")
    }

    // Canvas-authored matching items list every right-side option inside each
    // prompt's render_choice; the answer key lives in resprocessing. The importer
    // must pair prompts with their varequal targets, not the first listed option.
    func testImportsCanvasMatchingUsingAnswerKeyFromResprocessing() throws {
        let imported = try importClassicItem("""
        <item ident="q1" title="Match sounds">
          <itemmetadata><qtimetadata><qtimetadatafield><fieldlabel>question_type</fieldlabel><fieldentry>matching_question</fieldentry></qtimetadatafield></qtimetadata></itemmetadata>
          <presentation>
            <material><mattext texttype="text/html">Match each animal to its sound.</mattext></material>
            <response_lid ident="response_1000">
              <material><mattext texttype="text/plain">Dog</mattext></material>
              <render_choice>
                <response_label ident="101"><material><mattext>Meow</mattext></material></response_label>
                <response_label ident="102"><material><mattext>Bark</mattext></material></response_label>
                <response_label ident="103"><material><mattext>Moo</mattext></material></response_label>
              </render_choice>
            </response_lid>
            <response_lid ident="response_2000">
              <material><mattext texttype="text/plain">Cat</mattext></material>
              <render_choice>
                <response_label ident="101"><material><mattext>Meow</mattext></material></response_label>
                <response_label ident="102"><material><mattext>Bark</mattext></material></response_label>
                <response_label ident="103"><material><mattext>Moo</mattext></material></response_label>
              </render_choice>
            </response_lid>
          </presentation>
          <resprocessing>
            <outcomes><decvar maxvalue="100" minvalue="0" varname="SCORE" vartype="Decimal"/></outcomes>
            <respcondition><conditionvar><varequal respident="response_1000">102</varequal></conditionvar><setvar varname="SCORE" action="Add">50</setvar></respcondition>
            <respcondition><conditionvar><varequal respident="response_2000">101</varequal></conditionvar><setvar varname="SCORE" action="Add">50</setvar></respcondition>
          </resprocessing>
        </item>
        """)

        XCTAssertEqual(imported.type, .matching)
        XCTAssertEqual(imported.matches.map(\.prompt), ["Dog", "Cat"])
        XCTAssertEqual(imported.matches.map(\.match), ["Bark", "Meow"])
    }

    // Canvas survey exports carry the same matching presentation but no scoring,
    // so there is no answer key. Fall back to pairing each prompt with the option
    // at its own position instead of giving every prompt the first option.
    func testImportsSurveyMatchingWithoutResprocessingPositionally() throws {
        let imported = try importClassicItem("""
        <item ident="q1" title="Match sounds">
          <itemmetadata><qtimetadata><qtimetadatafield><fieldlabel>question_type</fieldlabel><fieldentry>matching_question</fieldentry></qtimetadatafield></qtimetadata></itemmetadata>
          <presentation>
            <material><mattext texttype="text/html">Match each animal to its sound.</mattext></material>
            <response_lid ident="response_1000">
              <material><mattext texttype="text/plain">Dog</mattext></material>
              <render_choice>
                <response_label ident="101"><material><mattext>Bark</mattext></material></response_label>
                <response_label ident="102"><material><mattext>Meow</mattext></material></response_label>
              </render_choice>
            </response_lid>
            <response_lid ident="response_2000">
              <material><mattext texttype="text/plain">Cat</mattext></material>
              <render_choice>
                <response_label ident="101"><material><mattext>Bark</mattext></material></response_label>
                <response_label ident="102"><material><mattext>Meow</mattext></material></response_label>
              </render_choice>
            </response_lid>
          </presentation>
        </item>
        """)

        XCTAssertEqual(imported.type, .matching)
        XCTAssertEqual(imported.matches.map(\.prompt), ["Dog", "Cat"])
        XCTAssertEqual(imported.matches.map(\.match), ["Bark", "Meow"])
    }

    // A matching question that survives import must export a usable Canvas item
    // again: every prompt keeps its own match in the classic answer key.
    func testMatchingSurvivesImportThenClassicExport() throws {
        let quiz = Quiz(title: "Round Trip", questions: [
            QuizQuestion(type: .matching, prompt: "Match.", matches: [
                MatchingPair(prompt: "Dog", match: "Bark"),
                MatchingPair(prompt: "Cat", match: "Meow")
            ])
        ])
        let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        try QTIPackageWriter(engine: .classicQuizzes).writeZip(for: quiz, to: archiveURL)

        let imported = try QTIImporter().importQuiz(fromZipAt: archiveURL)

        XCTAssertEqual(imported.questions[0].type, .matching)
        XCTAssertEqual(imported.questions[0].matches.map(\.prompt), ["Dog", "Cat"])
        XCTAssertEqual(imported.questions[0].matches.map(\.match), ["Bark", "Meow"])
    }

    /// Wraps a single classic item in a manifest + assessment on disk and
    /// imports it, returning the one parsed question.
    private func importClassicItem(_ item: String) throws -> QuizQuestion {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let quiz = "<questestinterop><assessment ident=\"a1\" title=\"Survey\"><section ident=\"root\">\(item)</section></assessment></questestinterop>"
        try quiz.write(to: directory.appendingPathComponent("quiz1.xml"), atomically: true, encoding: .utf8)
        let manifest = """
        <manifest><resources>
          <resource identifier="r1" type="imsqti_xmlv1p2/imscc_xmlv1p1/assessment" href="quiz1.xml"><file href="quiz1.xml"/></resource>
        </resources></manifest>
        """
        try manifest.write(to: directory.appendingPathComponent("imsmanifest.xml"), atomically: true, encoding: .utf8)

        let sections = try QTIImporter().importSections(fromDirectory: directory)
        return try XCTUnwrap(sections.first?.questions.first)
    }
}
