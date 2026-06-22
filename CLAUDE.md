# CLAUDE.md — Quiz Editor

Project guidance for working in this repository. Read before making changes.

## What this is

A free, private **macOS** app for authoring accessible quizzes and exchanging them
with any LMS via the open **QTI** and **Common Cartridge** formats. Swift Package
Manager, `swift-tools-version: 6.2`, macOS target. No third-party dependencies;
Apple frameworks only. Everything is local and offline by design.

## Architecture

Two targets (see `Package.swift`):

- **`QuizEditorCore`** (library): all logic and models. Pure, testable, no SwiftUI.
  Quiz model, QTI/Common Cartridge import/export, the offline linter, persona
  engine, linking model, competency frameworks, AI prompt building, marked-text
  parser. **Put logic here, not in the app.**
- **`QuizEditorApp`** (executable): SwiftUI app. Views, the document type, stores
  (`PersonaStore`, `FrameworkStore`), and thin glue. Depends on Core.
- **`QuizEditorCoreTests`** (tests): exercises Core. ~250 tests.

The app's main file is `QuizEditorApp.swift` (the `@main` app, `ContentView`, and
document types); other views live in feature files (`AIPanelViews.swift`,
`QuestionEditorViews.swift`, `ContentView+Detail.swift`, etc.). Keep large views
split; don't let one file grow back into a monolith.

## Build, run, test

```bash
swift build                       # build everything (Core + App)
swift test                        # run the full suite (must be green before merge)
Scripts/run-macos-app.sh          # build a debug .app bundle and launch it
swift run QuizEditorApp           # bare run (no bundle; document/UTType behavior is limited)
```

Use `Scripts/run-macos-app.sh` (not bare `swift run`) when you need real document
open/save and the `.quizeditor` file type, since those need the `Info.plist`
bundle. The icon is regenerated with `Scripts/generate-icon.swift` (rarely needed).

### Testing conventions

- **TDD is the norm here.** Write the failing test first, watch it fail, then make
  it pass. Nearly every feature in Core landed test-first.
- Tests run via SwiftPM (`swift test`), not Xcode schemes, so XCTest **`measure {}`
  baselines do not gate** in this flow. Performance regressions are caught by
  `LargeDocumentPerformanceTests` using **scaling/ratio guards** (machine-
  independent) plus loose absolute budgets. That file adds ~11s to a run; during
  fast iteration use `swift test --skip LargeDocumentPerformance`.
- Keep the suite fully green before opening or merging a PR.

## Core conventions (important)

- **Tolerant decoding everywhere.** Every model adds new fields with a custom
  `init(from:)` using `decodeIfPresent` + defaults, mirroring `QuizQuestion`. This
  is how quizzes/personas/frameworks saved against an older schema keep opening.
  When you add a field, follow this pattern, and add a round-trip + legacy-decode
  test.
- **Advisory, never coercive.** The linter, AI, and personas only *suggest*. They
  never block editing/export or change an export's correctness.
- **Author metadata is never exported.** Tags, difficulty, links (objectives,
  sources, stimuli, competencies), and a numeric question's expected unit must not
  appear in QTI/Common Cartridge output. There are export-exclusion tests; keep
  them passing when you touch the exporters.
- **Accessibility is the floor.** Color is never the only signal; figures require
  alt text; certain linter rules (accessibility) are non-overridable by personas.
- **No network.** Nothing in the app reaches the network except the user's own
  configured AI endpoint. Don't add analytics, telemetry, or remote fetches.
- **Persona packs are data.** A discipline persona is a `Persona` value configuring
  the engine (declarative linter rules, terminology lexicon, AI fragments, item
  types, linking/framework presets). Built-ins live in `DisciplinePersonas.swift`
  as value constants (most performant; no launch-time disk read). Adding a
  discipline = add a constant + validation tests; avoid new Swift unless the engine
  genuinely can't express a rule.

## Git workflow

- Branch off `main`; open a PR **targeting `main`**. (Lesson learned: do **not**
  base a PR on another open feature branch, or its merge lands on that branch
  instead of `main` and strands the work.)
- Keep PRs focused and reviewable; the suite must be green.
- Commit messages end with the footer:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: <session url>
  ```
- Use the `gh` CLI for PRs/issues (no GitHub MCP configured here).

## Release process

`Scripts/release.sh <version> [notary-profile]` builds, signs (Developer ID),
notarizes, staples, and zips a distributable `Quiz Editor.app`.

```bash
Scripts/release.sh 1.2.0          # notary profile defaults to QuizEditorNotary
```

What it does: `swift build -c release` → assemble `dist/Quiz Editor.app` with a
generated `Info.plist` (version comes from the `<version>` arg, sets both
`CFBundleShortVersionString` and `CFBundleVersion`, `LSMinimumSystemVersion` 14.0,
the `.quizeditor` document/UTType) → `codesign` with hardened runtime → zip →
submit to Apple notary (`xcrun notarytool ... --wait`) → `stapler staple` →
re-zip. Output: `dist/QuizEditor-<version>.zip`.

Prerequisites (one-time):

- A **"Developer ID Application"** certificate in the login keychain
  (team `C25Q3Q4YFN`, signing identity hardcoded in the script).
- A **notarytool keychain profile** named `QuizEditorNotary`:
  ```bash
  xcrun notarytool store-credentials QuizEditorNotary \
    --apple-id "<apple-id>" --team-id C25Q3Q4YFN --password "<app-specific-password>"
  ```

If the notary profile is absent, the script still produces a **signed but
un-notarized** zip and prints how to finish. Releases are distributed via **GitHub
Releases** (upload the stapled zip there); the landing page links to the latest
release.

There is **no CI** yet. If adding one, a GitHub Actions workflow running
`swift build` + `swift test` on push/PR is the natural first step (the performance
guards then run automatically).

## Public site & brand

- The marketing page is `docs/index.html`, served via **GitHub Pages** from
  `main` (pushing to `main` publishes it). Aesthetic: a Scantron/OMR exam
  instrument, committed periwinkle + teal, the answer-bubble motif throughout.
- Brand and design system are documented in `PRODUCT.md` and `DESIGN.md` (loaded by
  the `impeccable` design skill). **Copy rule: no em dashes or en dashes** in site
  text; use commas/colons/semicolons/periods/parentheses.

## Repo map

```
Sources/QuizEditorCore/   logic + models (QuizModels, Persona, QuestionLinter,
                          Linking, Framework, Numeric, CanvasQTIExporter,
                          QTIImporter, DisciplinePersonas, *Service, MarkedTextParser)
Sources/QuizEditorApp/    SwiftUI app, stores, views (split by feature)
Tests/QuizEditorCoreTests/ the test suite
Scripts/                  release.sh, run-macos-app.sh, generate-icon.swift
docs/                     GitHub Pages landing page + screenshots
dist/                     built/notarized release artifacts (git-ignored output)
PRODUCT.md / DESIGN.md    brand + design system for the landing page
```
