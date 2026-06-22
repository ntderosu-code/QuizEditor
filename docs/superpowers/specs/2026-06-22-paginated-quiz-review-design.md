# Paginated, applyable whole-quiz review — design

Date: 2026-06-22
Branch: `fix/ai-review-presentation` (stacked)

## Problem

The whole-quiz "Review Quiz" returns one free-form Markdown document. Two issues
surfaced in testing:

1. When a long quiz is processed in batches, the general "readiness" summary
   repeats for each batch.
2. There is no way to apply the review's feedback to the questions.

The request: review **10 questions at a time** to speed up analysis; while viewing
the first page, load the next; navigate pages with pagination; show the overall
readiness **once**; make feedback **applyable**.

## Decisions (confirmed)

- **Batched call per 10**: one AI request per page of 10 questions, returning a
  JSON array of per-question reviews.
- **Summary computed from results**: no extra AI call; derive a one-line readiness
  header from the per-question results.
- **Providers**: OpenAI-compatible API and Apple Foundation Models get the new
  paginated review. Copy-paste keeps today's copy-the-prompt behavior, unchanged.

## Core (`QuizEditorCore`)

Extend `QuestionReviewService` (reuses its alignment logic, which preserves answer
count and correctness):

- `makeBatchPrompt(questions: [QuizQuestion], quizTitle: String) -> String`
  Requests a JSON **array**, one element per question, each with its `index` and
  the existing review shape (`summary`, `suggestions`,
  `revised{prompt, answers, matches, feedback}`).
- `parseBatch(_ raw: String, originals: [QuizQuestion]) -> [QuestionReview]`
  Decodes the array, maps each element to `originals[index]`, and aligns revised
  fields exactly as the single-question parser does. Returns one `QuestionReview`
  per original, in order. A question the model omits becomes a clean
  "No issues reported." review (no revisions). Malformed JSON falls back to one
  clean review per question (nothing is lost; the page just shows no edits).

## App (`QuizEditorApp`)

- Extract `QuestionReviewDetail` from `QuestionReviewSheet`: a reusable view that
  renders a `QuestionReview` against its original (summary, suggestions, per-field
  before/after diffs with **Apply**), tracking applied fields and calling
  `onApply`. Both the item-review sheet and the quiz-review page use it.
- New `QuizReviewSheet`:
  - Splits questions into fixed **pages of 10**.
  - Per-page state: `idle / loading / loaded([QuestionReview]) / failed(String)`.
  - Loads page 1 on open; on a page finishing, prefetches the next; navigating to
    an unloaded page loads it.
  - Pagination footer: Prev · "Page X of Y" · Next.
  - One readiness header computed locally from loaded reviews: e.g. "Reviewed N of
    M questions — K have suggested edits." Updates as pages load; never repeats.
  - Renders each question on the current page via `QuestionReviewDetail`, writing
    back through a `Binding<[QuizQuestion]>` by question id. "Apply all on this
    page" applies every pending field on the visible page.
  - Provider-agnostic: takes `loadBatch: ([QuizQuestion]) async throws -> [QuestionReview]`.
- `AIPanel`:
  - Gains `questions: Binding<[QuizQuestion]>` (passed `$quiz.questions` from
    `ContentView`) so edits apply.
  - "Review Quiz" presents `QuizReviewSheet` for API / Foundation Models, building
    `loadBatch` as one `AIClient.complete` call (API) or one `FoundationModelsRunner.run`
    (on-device) per page. Copy-paste keeps `copyQuizPrompt`.

## Testing

TDD the core batch path:
- Array parse maps indices to the right questions.
- Revised answers/matches aligned per question; count and correctness preserved.
- Omitted question → clean review.
- Malformed JSON → one clean review per question.

UI verified by build + manual testing.

## Out of scope

- Page size is fixed at 10.
- Persona-aware review prompting (#21).
- Copy-paste paginated flow (provider can't auto-run per page).
