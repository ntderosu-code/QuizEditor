# Quiz Editor

A native macOS app for authoring, reviewing, and round-tripping **Canvas QTI quizzes**. Write questions with rich text and images, get AI-assisted item-writing feedback, and import/export Canvas Classic (QTI 1.2) and New Quizzes (QTI 2.1) packages — with accessibility built in from the start.

> Built entirely on Apple frameworks (SwiftUI, AppKit, WebKit). No third-party dependencies.

## Features

- **Question editing** — multiple choice, multiple answer, true/false, fill-in-the-blank, short answer, essay, and matching.
- **Rich text (WYSIWYG)** — bold, italics, underline, lists, links, tables, and embedded images for prompts and feedback. Formatting round-trips through QTI.
- **Accessible by design** — alt text is *required* on images before export; VoiceOver labels, Dynamic Type, full keyboard operation, and color that is never the sole signal.
- **AI review** — per-question review against established item-writing guidelines (not just grammar), with a before/after diff and per-field "apply." Works with an OpenAI-compatible API, Apple Foundation Models, or copy/paste to another assistant.
- **Import** — Canvas QTI `.zip` packages (handles both per-file and single-file inline layouts), with a *keep formatting* or *plain text* option for messy sources. Also imports simple marked plain text.
- **Export** — Canvas Classic (QTI 1.2) and New Quizzes (QTI 2.1) packages as `.zip`.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 6 toolchain / Xcode 16+ (to build)

## Build & run

```sh
git clone https://github.com/ntderosu-code/QuizEditor.git
cd QuizEditor
swift run QuizEditorApp
```

Run the tests:

```sh
swift test
```

## Project layout

| Path | Purpose |
|---|---|
| `Sources/QuizEditorCore` | Models, QTI import/export, HTML utilities, AI review service |
| `Sources/QuizEditorApp` | SwiftUI app (editor, sidebar, AI panel) |
| `Tests/QuizEditorCoreTests` | Unit tests for import/export, HTML handling, and AI parsing |

## AI configuration

The AI Assistant panel supports three providers:

- **OpenAI-compatible API** — supply an endpoint, model, and API key (stored locally via `@AppStorage`).
- **Apple Foundation Models** — on-device, on supported macOS versions with Apple Intelligence enabled.
- **Copy/Paste** — copies a prepared prompt for use in Claude, ChatGPT, or another assistant.

API keys are stored on your machine and are only sent to the endpoint you configure.

## Accessibility

WCAG 2.1 AA is treated as the floor. Images cannot be exported without alt text (or an explicit "decorative" choice), every control is keyboard reachable with visible focus, and status changes are announced to VoiceOver.

## License

[MIT](LICENSE) © 2026 ntderosu-code

Third-party acknowledgements are listed in the app under **Help → Acknowledgements**.
