# Quiz Editor

**A native macOS app for authoring, reviewing, and round-tripping Canvas QTI quizzes.**

Write questions with rich text and images, get AI-assisted item-writing feedback, and import/export Canvas Classic (QTI 1.2) and New Quizzes (QTI 2.1) packages — accessible from the first keystroke.

[View on GitHub](https://github.com/ntderosu-code/QuizEditor){: .btn }

---

## What it does

- **Author every Canvas question type** — multiple choice, multiple answer, true/false, fill-in-the-blank, short answer, essay, and matching.
- **Rich text editing** — bold, italics, underline, lists, links, tables, and embedded images in prompts and feedback, with WYSIWYG editing that round-trips through QTI.
- **AI review** — per-question feedback against real item-writing guidelines, shown as a before/after diff you can apply field by field.
- **Import & export** — Canvas QTI `.zip` packages in both directions, plus a *plain text* import path for inconsistently formatted sources.
- **Accessibility first** — required image alt text, VoiceOver support, Dynamic Type, full keyboard control, and color that is never the only signal.

## Get started

```sh
git clone https://github.com/ntderosu-code/QuizEditor.git
cd QuizEditor
swift run QuizEditorApp
```

Requires macOS 14+ and a Swift 6 toolchain.

## Why it exists

Canvas quiz authoring and QTI interchange are finicky — formatting gets lost, accessibility is an afterthought, and writing good distractors is hard. Quiz Editor keeps the source of truth local, makes formatting and accessibility first-class, and puts an item-writing reviewer one click away.

---

Released under the [MIT License](https://github.com/ntderosu-code/QuizEditor/blob/main/LICENSE). Built entirely on Apple frameworks; no third-party dependencies.
