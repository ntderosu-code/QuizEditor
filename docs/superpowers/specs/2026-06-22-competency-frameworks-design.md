# Competency / standards framework mapping + coverage report (#25) — design

Date: 2026-06-22
Branch: `feature/competency-frameworks`
Part of the Discipline Personas epic (#19), Phase 3.

## Goal

A structured, user-editable framework taxonomy that questions link to (distinct
from free-form tags), plus coverage/blueprint reporting, so a quiz can be audited
against a competency set. All local, advisory, never exported.

## Core (`QuizEditorCore`)

- `FrameworkNode { id, code, label, parentID? }` — nested via `parentID`.
- `Framework { id, name, source, version, nodes: [FrameworkNode], isBuiltIn }`.
  Both Codable/Sendable/Identifiable/Equatable with tolerant decoders.
- Built-in starter: **Bloom's Revised Taxonomy** (6 nodes), shipped as a code
  constant (like `Persona.general`); always available, read-only.
- `Framework.importResult(fromJSON:)` → `(framework, warnings)`; warns on unknown
  top-level keys, fails only when `id`/`name` are missing.
- `CoverageReport.make(quiz:frameworks:)` — pure function returning per-node item
  counts, gaps (nodes with zero items), the count of questions linking no
  competency, and cognitive-level balance (from linked objectives' Bloom levels).
- Linter: built-in rule `noCompetencyLinked` + `PersonaLinterProfile.requiresCompetency`
  (opt-in). Fires when an item links no competency; General/default unaffected.
- AI: `PromptLinkContext` gains `competencies: [String]` (node labels); a
  `Quiz.promptLinkContext(for:frameworks:)` overload resolves them, and they flow
  into the existing linked-context prompt section.

## App (`QuizEditorApp`)

- `FrameworkStore` (ObservableObject): built-in(s) + user frameworks from
  `Application Support/QuizEditor/Frameworks/*.json`; load/save/delete. No network.
- Framework manager + editor: list with New/Edit/Duplicate/Delete/Import/Export
  (`.qeframework`); guided editor for name/source/version and an add/edit/nest/
  remove node tree. Built-ins read-only (Edit forks to a user copy).
- Competency picker in the question Links section: a searchable tree of framework
  nodes that sets `competencyIDs`, shown as chips (deferred from #23).
- `CoverageReportSheet`: counts per node, gaps, unmapped items, and cognitive-level
  balance; gaps conveyed by text + icon, not color.
- Wiring: a `frameworkStore` alongside `personaStore` in `ContentView`, threaded
  into the Links section, the AI call sites (competency labels), and the report.

## Guardrails

- Frameworks are advisory metadata — never written into QTI/Common Cartridge
  export (covered by an export-exclusion test). All local, no network.
- Built-in frameworks are read-only.
- Tree/picker keyboard-navigable, dark-mode complete, selection announced; report
  gaps not color-only.

## Testing

TDD core: framework round-trip, import validation + warnings, coverage math
(counts, gaps, unmapped, cognitive balance), the `noCompetencyLinked` gate,
competency labels in prompts, and framework export-exclusion. Tree/editor/report
UI verified by build + manual testing.

## Acceptance

- A built-in framework is available, an item links to a node, and the coverage
  report shows counts and gaps.
- A user-defined framework round-trips through import/export and persists locally.

## Out of scope

- Shipping large real-world framework taxonomies as built-ins (one recognizable
  starter; users import the rest).
