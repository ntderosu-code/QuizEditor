# Per-distractor misconception tagging — design

Date: 2026-06-22
Branch: `feature/misconception-tagging`
Part of the Discipline Personas epic (#19), Phase 3.

## Goal

Make the `QuizAnswer.misconceptionTag` field (added in #23) usable: let authors
label which misconception each distractor targets, and let AI distractor
generation produce those labels when a persona opts in.

## Core (`QuizEditorCore`)

- `QuestionAuthoringService.parseLabeledDistractors(_:)` → `[(text: String, misconception: String?)]`,
  tolerantly accepting both the current `{"distractors": ["text", …]}` /  bare
  `["text", …]` shapes and a richer `[{"text": "…", "misconception": "…"}]` /
  `{"distractors": [{...}]}` form. `parseDistractors` stays for callers that only
  want text.
- `PersonaAIProfile.labelsMisconceptions: Bool` (opt-in). When true,
  `makeDistractorsPrompt(…persona:)` appends a request to label each distractor's
  misconception; when false the prompt is byte-identical to today.

## App (`QuizEditorApp`)

- `AnswerEditor`: a compact "Misconception (optional)" field under each incorrect
  option, for multiple-choice / multiple-answer questions, bound to
  `misconceptionTag`.
- "Generate Distractors" (the editor path and the AI-panel path) stores any
  returned misconception labels on the new answers.
- A `labelsMisconceptions` toggle in the persona editor.

## Guardrails

- Advisory metadata only — already excluded from QTI/Common Cartridge export
  (covered by the #23 export test). Applies only to selectable distractors, not
  short-answer keys, essay, or matching.

## Testing

TDD: labeled-distractor parse (both shapes + back-compat with the text-only
parser), and the opt-in distractor prompt (off = byte-equivalent, on = requests
labels). UI verified by build.

## Acceptance

- An author can tag a distractor with a misconception and it persists.
- With a persona that opts in, generated distractors arrive with misconception
  labels stored on the answers.
