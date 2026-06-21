# Quiz Editor

**A native macOS app for authoring, reviewing, and round-tripping quizzes in open standards — QTI and IMS Common Cartridge.**

Write questions with rich text and images, get AI-assisted item-writing feedback, and import/export **QTI** (1.2 and 2.1) and **Common Cartridge** packages that work with Canvas, Brightspace, Blackboard, Moodle, and other learning management systems — accessible from the first keystroke.

[View on GitHub](https://github.com/ntderosu-code/QuizEditor){: .btn }

![Quiz Editor main window](screenshots/editor.png)

---

## What it does

- **Author every common question type** — multiple choice, multiple answer, true/false, fill-in-the-blank, short answer, essay, and matching.
- **Rich text editing** — bold, italics, underline, lists, links, tables, and embedded images in prompts and feedback, with WYSIWYG editing that round-trips through QTI.
- **Organize & tag** — per-question tags, difficulty, and points; sidebar search, filtering, drag-to-reorder, duplicate, and a quick-switch palette.
- **AI review & authoring** — feedback against real item-writing guidelines as an applyable before/after diff, plus AI generation of questions, distractors, and feedback. An **offline linter** also flags common item-writing problems instantly.
- **Import & export** — **QTI** `.zip` and **IMS Common Cartridge** (`.imscc`) packages in both directions — including whole quizzes and item banks — with a question picker, a *plain text* import path for messy sources, a validated QTI export, and a print-ready paper exam.
- **Accessibility first** — required image alt text, VoiceOver support, Dynamic Type, full keyboard control, and color that is never the only signal.

## Get started

```sh
git clone https://github.com/ntderosu-code/QuizEditor.git
cd QuizEditor
swift run QuizEditorApp
```

Requires macOS 14+ and a Swift 6 toolchain.

## AI review with a before/after diff

![AI Review sheet showing a before/after diff with per-field apply](screenshots/ai-review.png)

## Import marked plain text

![Import Marked Text dialog](screenshots/import.png)

## Why it exists

Quiz authoring and QTI/Common Cartridge interchange across learning management systems are finicky — formatting gets lost, accessibility is an afterthought, and writing good distractors is hard. Quiz Editor keeps the source of truth local, makes formatting and accessibility first-class, validates what it exports, and puts an item-writing reviewer one click away.

---

Released under the [MIT License](https://github.com/ntderosu-code/QuizEditor/blob/main/LICENSE) © 2026 Byron R Roush. Built entirely on Apple frameworks; no third-party dependencies.
