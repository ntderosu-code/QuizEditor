import XCTest
@testable import QuizEditorCore

final class QTICommonCartridgeTests: XCTestCase {
    private func mcItem(ident: String, prompt: String, correct: String, options: [(id: String, text: String)]) -> String {
        let labels = options.map { option in
            "<response_label ident=\"\(option.id)\"><material><mattext texttype=\"text/html\">\(option.text)</mattext></material></response_label>"
        }.joined()
        return """
        <item ident="\(ident)" title="\(ident)">
          <itemmetadata><qtimetadata><qtimetadatafield><fieldlabel>question_type</fieldlabel><fieldentry>multiple_choice_question</fieldentry></qtimetadatafield></qtimetadata></itemmetadata>
          <presentation>
            <material><mattext texttype="text/html">\(prompt)</mattext></material>
            <response_lid ident="response1" rcardinality="Single"><render_choice>\(labels)</render_choice></response_lid>
          </presentation>
          <resprocessing><outcomes><decvar/></outcomes><respcondition><conditionvar><varequal respident="response1">\(correct)</varequal></conditionvar></respcondition></resprocessing>
        </item>
        """
    }

    /// Writes a minimal Common Cartridge with one quiz (2 items) and one item
    /// bank (1 item) into a temporary directory.
    private func makeCartridge() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let item1 = mcItem(ident: "q1", prompt: "What is 2 + 2?", correct: "a", options: [("a", "4"), ("b", "5")])
        let item2 = mcItem(ident: "q2", prompt: "Capital of France?", correct: "a", options: [("a", "Paris"), ("b", "Lyon")])
        let bankItem = mcItem(ident: "b1", prompt: "What gas do plants absorb?", correct: "a", options: [("a", "CO2"), ("b", "O2")])

        let quiz = "<questestinterop><assessment ident=\"a1\" title=\"Quiz One\"><section ident=\"root\">\(item1)\(item2)</section></assessment></questestinterop>"
        let bank = "<questestinterop><objectbank ident=\"ob1\" title=\"Bank One\">\(bankItem)</objectbank></questestinterop>"
        let manifest = """
        <manifest>
          <resources>
            <resource identifier="r1" type="imsqti_xmlv1p2/imscc_xmlv1p1/assessment" href="quiz1.xml"><file href="quiz1.xml"/></resource>
            <resource identifier="r2" type="imsqti_xmlv1p2/imscc_xmlv1p1/question-bank" href="bank1.xml"><file href="bank1.xml"/></resource>
            <resource identifier="r3" type="webcontent" href="page.html"><file href="page.html"/></resource>
          </resources>
        </manifest>
        """

        try quiz.write(to: dir.appendingPathComponent("quiz1.xml"), atomically: true, encoding: .utf8)
        try bank.write(to: dir.appendingPathComponent("bank1.xml"), atomically: true, encoding: .utf8)
        try manifest.write(to: dir.appendingPathComponent("imsmanifest.xml"), atomically: true, encoding: .utf8)
        try "<html></html>".write(to: dir.appendingPathComponent("page.html"), atomically: true, encoding: .utf8)
        return dir
    }

    func testImportsQuizAndBankSectionsFromCartridge() throws {
        let dir = try makeCartridge()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sections = try QTIImporter().importSections(fromDirectory: dir)

        XCTAssertEqual(sections.count, 2)

        let quizSection = try XCTUnwrap(sections.first { $0.kind == .assessment })
        XCTAssertEqual(quizSection.title, "Quiz One")
        XCTAssertEqual(quizSection.questions.count, 2)
        XCTAssertEqual(quizSection.questions.first?.prompt, "What is 2 + 2?")
        XCTAssertEqual(quizSection.questions.first?.answers.first(where: { $0.isCorrect })?.text, "4")

        let bankSection = try XCTUnwrap(sections.first { $0.kind == .questionBank })
        XCTAssertEqual(bankSection.title, "Bank One")
        XCTAssertEqual(bankSection.questions.count, 1)
        XCTAssertEqual(bankSection.questions.first?.prompt, "What gas do plants absorb?")
    }

    func testIgnoresNonQuizResources() throws {
        let dir = try makeCartridge()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sections = try QTIImporter().importSections(fromDirectory: dir)
        // The webcontent page.html contributes no sections.
        XCTAssertFalse(sections.contains { $0.title == "page.html" })
        XCTAssertEqual(sections.flatMap(\.questions).count, 3)
    }

    /// Writes a Canvas-style cartridge where the question bank lives only in a
    /// `non_cc_assessments/<id>.xml.qti` file (Canvas's native QTI), and that same
    /// folder also holds a duplicate of the CC-standard assessment. Mirrors a real
    /// Canvas export: the bank's items are not inlined into the quiz, and the
    /// quiz's only group pulls from the bank via `<sourcebank_ref>`.
    private func makeCanvasCartridge() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("non_cc_assessments"), withIntermediateDirectories: true)

        let item1 = mcItem(ident: "q1", prompt: "What is 2 + 2?", correct: "a", options: [("a", "4"), ("b", "5")])
        let bankItem = mcItem(ident: "b1", prompt: "What gas do plants absorb?", correct: "a", options: [("a", "CO2"), ("b", "O2")])

        // CC-standard assessment (one direct item).
        let quiz = "<questestinterop><assessment ident=\"a1\" title=\"Sample Quiz\"><section ident=\"root\">\(item1)</section></assessment></questestinterop>"
        // Canvas-native copy of the SAME assessment (same ident) plus a group that
        // pulls from the bank. Importing this would double-count q1.
        let quizNative = """
        <questestinterop><assessment ident="a1" title="Sample Quiz"><section ident="root">\(item1)<section ident="grp" title="Group"><selection_ordering><selection><sourcebank_ref>ob1</sourcebank_ref><selection_number>1</selection_number></selection></selection_ordering></section></section></assessment></questestinterop>
        """
        let bank = "<questestinterop><objectbank ident=\"ob1\" title=\"Bank One\">\(bankItem)</objectbank></questestinterop>"
        let manifest = """
        <manifest>
          <resources>
            <resource identifier="r1" type="imsqti_xmlv1p2/imscc_xmlv1p1/assessment" href="a1/assessment_qti.xml"><file href="a1/assessment_qti.xml"/></resource>
            <resource identifier="r2" type="associatedcontent/imscc_xmlv1p1/learning-application-resource" href="non_cc_assessments/a1.xml.qti"><file href="non_cc_assessments/a1.xml.qti"/></resource>
            <resource identifier="r3" type="associatedcontent/imscc_xmlv1p1/learning-application-resource" href="non_cc_assessments/ob1.xml.qti"><file href="non_cc_assessments/ob1.xml.qti"/></resource>
          </resources>
        </manifest>
        """

        try FileManager.default.createDirectory(at: dir.appendingPathComponent("a1"), withIntermediateDirectories: true)
        try quiz.write(to: dir.appendingPathComponent("a1/assessment_qti.xml"), atomically: true, encoding: .utf8)
        try quizNative.write(to: dir.appendingPathComponent("non_cc_assessments/a1.xml.qti"), atomically: true, encoding: .utf8)
        try bank.write(to: dir.appendingPathComponent("non_cc_assessments/ob1.xml.qti"), atomically: true, encoding: .utf8)
        try manifest.write(to: dir.appendingPathComponent("imsmanifest.xml"), atomically: true, encoding: .utf8)
        return dir
    }

    func testImportsBankFromCanvasNonCCAssessmentsFolder() throws {
        let dir = try makeCanvasCartridge()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sections = try QTIImporter().importSections(fromDirectory: dir)

        // The objectbank in non_cc_assessments/ob1.xml.qti must be imported.
        let bankSection = try XCTUnwrap(sections.first { $0.kind == .questionBank })
        XCTAssertEqual(bankSection.title, "Bank One")
        XCTAssertEqual(bankSection.questions.count, 1)
        XCTAssertEqual(bankSection.questions.first?.prompt, "What gas do plants absorb?")

        // The quiz must appear exactly once with its single direct item, not
        // duplicated by the non_cc copy of the same assessment.
        let quizSections = sections.filter { $0.kind == .assessment }
        XCTAssertEqual(quizSections.count, 1)
        XCTAssertEqual(quizSections.first?.questions.count, 1)
        XCTAssertEqual(sections.flatMap(\.questions).count, 2)
    }

    /// A Canvas objectbank with no `title` attribute, named only by a
    /// `bank_title` qtimetadata field (the real Canvas export shape).
    private func namedBank(ident: String, bankTitle: String, item: String) -> String {
        """
        <questestinterop><objectbank ident="\(ident)">
          <qtimetadata>
            <qtimetadatafield><fieldlabel>bank_title</fieldlabel><fieldentry>\(bankTitle)</fieldentry></qtimetadatafield>
            <qtimetadatafield><fieldlabel>bank_state</fieldlabel><fieldentry>active</fieldentry></qtimetadatafield>
          </qtimetadata>
          \(item)
        </objectbank></questestinterop>
        """
    }

    func testNamesBanksFromBankTitleMetadataAndKeepsThemSeparate() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("non_cc_assessments"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let bankA = namedBank(ident: "ob1", bankTitle: "5805Quiz1",
                              item: mcItem(ident: "a1", prompt: "Bank A question?", correct: "a", options: [("a", "Yes"), ("b", "No")]))
        let bankB = namedBank(ident: "ob2", bankTitle: "Unfiled Questions",
                              item: mcItem(ident: "b1", prompt: "Bank B question?", correct: "a", options: [("a", "Yes"), ("b", "No")]))
        // List the banks out of alphabetical order in the manifest so the test
        // exercises the sort, not the file order.
        let manifest = """
        <manifest><resources>
          <resource identifier="ob2" type="associatedcontent/imscc_xmlv1p1/learning-application-resource" href="non_cc_assessments/ob2.xml.qti"><file href="non_cc_assessments/ob2.xml.qti"/></resource>
          <resource identifier="ob1" type="associatedcontent/imscc_xmlv1p1/learning-application-resource" href="non_cc_assessments/ob1.xml.qti"><file href="non_cc_assessments/ob1.xml.qti"/></resource>
        </resources></manifest>
        """
        try bankA.write(to: dir.appendingPathComponent("non_cc_assessments/ob1.xml.qti"), atomically: true, encoding: .utf8)
        try bankB.write(to: dir.appendingPathComponent("non_cc_assessments/ob2.xml.qti"), atomically: true, encoding: .utf8)
        try manifest.write(to: dir.appendingPathComponent("imsmanifest.xml"), atomically: true, encoding: .utf8)

        let sections = try QTIImporter().importSections(fromDirectory: dir)

        // Each bank must remain its own section, titled from bank_title (not all
        // collapsed into a generic "Question Bank"), and sorted alphabetically by
        // name regardless of manifest order.
        let banks = sections.filter { $0.kind == .questionBank }
        XCTAssertEqual(banks.map(\.title), ["5805Quiz1", "Unfiled Questions"])
        XCTAssertFalse(banks.contains { $0.title == "Question Bank" })
        XCTAssertEqual(try XCTUnwrap(banks.first { $0.title == "5805Quiz1" }).questions.first?.prompt, "Bank A question?")
    }

    func testPlainQTIAssessmentFallsBackToSingleSection() throws {
        // A package whose manifest references an assessment file that holds items
        // inline still yields one assessment section.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let item = mcItem(ident: "q1", prompt: "Single?", correct: "a", options: [("a", "Yes"), ("b", "No")])
        let assessment = "<questestinterop><assessment ident=\"a1\" title=\"Solo Quiz\"><section ident=\"root\">\(item)</section></assessment></questestinterop>"
        let manifest = "<manifest><resources><resource href=\"assessment.xml\"><file href=\"assessment.xml\"/></resource></resources></manifest>"
        try assessment.write(to: dir.appendingPathComponent("assessment.xml"), atomically: true, encoding: .utf8)
        try manifest.write(to: dir.appendingPathComponent("imsmanifest.xml"), atomically: true, encoding: .utf8)

        let sections = try QTIImporter().importSections(fromDirectory: dir)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.questions.count, 1)
    }
}
