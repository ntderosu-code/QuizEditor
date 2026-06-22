import SwiftUI
import UniformTypeIdentifiers
import AppKit
import QuizEditorCore

extension ContentView {
    var selectedQuestionForPreview: (number: Int, question: QuizQuestion)? {
        guard let index = quiz.questions.firstIndex(where: { $0.id == selectedQuestionID }) else { return nil }
        return (index + 1, quiz.questions[index])
    }

    @ViewBuilder
    var editorDetail: some View {
        if let selectedIndex = quiz.questions.firstIndex(where: { $0.id == selectedQuestionID }) {
            QuestionEditor(
                question: $quiz.questions[selectedIndex],
                quizTitle: quiz.title,
                questionNumber: selectedIndex + 1,
                questionTotal: quiz.questions.count,
                objectives: $quiz.objectives,
                sources: $quiz.sources,
                stimuli: $quiz.stimuli,
                frameworks: frameworkStore.frameworks,
                persona: activePersona
            ) {
                deleteQuestion(id: quiz.questions[selectedIndex].id)
            }
            .id(quiz.questions[selectedIndex].id)
        } else {
            ContentUnavailableView {
                Label("No Question Selected", systemImage: "questionmark.square.dashed")
            } description: {
                Text("Choose a question or add a new one to start writing.")
            } actions: {
                // Stack the actions so they never overflow the (sometimes narrow)
                // editor card. Each stretches to a shared width for a tidy column.
                VStack(spacing: 8) {
                    Button {
                        addQuestion()
                    } label: {
                        Label("Add Question", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Import Marked Text", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }

                    Menu {
                        Button("Keep Formatting…") {
                            importPreservesFormatting = true
                            isQTIImporterPresented = true
                        }
                        Button("Plain Text…") {
                            importPreservesFormatting = false
                            isQTIImporterPresented = true
                        }
                    } label: {
                        Label("Import QTI Zip", systemImage: "doc.zipper")
                            .frame(maxWidth: .infinity)
                    } primaryAction: {
                        importPreservesFormatting = true
                        isQTIImporterPresented = true
                    }
                }
                .frame(width: 240)
            }
        }
    }

    var defaultExportFilename: String {
        let safeTitle = quiz.title
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return (safeTitle.isEmpty ? "canvas-quiz" : safeTitle) + ".zip"
    }

    // MARK: - Question mutations (undoable)

    /// Applies a structural change to the quiz and registers it with the window's
    /// UndoManager so Edit ▸ Undo restores the prior state (e.g. before a merge).
    func mutateQuiz(to newQuiz: Quiz, actionName: String) {
        let previous = quiz
        quiz = newQuiz
        registerUndo(restoring: previous, then: newQuiz, actionName: actionName)
    }

    func registerUndo(restoring restoreState: Quiz, then redoState: Quiz, actionName: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: undoCoordinator) { _ in
            quiz = restoreState
            fixSelection(in: restoreState)
            registerUndo(restoring: redoState, then: restoreState, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    func fixSelection(in quizState: Quiz) {
        if let selected = selectedQuestionID, quizState.questions.contains(where: { $0.id == selected }) { return }
        selectedQuestionID = quizState.questions.first?.id
    }

    func addQuestion() {
        let question = QuizQuestion(
            type: .multipleChoice,
            prompt: "New question",
            answers: [
                QuizAnswer(text: "Correct answer", isCorrect: true),
                QuizAnswer(text: "Distractor", isCorrect: false)
            ]
        )
        var updated = quiz
        updated.questions.append(question)
        mutateQuiz(to: updated, actionName: "Add Question")
        selectedQuestionID = question.id
    }

    /// Appends questions (with fresh IDs) from the bank or AI authoring.
    func addQuestions(_ questions: [QuizQuestion], actionName: String) {
        guard !questions.isEmpty else { return }
        let merger = QuizMerger()
        let fresh = questions.map { merger.withFreshIDs($0) }
        var updated = quiz
        updated.questions.append(contentsOf: fresh)
        mutateQuiz(to: updated, actionName: actionName)
        if let first = fresh.first?.id { selectedQuestionID = first }
    }

    func duplicateQuestion(id: UUID) {
        guard let index = quiz.questions.firstIndex(where: { $0.id == id }) else { return }
        let copy = QuizMerger().withFreshIDs(quiz.questions[index])
        var updated = quiz
        updated.questions.insert(copy, at: index + 1)
        mutateQuiz(to: updated, actionName: "Duplicate Question")
        selectedQuestionID = copy.id
    }

    func deleteQuestion(id: UUID) {
        guard let index = quiz.questions.firstIndex(where: { $0.id == id }) else { return }
        var updated = quiz
        updated.questions.remove(at: index)
        mutateQuiz(to: updated, actionName: "Delete Question")
        if selectedQuestionID == id {
            let nextIndex = min(index, updated.questions.count - 1)
            selectedQuestionID = updated.questions.indices.contains(nextIndex) ? updated.questions[nextIndex].id : nil
        }
    }

    func moveQuestions(from offsets: IndexSet, to destination: Int) {
        var updated = quiz
        updated.questions.move(fromOffsets: offsets, toOffset: destination)
        mutateQuiz(to: updated, actionName: "Reorder Questions")
    }

    func nudgeQuestion(id: UUID, by delta: Int) {
        guard let index = quiz.questions.firstIndex(where: { $0.id == id }) else { return }
        let target = index + delta
        guard quiz.questions.indices.contains(target) else { return }
        var updated = quiz
        updated.questions.swapAt(index, target)
        mutateQuiz(to: updated, actionName: "Move Question")
        selectedQuestionID = id
    }

    // MARK: - Selection / navigation

    func selectAdjacent(_ delta: Int) {
        guard let current = selectedQuestionID,
              let index = quiz.questions.firstIndex(where: { $0.id == current }) else {
            selectedQuestionID = quiz.questions.first?.id
            return
        }
        let target = index + delta
        guard quiz.questions.indices.contains(target) else { return }
        selectedQuestionID = quiz.questions[target].id
    }

    func selectEdge(first: Bool) {
        selectedQuestionID = first ? quiz.questions.first?.id : quiz.questions.last?.id
    }

    func makeCommandActions() -> QuizCommandActions {
        let index = selectedQuestionID.flatMap { id in quiz.questions.firstIndex(where: { $0.id == id }) }
        let lastIndex = quiz.questions.count - 1
        return QuizCommandActions(
            hasSelection: selectedQuestionID != nil,
            canSelectPrevious: (index ?? 0) > 0,
            canSelectNext: index.map { $0 < lastIndex } ?? false,
            canMoveUp: (index ?? 0) > 0,
            canMoveDown: index.map { $0 < lastIndex } ?? false,
            addQuestion: addQuestion,
            selectPrevious: { selectAdjacent(-1) },
            selectNext: { selectAdjacent(1) },
            selectFirst: { selectEdge(first: true) },
            selectLast: { selectEdge(first: false) },
            moveUp: { if let id = selectedQuestionID { nudgeQuestion(id: id, by: -1) } },
            moveDown: { if let id = selectedQuestionID { nudgeQuestion(id: id, by: 1) } },
            duplicate: { if let id = selectedQuestionID { duplicateQuestion(id: id) } },
            delete: { if let id = selectedQuestionID { deleteQuestion(id: id) } },
            showQuickSwitch: { isQuickSwitchPresented = true }
        )
    }

    // MARK: - Import / merge (via the question picker)

    func importMarkedText(_ text: String) {
        do {
            let marker = CorrectAnswerMarker(symbol: correctMarkerSymbol, location: correctMarkerLocation)
            let parsed = try MarkedTextParser(correctAnswerMarker: marker).parse(text)
            // Defer the picker until the import sheet has fully dismissed.
            pendingImport = PendingImport(questions: parsed.questions, importedTitle: parsed.title, source: "marked text")
            isImporterPresented = false
        } catch {
            // Close the sheet so the error alert (declared under it) can present;
            // pendingImport stays nil so onDismiss won't open the picker.
            pendingImport = nil
            isImporterPresented = false
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func presentPendingImportPicker() {
        guard let pending = pendingImport else { return }
        pendingImport = nil
        presentImportPicker(questions: pending.questions, importedTitle: pending.importedTitle, source: pending.source)
    }

    func importQTIArchive(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            let imported = try QTIImporter(preserveFormatting: importPreservesFormatting).importQuiz(fromZipAt: url)
            presentImportPicker(questions: imported.questions, importedTitle: imported.title, source: url.lastPathComponent)
        } catch {
            errorMessage = "QTI import failed: \(error.localizedDescription)"
        }
    }

    func presentImportPicker(questions: [QuizQuestion], importedTitle: String?, source: String) {
        guard !questions.isEmpty else {
            errorMessage = "No questions were found in the \(source)."
            return
        }
        importPickerContext = ImportPickerContext(
            title: "Import Questions",
            sourceDescription: "From \(source) — choose which questions to import.",
            candidates: importCandidates(for: questions),
            confirmVerb: "Import",
            importedTitle: importedTitle,
            actionName: "Import Questions",
            onConfirm: { selected, title, action in commitImport(selected, importedTitle: title, actionName: action) }
        )
    }

    func mergeFromFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else { return }

            var collected: [QuizQuestion] = []
            var failed: [String] = []
            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                if let questions = try? loadQuestions(from: url) {
                    collected.append(contentsOf: questions)
                } else {
                    failed.append(url.lastPathComponent)
                }
            }

            guard !collected.isEmpty else {
                errorMessage = "No questions could be read from the selected file\(urls.count == 1 ? "" : "s")."
                return
            }

            let names = urls.map(\.lastPathComponent).joined(separator: ", ")
            var description = "From \(names) — duplicates are unchecked. Checking a duplicate keeps both copies."
            if !failed.isEmpty { description += " Couldn't read: \(failed.joined(separator: ", "))." }

            importPickerContext = ImportPickerContext(
                title: "Merge Questions",
                sourceDescription: description,
                candidates: importCandidates(for: collected),
                confirmVerb: "Merge",
                importedTitle: nil,
                actionName: "Merge Questions",
                onConfirm: { selected, title, action in commitImport(selected, importedTitle: title, actionName: action) }
            )
        } catch {
            errorMessage = "Merge failed: \(error.localizedDescription)"
        }
    }

    func loadQuestions(from url: URL) throws -> [QuizQuestion] {
        if url.pathExtension.lowercased() == "zip" {
            return try QTIImporter().importQuiz(fromZipAt: url).questions
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Quiz.self, from: data).questions
    }

    /// Flags incoming questions that duplicate one already in the quiz (prompt + type).
    func importCandidates(for questions: [QuizQuestion]) -> [ImportCandidate] {
        let merger = QuizMerger()
        let existingKeys = Set(quiz.questions.map(merger.duplicateKey(for:)))
        return questions.map {
            ImportCandidate(question: $0, isDuplicate: existingKeys.contains(merger.duplicateKey(for: $0)))
        }
    }

    // MARK: - Common Cartridge (.imscc) import

    var imsccContentTypes: [UTType] {
        if let imscc = UTType(filenameExtension: "imscc") {
            return [imscc, .zip]
        }
        return [.zip]
    }

    func importCommonCartridge(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            let sections = try QTIImporter(preserveFormatting: importPreservesFormatting).importSections(fromZipAt: url)
            let candidates = importCandidates(sections: sections)
            guard !candidates.isEmpty else {
                errorMessage = "No quiz questions were found in \(url.lastPathComponent)."
                return
            }

            let quizzes = sections.filter { $0.kind == .assessment }.count
            let banks = sections.filter { $0.kind == .questionBank }.count
            importPickerContext = ImportPickerContext(
                title: "Import from Common Cartridge",
                sourceDescription: "From \(url.lastPathComponent) — \(sectionSummary(quizzes: quizzes, banks: banks)). Choose which questions to import.",
                candidates: candidates,
                confirmVerb: "Import",
                importedTitle: nil,
                actionName: "Import Common Cartridge",
                onConfirm: { selected, title, action in commitImport(selected, importedTitle: title, actionName: action) }
            )
        } catch {
            errorMessage = "Common Cartridge import failed: \(error.localizedDescription)"
        }
    }

    func importCandidates(sections: [QTISection]) -> [ImportCandidate] {
        let merger = QuizMerger()
        let existingKeys = Set(quiz.questions.map(merger.duplicateKey(for:)))
        return sections.flatMap { section in
            let prefix = section.kind == .questionBank ? "Bank" : "Quiz"
            return section.questions.map { question in
                ImportCandidate(
                    question: question,
                    isDuplicate: existingKeys.contains(merger.duplicateKey(for: question)),
                    sourceLabel: "\(prefix): \(section.title)"
                )
            }
        }
    }

    func sectionSummary(quizzes: Int, banks: Int) -> String {
        var parts: [String] = []
        if quizzes > 0 { parts.append("\(quizzes) quiz\(quizzes == 1 ? "" : "zes")") }
        if banks > 0 { parts.append("\(banks) item bank\(banks == 1 ? "" : "s")") }
        return parts.isEmpty ? "no sections" : parts.joined(separator: ", ")
    }

    func commitImport(_ questions: [QuizQuestion], importedTitle: String?, actionName: String) {
        guard !questions.isEmpty else { return }
        let merger = QuizMerger()
        let fresh = questions.map { merger.withFreshIDs($0) }
        var updated = quiz
        if updated.questions.isEmpty, isDefaultTitle(updated.title), let importedTitle, !importedTitle.isEmpty {
            updated.title = importedTitle
        }
        updated.questions.append(contentsOf: fresh)
        mutateQuiz(to: updated, actionName: actionName)
        selectedQuestionID = fresh.first?.id ?? selectedQuestionID
    }

    func isDefaultTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "Untitled Quiz"
    }

    func exportPaperExam(_ options: PaperExamOptions) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        let base = (defaultExportFilename as NSString).deletingPathExtension
        panel.nameFieldStringValue = base + (options.includeAnswerKey ? "-answer-key.html" : "-exam.html")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let document = PaperExamBuilder().document(for: quiz, options: options)
            try document.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Paper exam export failed: \(error.localizedDescription)"
        }
    }

    func exportFormattedDocument() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = (defaultExportFilename as NSString).deletingPathExtension + ".html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let document = FormattedDocumentBuilder().document(for: quiz)
            try document.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Document export failed: \(error.localizedDescription)"
        }
    }

    func prepareExport(engine: CanvasQuizEngine) {
        let altIssues = QuizAccessibilityValidator().imagesMissingAltText(in: quiz)
        guard altIssues.isEmpty else {
            errorMessage = "Export blocked — add alt text first. \(altIssues.joined(separator: "; "))."
            return
        }

        // Validate the package (well-formed XML, manifest consistency, and a
        // re-import round-trip). Clean packages export straight away; otherwise the
        // findings are shown first so the user can fix them or proceed anyway.
        let validationIssues = QTIValidator().validateExport(of: quiz, engine: engine)
        if validationIssues.isEmpty {
            finishExport(engine: engine)
        } else {
            qtiValidation = QTIValidationContext(engine: engine, issues: validationIssues)
        }
    }

    func finishExport(engine: CanvasQuizEngine) {
        do {
            exportDocument = try QTIArchiveDocument(quiz: quiz, engine: engine)
            isExporterPresented = true
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func checkSpelling() {
        NSApp.sendAction(#selector(NSText.checkSpelling(_:)), to: nil, from: nil)
    }

    func showSpellingPanel() {
        NSApp.sendAction(#selector(NSText.showGuessPanel(_:)), to: nil, from: nil)
    }

    func toggleContinuousSpellChecking() {
        NSApp.sendAction(#selector(NSTextView.toggleContinuousSpellChecking(_:)), to: nil, from: nil)
    }
}
