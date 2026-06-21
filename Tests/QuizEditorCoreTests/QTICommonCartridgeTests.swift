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
