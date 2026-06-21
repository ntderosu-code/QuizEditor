import XCTest
@testable import QuizEditorCore

final class QuizBankIndexerTests: XCTestCase {
    private let indexer = QuizBankIndexer()

    private func sampleQuizzes() -> [(url: URL, quiz: Quiz)] {
        [
            (URL(fileURLWithPath: "/bank/bio.quizeditor"), Quiz(title: "Biology", questions: [
                QuizQuestion(type: .multipleChoice, prompt: "What organelle makes ATP?",
                             answers: [QuizAnswer(text: "Mitochondrion", isCorrect: true)],
                             tags: ["cells"]),
                QuizQuestion(type: .essay, prompt: "Explain photosynthesis.", tags: ["plants"])
            ])),
            (URL(fileURLWithPath: "/bank/chem.quizeditor"), Quiz(title: "Chemistry", questions: [
                QuizQuestion(type: .trueFalse, prompt: "Water is H2O.",
                             answers: [QuizAnswer(text: "True", isCorrect: true), QuizAnswer(text: "False", isCorrect: false)],
                             tags: ["molecules"])
            ]))
        ]
    }

    func testIndexFlattensAllQuestionsWithSource() {
        let bank = indexer.index(quizzes: sampleQuizzes())
        XCTAssertEqual(bank.count, 3)
        XCTAssertEqual(bank.first?.sourceTitle, "Biology")
        XCTAssertEqual(bank.first?.sourceURL.lastPathComponent, "bio.quizeditor")
    }

    func testSearchMatchesPromptAndAnswerText() {
        let bank = indexer.index(quizzes: sampleQuizzes())
        let atp = indexer.filter(bank, with: .init(searchText: "atp"))
        XCTAssertEqual(atp.count, 1)
        let mito = indexer.filter(bank, with: .init(searchText: "mitochondrion"))
        XCTAssertEqual(mito.count, 1)
    }

    func testFilterByTypeAndTag() {
        let bank = indexer.index(quizzes: sampleQuizzes())
        XCTAssertEqual(indexer.filter(bank, with: .init(type: .essay)).count, 1)
        XCTAssertEqual(indexer.filter(bank, with: .init(tag: "cells")).count, 1)
        XCTAssertEqual(indexer.filter(bank, with: .init(tag: "MOLECULES")).count, 1) // case-insensitive
    }

    func testTagsListIsDeDupedAndSorted() {
        let bank = indexer.index(quizzes: sampleQuizzes())
        XCTAssertEqual(indexer.tags(in: bank), ["cells", "molecules", "plants"])
    }

    func testIndexesQuizEditorFilesFromFolderReadOnly() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let quiz = Quiz(title: "Saved", questions: [QuizQuestion(type: .essay, prompt: "On disk?")])
        let data = try JSONEncoder().encode(quiz)
        try data.write(to: folder.appendingPathComponent("saved.quizeditor"))
        // A non-quiz file that must be ignored.
        try Data("not a quiz".utf8).write(to: folder.appendingPathComponent("notes.txt"))

        let bank = indexer.index(folder: folder)
        XCTAssertEqual(bank.count, 1)
        XCTAssertEqual(bank.first?.question.prompt, "On disk?")

        // Source file is untouched by indexing.
        let reread = try JSONDecoder().decode(Quiz.self, from: Data(contentsOf: folder.appendingPathComponent("saved.quizeditor")))
        XCTAssertEqual(reread, quiz)
    }
}
