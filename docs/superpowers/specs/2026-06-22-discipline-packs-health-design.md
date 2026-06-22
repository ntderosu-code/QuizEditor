# Phase 4: discipline packs — Health family + Social Work — design

Date: 2026-06-22
Branch: `feature/discipline-packs-health`
Part of the Discipline Personas epic (#19), Phase 4.

## Approach

The engine (linter declarative rules + overrides + lexicon + recall-drift +
competency gate, persona AI prompting, linking, frameworks, numeric/units) is
already built. A discipline pack is therefore **pure data**: a `Persona` value
configuring the engine. Packs ship as Swift value constants in `QuizEditorCore`
(most performant — in-memory literals, no launch-time disk read or JSON parse) and
remain read-only, forkable, and exportable.

## Packs (this PR)

- **Nursing** (#37, family health): SATA count-cue declarative rule (multipleAnswer);
  priority-language reminder; banned-abbreviation lexicon (QD/QOD/U/IU/MS/MSO4/cc →
  safe forms) via terminology; recall-drift on; NCSBN CJMM AI preamble + review/
  authoring/feedback guidelines + safety clauses; misconception-labeled distractors;
  default MC, preferred MC/multipleAnswer/fillInBlank/matching; NCLEX/CJMM framework
  presets.
- **Medicine** (#36, health): escalate `unemphasizedNegativeStem` to warning;
  single-best-answer + defer-to-guideline AI fragments; terminology "associated
  with" › "causes" and generic drug names; safety: never invent doses/citations.
- **Pharmacy** (#38, health): missing-units declarative rule on numeric dose items;
  calculation-safety AI fragments; generic names + banned-abbreviation lexicon;
  safety: never invent doses.
- **Public Health** (#43, health): correlation-vs-causation terminology
  ("associated with" › "causes"/"proves"); epi/biostatistics scenario AI fragments;
  suggest source/competency links.
- **Social Work** (#44, social-science): person-first / anti-oppressive terminology
  (deficit/stigmatizing terms → person-first); CSWE EPAS + NASW ethics AI fragments;
  `requiresCompetency` on (the epic's named opt-in gate for social work); CSWE EPAS
  framework presets.

## Wiring

- `Persona.builtInDisciplines: [Persona]` in core.
- `PersonaStore.loadAll()` seeds General + built-in disciplines (read-only, never
  shadowed by user files), then user personas.

## Validation (TDD)

Per pack, assert signature behavior through the real engine:
- Nursing: counted-SATA stem fires `sataCountCue`; "QD" flagged via lexicon; AI
  preamble present in review prompt.
- Medicine: an un-emphasized negative stem is escalated to `.warning`.
- Pharmacy: a unit-less numeric/fill-in dose fires the missing-units rule.
- Public Health / Social Work: discouraged terms flagged via lexicon; Social Work
  flags an item with no competency linked.
- General is unaffected (regression guard).

## Out of scope / future engine extensions

A few pre-engine rules need compound conditions the declarative primitives don't
express yet (e.g. Nursing "priority intent AND no patient cues AND short stem").
Shipped as the closest single-condition rule or deferred, not faked.
