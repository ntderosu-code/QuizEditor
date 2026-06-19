# Quiz Editor

<img src="docs/screenshots/app-icon.png" alt="Quiz Editor app icon: a bubble sheet / scantron" width="128" align="right">

A native macOS app for authoring, reviewing, and round-tripping **Canvas QTI quizzes**. Write questions with rich text and images, get AI-assisted item-writing feedback, and import/export Canvas Classic (QTI 1.2) and New Quizzes (QTI 2.1) packages — with accessibility built in from the start.

> Built entirely on Apple frameworks (SwiftUI, AppKit, WebKit). No third-party dependencies.

![Quiz Editor main window — sidebar, question editor, and AI Assistant panel](docs/screenshots/editor.png)

## Features

- **Question editing** — multiple choice, multiple answer, true/false, fill-in-the-blank, short answer, essay, and matching.
- **Rich text (WYSIWYG)** — bold, italics, underline, lists, links, tables, and embedded images for prompts and feedback. Formatting round-trips through QTI.
- **Accessible by design** — alt text is *required* on images before export; VoiceOver labels, Dynamic Type, full keyboard operation, and color that is never the sole signal.
- **AI review** — per-question review against established item-writing guidelines (not just grammar), with a before/after diff and per-field "apply." Works with an OpenAI-compatible API, Apple Foundation Models, or copy/paste to another assistant.
- **Save & open** — store a quiz as a `.quizeditor` document (JSON) and reopen it later.
- **Import** — Canvas QTI `.zip` packages (handles both per-file and single-file inline layouts), with a *keep formatting* or *plain text* option for messy sources. Also imports simple marked plain text.
- **Export** — Canvas Classic (QTI 1.2) and New Quizzes (QTI 2.1) packages as `.zip`, plus a formatted, printable **HTML document**.
- **Preview** — a modal that renders a formatted version of the current question or the full quiz, with an optional answer key.

### AI review with a before/after diff

![AI Review sheet showing a before/after diff with per-field apply](docs/screenshots/ai-review.png)

### Import marked plain text

![Import Marked Text dialog with a correct-answer marker and sample text](docs/screenshots/import.png)

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

## App icon

The icon is a bubble sheet / scantron, designed for Apple's **Icon Composer** (Liquid Glass). The editable source is `AppIcon.icon/`; the rendered `Resources/AppIcon.icns` is bundled into the app by `Scripts/run-macos-app.sh`.

To regenerate the artwork and renditions:

```sh
# 1. Redraw the layer art (CoreGraphics)
swift Scripts/generate-icon.swift /tmp/iconwork
cp /tmp/iconwork/layer-foreground-1024.png AppIcon.icon/Assets/foreground.png

# 2. Render renditions from the .icon with Icon Composer's CLI (ictool)
ICT="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
"$ICT" AppIcon.icon --export-image --output-file icon-1024.png \
  --platform macOS --rendition Default --width 512 --height 512 --scale 2
```

Open `AppIcon.icon` in Icon Composer to tweak layers, gradient, and glass.

## Accessibility

WCAG 2.1 AA is treated as the floor. Images cannot be exported without alt text (or an explicit "decorative" choice), every control is keyboard reachable with visible focus, and status changes are announced to VoiceOver.

## License

[MIT](LICENSE) © 2026 Byron R Roush

Third-party acknowledgements are listed in the app under **Help → Acknowledgements**.
