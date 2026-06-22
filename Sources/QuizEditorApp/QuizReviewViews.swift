import SwiftUI
import QuizEditorCore

/// The body of a single question's AI review: summary, suggestions, and per-field
/// before/after diffs with Apply. Extracted so both the single-question review
/// sheet and the paginated whole-quiz review render reviews the same way.
/// What a reviewed question emphasizes. Quiz-level tools reuse this one view:
/// full review shows the assessment plus every edit; revisions and feedback hide
/// the prose assessment and surface just the edits to apply.
enum ReviewFocus { case full, revisions, feedback }

struct QuestionReviewDetail: View {
    let review: QuestionReview
    /// The question as it was when reviewed — the "before" side of each diff.
    let original: QuizQuestion
    /// Optional heading (e.g. "Question 3") shown above the summary.
    var heading: String? = nil
    /// Which parts of the review to show. Defaults to the full review.
    var focus: ReviewFocus = .full
    /// Applies a mutation to the question this review belongs to. Last parameter
    /// so callers can pass it as a trailing closure.
    let onApply: (@escaping (inout QuizQuestion) -> Void) -> Void

    private enum Field { case prompt, answers, matches, feedback }
    @State private var appliedFields: Set<Field> = []
    @ScaledMetric(relativeTo: .callout) private var suggestionBulletSize: CGFloat = 5

    /// The assessment prose (summary + suggestions) only appears in a full review.
    private var showsAssessment: Bool { focus == .full }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let heading {
                Text(heading)
                    .font(.headline)
            }

            if showsAssessment {
                Text(review.summary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsAssessment, !review.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What to improve")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(Array(review.suggestions.enumerated()), id: \.offset) { _, suggestion in
                        Label {
                            Text(suggestion)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .font(.system(size: suggestionBulletSize))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }

            if review.hasRevisions {
                HStack {
                    Text("Suggested edits")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Apply all edits", action: applyAll)
                        .font(.caption)
                        .disabled(applicableFields.isSubset(of: appliedFields))
                }

                if let revisedPrompt = review.revisedPrompt {
                    diffRow(title: "Prompt", before: original.prompt, after: revisedPrompt, field: .prompt) {
                        $0.prompt = revisedPrompt
                    }
                }
                if appliesToAnswers, let revisedAnswers = review.revisedAnswers {
                    diffRow(title: "Answers", before: answersText(original.answers), after: answersText(revisedAnswers), field: .answers) {
                        $0.answers = revisedAnswers
                    }
                }
                if original.type == .matching, let revisedMatches = review.revisedMatches {
                    diffRow(title: "Matching pairs", before: matchesText(original.matches), after: matchesText(revisedMatches), field: .matches) {
                        $0.matches = revisedMatches
                    }
                }
                if let revisedFeedback = review.revisedFeedback {
                    diffRow(title: "Feedback", before: original.feedback.isEmpty ? "(none)" : original.feedback, after: revisedFeedback, field: .feedback) {
                        $0.feedback = revisedFeedback
                    }
                }
            } else {
                Label(emptyStateText, systemImage: "checkmark.seal")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func diffRow(title: String, before: String, after: String, field: Field, apply: @escaping (inout QuizQuestion) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if appliedFields.contains(field) {
                    Label("Applied", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button("Apply") {
                        onApply(apply)
                        appliedFields.insert(field)
                    }
                    .help("Replace the current \(title.lowercased()) with this rewrite")
                }
            }

            diffBlock(tag: "Before", text: before, tint: .red)
            diffBlock(tag: "After", text: after, tint: .green)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(.rect(cornerRadius: 10))
    }

    @ViewBuilder
    private func diffBlock(tag: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tag.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(tint.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(tint.opacity(0.35))
                )
                .clipShape(.rect(cornerRadius: 6))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tag): \(text)")
    }

    private var emptyStateText: String {
        switch focus {
        case .feedback: "Feedback already looks complete for this question."
        case .revisions: "No rewrites suggested — this question already reads well."
        case .full: "No rewrites suggested — this question already reads well."
        }
    }

    private var appliesToAnswers: Bool {
        original.type != .essay && original.type != .matching
    }

    private var applicableFields: Set<Field> {
        var fields: Set<Field> = []
        if review.revisedPrompt != nil { fields.insert(.prompt) }
        if appliesToAnswers, review.revisedAnswers != nil { fields.insert(.answers) }
        if original.type == .matching, review.revisedMatches != nil { fields.insert(.matches) }
        if review.revisedFeedback != nil { fields.insert(.feedback) }
        return fields
    }

    private func applyAll() {
        if let revisedPrompt = review.revisedPrompt, !appliedFields.contains(.prompt) {
            onApply { $0.prompt = revisedPrompt }
            appliedFields.insert(.prompt)
        }
        if appliesToAnswers, let revisedAnswers = review.revisedAnswers, !appliedFields.contains(.answers) {
            onApply { $0.answers = revisedAnswers }
            appliedFields.insert(.answers)
        }
        if original.type == .matching, let revisedMatches = review.revisedMatches, !appliedFields.contains(.matches) {
            onApply { $0.matches = revisedMatches }
            appliedFields.insert(.matches)
        }
        if let revisedFeedback = review.revisedFeedback, !appliedFields.contains(.feedback) {
            onApply { $0.feedback = revisedFeedback }
            appliedFields.insert(.feedback)
        }
    }

    private func answersText(_ answers: [QuizAnswer]) -> String {
        answers.map { "\($0.text)\($0.isCorrect ? "  (correct)" : "")" }.joined(separator: "\n")
    }

    private func matchesText(_ matches: [MatchingPair]) -> String {
        matches.map { "\($0.prompt) → \($0.match)" }.joined(separator: "\n")
    }
}

/// A reviewed question on a page: its review, the snapshot it was reviewed
/// against, and its position in the whole quiz.
struct QuizReviewItem: Identifiable {
    let globalIndex: Int
    let original: QuizQuestion
    let review: QuestionReview
    var id: Int { globalIndex }
}

/// The paginated whole-quiz review. Questions are analyzed a page (of 10) at a
/// time in one batched request each; the next page prefetches while the current
/// one is read. The readiness header is computed locally from results — there is
/// no separate AI summary, so it never repeats per page. Each question's edits
/// can be applied back to the quiz.
struct QuizReviewSheet: View {
    let quizTitle: String
    @Binding var questions: [QuizQuestion]
    /// Reviews one page of questions in a single request. Provider-specific and
    /// injected by the caller so this sheet stays provider-agnostic.
    let loadBatch: ([QuizQuestion]) async throws -> [QuestionReview]
    /// Window title for this run (Review Quiz, Suggested Revisions, Drafted Feedback).
    var title: String = "Quiz Review"
    /// Which parts of each question's result to show; passed through to the detail.
    var focus: ReviewFocus = .full

    @Environment(\.dismiss) private var dismiss

    private let pageSize = 10

    enum PageState {
        case idle
        case loading
        case loaded([QuizReviewItem])
        case failed(String)
    }

    @State private var pageStates: [PageState] = []
    @State private var currentPage = 0

    private var pageCount: Int {
        max(1, Int(ceil(Double(questions.count) / Double(pageSize))))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 600)
        .onAppear {
            if pageStates.isEmpty {
                pageStates = Array(repeating: .idle, count: pageCount)
            }
            ensureLoaded(currentPage)
        }
    }

    // MARK: - Header (locally computed readiness)

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "sparkles")
                .font(.title2.bold())
            Text(readinessSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    /// All reviews loaded so far, across every page.
    private var loadedItems: [QuizReviewItem] {
        pageStates.flatMap { state -> [QuizReviewItem] in
            if case .loaded(let items) = state { return items }
            return []
        }
    }

    private var readinessSummary: String {
        let reviewed = loadedItems.count
        let total = questions.count
        guard reviewed > 0 else { return "Analyzing \(total) question\(total == 1 ? "" : "s")…" }
        let needEdits = loadedItems.filter { $0.review.hasRevisions }.count
        let clean = reviewed - needEdits
        let scope = reviewed == total ? "all \(total)" : "\(reviewed) of \(total)"
        let plural = total == 1 ? "" : "s"
        switch focus {
        case .feedback:
            return "Drafted feedback for \(scope) question\(plural) — \(needEdits) ready to apply, \(clean) already complete."
        case .revisions:
            return "Suggested revisions for \(scope) question\(plural) — \(needEdits) with edits to apply, \(clean) look clean."
        case .full:
            return "Reviewed \(scope) question\(plural) — \(needEdits) with suggested edits, \(clean) look clean."
        }
    }

    // MARK: - Content (current page)

    @ViewBuilder
    private var content: some View {
        if questions.isEmpty {
            ContentUnavailableView("No questions to review", systemImage: "tray")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch state(for: currentPage) {
            case .idle, .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Reviewing questions \(pageRangeLabel(currentPage))…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                VStack(spacing: 12) {
                    Label("Couldn't review this page", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try again") { load(currentPage) }
                        .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let items):
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(items) { item in
                            QuestionReviewDetail(
                                review: item.review,
                                original: item.original,
                                heading: "Question \(item.globalIndex + 1)",
                                focus: focus
                            ) { mutate in
                                guard questions.indices.contains(item.globalIndex) else { return }
                                mutate(&questions[item.globalIndex])
                            }
                            Divider()
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Footer (pagination)

    private var footer: some View {
        HStack {
            Button {
                goTo(currentPage - 1)
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(currentPage == 0)

            Spacer()

            Text("Page \(currentPage + 1) of \(pageCount)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                goTo(currentPage + 1)
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(currentPage >= pageCount - 1)

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
    }

    // MARK: - Paging and loading

    private func state(for page: Int) -> PageState {
        pageStates.indices.contains(page) ? pageStates[page] : .idle
    }

    private func questionsForPage(_ page: Int) -> [(index: Int, question: QuizQuestion)] {
        let start = page * pageSize
        let end = min(start + pageSize, questions.count)
        guard start < end else { return [] }
        return (start..<end).map { ($0, questions[$0]) }
    }

    private func pageRangeLabel(_ page: Int) -> String {
        let slice = questionsForPage(page)
        guard let first = slice.first?.index, let last = slice.last?.index else { return "" }
        return first == last ? "\(first + 1)" : "\(first + 1)–\(last + 1)"
    }

    private func goTo(_ page: Int) {
        guard page >= 0, page < pageCount else { return }
        currentPage = page
        ensureLoaded(page)
    }

    /// Loads a page if it hasn't started yet.
    private func ensureLoaded(_ page: Int) {
        if case .idle = state(for: page) { load(page) }
    }

    private func load(_ page: Int) {
        let slice = questionsForPage(page)
        guard !slice.isEmpty, pageStates.indices.contains(page) else { return }
        pageStates[page] = .loading
        let originals = slice.map(\.question)
        Task {
            do {
                let reviews = try await loadBatch(originals)
                let items = slice.enumerated().map { offset, entry in
                    QuizReviewItem(
                        globalIndex: entry.index,
                        original: entry.question,
                        review: offset < reviews.count ? reviews[offset] : QuestionReview(summary: "No issues reported.")
                    )
                }
                if pageStates.indices.contains(page) { pageStates[page] = .loaded(items) }
                // Prefetch the next page so it's ready while this one is read.
                ensureLoaded(page + 1)
            } catch {
                if pageStates.indices.contains(page) { pageStates[page] = .failed("\(error)") }
            }
        }
    }
}
