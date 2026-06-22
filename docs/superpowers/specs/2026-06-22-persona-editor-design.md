# Persona editor + fork + import/export (#24) — design

Date: 2026-06-22
Branch: `feature/persona-editor`
Part of the Discipline Personas epic (#19), Phase 3.

## Goal

Make personas fully user-authorable, forkable, and shareable as files — no JSON
editing, all local/private, advisory-only.

## Core (`QuizEditorCore`)

- `Persona.fork()` — returns a user copy: fresh reverse-DNS `id`, `isBuiltIn =
  false`, `basePersonaID` set to the source, displayName "… (Copy)"; all profiles
  carried over so the fork starts identical to its source.
- `LintRuleCatalog` — the built-in `LintFinding.Rule`s with a human label,
  description, and default severity, for rendering the editor's override toggles.
  Excludes `QuestionLinter.nonOverridableRuleIDs`.
- `Persona.importResult(fromJSON:)` → `(persona, warnings)`: decodes a persona,
  collects warnings for unknown top-level keys (forward-compatible), and fails
  only when `id`/`displayName` are missing.

## App (`QuizEditorApp`)

- `PersonaStore.save(_:)` / `delete(_:)` — write/remove
  `Application Support/QuizEditor/Personas/<sanitized id>.json` then refresh
  `personas`. No network.
- `PersonaEditorSheet` (`PersonaEditorViews.swift`) — guided editor, sections:
  - Identity: displayName, summary, family, parent (shown when forked).
  - Built-in rules: per rule, an enable toggle + severity picker; non-overridable
    rules shown locked.
  - Declarative rules: list + add/edit/remove via a form (id, scope,
    requires/forbids pattern, item-type & difficulty gates, requires-stimulus/
    source, severity, message, suggestion).
  - AI profile: system preamble, review/authoring/feedback guideline bullets,
    distractor strategy, tone, safety clauses, temperature override, recall-drift
    toggle.
  - Terminology: preferred / discouraged / rationale rows.
  - Exemplars: string list.
  - Default & preferred item types.
- `PersonaManagementSheet` actions: New, Edit (user) / Duplicate-to-edit (built-in
  → fork), Delete (user), Export…, Import…
- Packaging: `.qepersona` single JSON file via `UTType(filenameExtension:
  "qepersona")` in open/save panels — no Info.plist changes. Import decodes →
  validates → saves into the Personas dir (fresh id on built-in collision) →
  reloads.

## Guardrails

- Built-in packs read-only; Edit forks to a user copy.
- The editor cannot disable the non-overridable accessibility rules.
- Imported personas are advisory data only; they never alter exports or reach the
  network.
- Accessible: keyboard-operable, dark-mode complete, fixed-header/scroll/footer,
  severity labeled not color-only, focus returns on close.

## Testing

TDD core: `fork` (fresh id, basePersonaID, isBuiltIn false, profiles carried),
catalog contents, full-persona JSON round-trip fidelity, import validation +
unknown-field warnings. UI verified by build + manual testing.

## Acceptance

- Fork a built-in, add a declarative rule via the form, see it fire in the linter,
  export and re-import on another machine with identical behavior.
- A composed base + fork persona resolves correctly (already handled by
  `PersonaResolver`).

## Out of scope

- Bundle format for exemplar figures (exemplars are plain strings today; a single
  JSON file suffices).
- Competency framework editing (#25).
