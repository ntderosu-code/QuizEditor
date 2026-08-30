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
        try QTIPackageWriter(target: .qti12).writeZip(for: original, to: archiveURL)

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
        try QTIPackageWriter(target: .qti21).writeZip(for: original, to: archiveURL)

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
        try QTIPackageWriter(target: .qti12).writeZip(for: quiz, to: archiveURL)

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

    // MARK: - New question types

    func testImportsFileUploadQuestionWithMimeAllowList() throws {
        let prompt = "Upload your essay"
        let item = """
        <item ident="q1" title="q1">
          <itemmetadata><qtimetadata>
            <qtimetadatafield><fieldlabel>question_type</fieldlabel><fieldentry>file_upload_question</fieldentry></qtimetadatafield>
          </qtimetadata></itemmetadata>
          <presentation>
            <material><mattext texttype="text/html">\(prompt)</mattext></material>
            <response_str ident="response1" rcardinality="Single" type="file">
              <render_fib fibtype="File" prompt="Upload" rows="1" columns="40" mimetype="application/pdf text/plain"/>
            </response_str>
          </presentation>
        </item>
        """
        let question = try importClassicItem(item)
        XCTAssertEqual(question.type, .fileUpload)
        XCTAssertEqual(question.prompt, prompt)
        XCTAssertEqual(question.allowedFileTypes, ["application/pdf", "text/plain"])
    }

    func testImportsFormulaQuestionFromClassicMetadata() throws {
        let item = """
        <item ident="q1" title="q1">
          <itemmetadata><qtimetadata>
            <qtimetadatafield><fieldlabel>question_type</fieldlabel><fieldentry>calculated_question</fieldentry></qtimetadatafield>
            <qtimetadatafield>
              <fieldlabel>formula_question</fieldlabel>
              <fieldentry><formula>m * a<variables><variable name="m">2</variable><variable name="a">9.8</variable></variables></formula></fieldentry>
            </qtimetadatafield>
          </qtimetadata></itemmetadata>
          <presentation>
            <material><mattext texttype="text/html">Compute F.</mattext></material>
            <response_str ident="response1" rcardinality="Single">
              <render_fib fibtype="Decimal" prompt="Box" rows="1" columns="20"/>
            </response_str>
          </presentation>
        </item>
        """
        let question = try importClassicItem(item)
        XCTAssertEqual(question.type, .formula)
        XCTAssertEqual(question.formula?.expression, "m * a")
        XCTAssertEqual(question.formula?.variables.count, 2)
        XCTAssertEqual(question.formula?.variables.first?.name, "m")
        XCTAssertEqual(question.formula?.computedValue, 19.6)
    }

    func testRecoversFormulaToleranceFromClassicBounds() throws {
        // The tolerance is not in the qtimetadata; it is implied by the accepted
        // band the exporter writes into resprocessing. Round-tripping a formula
        // must not silently turn a tolerance band into an exact match.
        let quiz = Quiz(title: "Physics", questions: [
            QuizQuestion(
                type: .formula,
                prompt: "Compute F.",
                formula: FormulaAnswer(
                    variables: [FormulaVariable(name: "m", value: 2), FormulaVariable(name: "a", value: 9.8)],
                    expression: "m * a",
                    tolerance: 0.5
                )
            )
        ])
        let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        try QTIPackageWriter(target: .qti12).writeZip(for: quiz, to: archiveURL)

        let imported = try QTIImporter().importQuiz(fromZipAt: archiveURL)
        let formula = try XCTUnwrap(imported.questions.first?.formula)
        XCTAssertEqual(formula.expression, "m * a")
        XCTAssertEqual(formula.tolerance, 0.5, accuracy: 1e-9)
    }

    func testFormulaWithoutToleranceBandImportsAsExactMatch() throws {
        let quiz = Quiz(title: "Physics", questions: [
            QuizQuestion(
                type: .formula,
                prompt: "Compute F.",
                formula: FormulaAnswer(
                    variables: [FormulaVariable(name: "m", value: 2), FormulaVariable(name: "a", value: 9.8)],
                    expression: "m * a"
                )
            )
        ])
        let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        try QTIPackageWriter(target: .qti12).writeZip(for: quiz, to: archiveURL)

        let imported = try QTIImporter().importQuiz(fromZipAt: archiveURL)
        XCTAssertEqual(imported.questions.first?.formula?.tolerance, 0)
    }

    func testRecognizesFormulaQTI21Type() throws {
        // The QTI 2.1 / New Quizzes community calls these `formula_question` —
        // the importer should map it to .formula too.
        let item = """
        <item ident="q1" title="q1">
          <itemmetadata><qtimetadata>
            <qtimetadatafield><fieldlabel>question_type</fieldlabel><fieldentry>formula_question</fieldentry></qtimetadatafield>
          </qtimetadata></itemmetadata>
          <presentation>
            <material><mattext texttype="text/html">f(x)</mattext></material>
            <response_str ident="response1" rcardinality="Single">
              <render_fib fibtype="Decimal" prompt="Box" rows="1" columns="20"/>
            </response_str>
          </presentation>
        </item>
        """
        let question = try importClassicItem(item)
        XCTAssertEqual(question.type, .formula)
    }

    // MARK: - Survey detection

    func testDetectsSurveyWhenNoScoringOrPoints() throws {
        // Surveys: no `points_possible`, no `<resprocessing>`, no respcondition.
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
        <questestinterop>
          <assessment ident="a" title="Course eval">
            <section ident="root">
              <item ident="q1" title="q1">
                <itemmetadata><qtimetadata>
                  <qtimetadatafield><fieldlabel>question_type</fieldlabel><fieldentry>multiple_choice_question</fieldentry></qtimetadatafield>
                </qtimetadata></itemmetadata>
                <presentation>
                  <material><mattext texttype="text/html">Pace?</mattext></material>
                  <response_lid ident="response1" rcardinality="Single">
                    <render_choice>
                      <response_label ident="a"><material><mattext texttype="text/html">Just right</mattext></material></response_label>
                      <response_label ident="b"><material><mattext texttype="text/html">Too fast</mattext></material></response_label>
                    </render_choice>
                  </response_lid>
                </presentation>
              </item>
            </section>
          </assessment>
        </questestinterop>
        """
        let dir = try writePackage(manifest: manifest, files: [("assessment.xml", assessment)])
        defer { try? FileManager.default.removeItem(at: dir) }

        let quiz = try QTIImporter().importQuiz(fromDirectory: dir)
        XCTAssertEqual(quiz.kind, .survey)
    }

    func testDetectsGradedWhenPointsOrScoringPresent() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <questestinterop>
          <assessment ident="a" title="Quiz">
            <qtimetadata><qtimetadatafield>
              <fieldlabel>cc_maxattempts</fieldlabel><fieldentry>1</fieldentry>
            </qtimetadatafield></qtimetadata>
            <section ident="root">
              <item ident="q1" title="q1">
                <itemmetadata><qtimetadata>
                  <qtimetadatafield><fieldlabel>question_type</fieldlabel><fieldentry>multiple_choice_question</fieldentry></qtimetadatafield>
                  <qtimetadatafield><fieldlabel>points_possible</fieldlabel><fieldentry>1</fieldentry></qtimetadatafield>
                </qtimetadata></itemmetadata>
                <presentation>
                  <material><mattext texttype="text/html">?</mattext></material>
                  <response_lid ident="response1" rcardinality="Single">
                    <render_choice>
                      <response_label ident="a"><material><mattext texttype="text/html">A</mattext></material></response_label>
                    </render_choice>
                  </response_lid>
                </presentation>
                <resprocessing>
                  <outcomes><decvar/></outcomes>
                  <respcondition><conditionvar><varequal respident="response1">a</varequal></conditionvar></respcondition>
                </resprocessing>
              </item>
            </section>
          </assessment>
        </questestinterop>
        """
        let dir = try writePackage(manifest: "<?xml version=\"1.0\"?><manifest><resources><resource identifier=\"q\" type=\"imsqti_xmlv1p2\" href=\"assessment.xml\"><file href=\"assessment.xml\"/></resource></resources></manifest>", files: [("assessment.xml", xml)])
        defer { try? FileManager.default.removeItem(at: dir) }

        let quiz = try QTIImporter().importQuiz(fromDirectory: dir)
        XCTAssertEqual(quiz.kind, .graded)
    }

    // MARK: - QTI 2.1 numeric and formula round-trips

    /// A New Quizzes (QTI 2.1) numeric export must come back as a graded numeric.
    /// Before this, `parseQTI21Item` had no numeric branch, so the item fell
    /// through to the multiple-choice tail, found no `simpleChoice`, and became
    /// an answerless essay.
    func testImportsQTI21NumericExactValueWithMargin() throws {
        let quiz = Quiz(title: "Physics", questions: [
            QuizQuestion(
                type: .numeric,
                prompt: "Acceleration due to gravity?",
                numeric: NumericAnswer(mode: .exact, value: 9.8, margin: 0.1)
            )
        ])
        let question = try roundTripThroughNewQuizzes(quiz)

        XCTAssertEqual(question.type, .numeric)
        XCTAssertEqual(question.numeric?.mode, .exact)
        XCTAssertEqual(try XCTUnwrap(question.numeric?.value), 9.8, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(question.numeric?.margin), 0.1, accuracy: 0.0001)
        let interval = try XCTUnwrap(question.numeric?.acceptedInterval)
        XCTAssertEqual(interval.low, 9.7, accuracy: 0.0001)
        XCTAssertEqual(interval.high, 9.9, accuracy: 0.0001)
    }

    /// A range item exports as the same `gte`/`lte` pair as an exact value with a
    /// margin, so the *mode* can't be recovered from QTI 2.1 — only the accepted
    /// interval can. It comes back as an equivalent exact-plus-margin spec, which
    /// grades identically.
    func testImportsQTI21NumericRangeAsAnEquivalentInterval() throws {
        let quiz = Quiz(title: "Physics", questions: [
            QuizQuestion(
                type: .numeric,
                prompt: "A plausible pH for rain?",
                numeric: NumericAnswer(mode: .range, rangeMin: 5.0, rangeMax: 6.5)
            )
        ])
        let question = try roundTripThroughNewQuizzes(quiz)

        XCTAssertEqual(question.type, .numeric)
        let interval = try XCTUnwrap(question.numeric?.acceptedInterval)
        XCTAssertEqual(interval.low, 5.0, accuracy: 0.0001)
        XCTAssertEqual(interval.high, 6.5, accuracy: 0.0001)
    }

    /// A numeric item with nothing to grade against still imports as a numeric,
    /// not as an essay. The spec comes back unconfigured.
    func testImportsQTI21NumericWithoutGradingSpecAsUnconfiguredNumeric() throws {
        let quiz = Quiz(title: "Physics", questions: [
            QuizQuestion(type: .numeric, prompt: "Estimate the mass.", numeric: NumericAnswer(mode: .exact))
        ])
        let question = try roundTripThroughNewQuizzes(quiz)

        XCTAssertEqual(question.type, .numeric)
        XCTAssertEqual(question.numeric?.isConfigured, false)
    }

    /// QTI 2.1 has no canonical slot for a formula expression, and this exporter
    /// writes formula items with exactly the same interaction, base type, and
    /// inline `responseProcessing` as a numeric. So a formula export deliberately
    /// degrades to a *graded numeric* on re-import: the answer key survives, the
    /// expression does not. It must not come back as an answerless essay.
    func testQTI21FormulaExportDegradesToGradedNumeric() throws {
        let quiz = Quiz(title: "Physics", questions: [
            QuizQuestion(
                type: .formula,
                prompt: "Compute F = m * a.",
                formula: FormulaAnswer(
                    variables: [FormulaVariable(name: "m", value: 2), FormulaVariable(name: "a", value: 9.8)],
                    expression: "m * a",
                    tolerance: 0.5
                )
            )
        ])
        let question = try roundTripThroughNewQuizzes(quiz)

        XCTAssertEqual(question.type, .numeric)
        XCTAssertEqual(question.numeric?.mode, .exact)
        XCTAssertEqual(try XCTUnwrap(question.numeric?.value), 19.6, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(question.numeric?.margin), 0.5, accuracy: 0.0001)
    }

    /// The float base type is what separates a numeric from the other items that
    /// also use `textEntryInteraction`. Short answer must stay short answer.
    func testQTI21ShortAnswerIsNotMistakenForNumeric() throws {
        let quiz = Quiz(title: "Vocab", questions: [
            QuizQuestion(
                type: .shortAnswer,
                prompt: "Name the process.",
                answers: [QuizAnswer(text: "photosynthesis", isCorrect: true)]
            )
        ])
        let question = try roundTripThroughNewQuizzes(quiz)

        XCTAssertNotEqual(question.type, .numeric)
    }

    /// Exports the quiz as New Quizzes (QTI 2.1), writes the package to disk, and
    /// imports it back — the same path a user takes exporting then re-importing.
    private func roundTripThroughNewQuizzes(_ quiz: Quiz) throws -> QuizQuestion {
        let package = try QTIExporter(target: .qti21).makePackage(for: quiz)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("items"), withIntermediateDirectories: true)
        for file in package.files {
            try file.contents.write(to: directory.appendingPathComponent(file.path), atomically: true, encoding: .utf8)
        }

        let sections = try QTIImporter().importSections(fromDirectory: directory)
        return try XCTUnwrap(sections.first?.questions.first)
    }

    private func writePackage(manifest: String, files: [(String, String)]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try manifest.write(to: dir.appendingPathComponent("imsmanifest.xml"), atomically: true, encoding: .utf8)
        for (name, contents) in files {
            try contents.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return dir
    }
}
