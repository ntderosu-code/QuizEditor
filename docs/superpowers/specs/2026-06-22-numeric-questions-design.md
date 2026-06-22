# Numeric question type (+ advisory unit) — design

Date: 2026-06-22
Branch: `feature/numeric-questions`
Part of the Discipline Personas epic (#19), Phase 3.

## Context

Research confirmed: numeric value + tolerance is supported by QTI and by both
Canvas engines (Classic `numerical_question`, New Quizzes Numeric: exact/margin/
range/precision). **Units are not a gradeable field** in QTI or Canvas, so the
expected unit is tool-only authoring metadata, surfaced in the UI as such.

## Core (`QuizEditorCore`)

- `QuizQuestionType.numeric` (display "Numeric", canvas `numerical_question`).
- `NumericAnswer` on `QuizQuestion` (`numeric: NumericAnswer?`, tolerant-decoded):
  - `mode`: `exact` (value ± margin), `range` (min…max), `precision` (value to N digits).
  - `value`, `margin`, `rangeMin`, `rangeMax`, `precisionDigits`.
  - `expectedUnit: String?` — advisory only, never exported.
  - `isConfigured` helper (enough to grade).
- Exporters (`CanvasQTIExporter`):
  - Classic (QTI 1.2): a Decimal `render_fib` + `resprocessing` with
    `vargte`/`varlte` for exact±margin and range (exact margin 0 → `varequal`;
    precision → `varequal` on the value). The unit is never written.
  - New Quizzes (QTI 2.1): float `responseDeclaration` with the correct value, a
    `textEntryInteraction`, and a custom numeric `responseProcessing` (tolerance
    via `equal`/range comparison) instead of the shared match_correct template.
- Importer: parse numeric items back where feasible; otherwise fall through
  without crashing.
- Linter: a finding when a numeric question has no grading configured.

## App (`QuizEditorApp`)

- A numeric grading editor (when type == numeric): mode picker + the relevant
  value/margin/range/precision fields, replacing the option list.
- "Expected unit (optional)" field with helper text: "Not sent to your LMS — used
  only inside QuizEditor (linter and AI)."

## Guardrails

- Unit is tool-only metadata, excluded from every export (export-exclusion test).
- Absolute margin only (percent margin is New-Quizzes-only); noted in the UI.

## Testing

TDD: model round-trip, numeric classic + new-quizzes export XML, unit-not-exported,
the no-grading lint. UI by build + manual.

## Acceptance

- A numeric question with exact±margin / range / precision authors, persists, and
  exports to both Canvas engines as a numerical question.
- The expected unit never appears in an export and is labeled tool-only in the UI.
