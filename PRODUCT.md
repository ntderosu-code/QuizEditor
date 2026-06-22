# PRODUCT.md — Quiz Editor

> Brand and product context for design work. The design surface is the public
> landing page (`docs/index.html`, served via GitHub Pages). Pair with `DESIGN.md`.

register: brand

## Product purpose

Quiz Editor is a free, private macOS app for writing rich, accessible quizzes and
moving them in and out of any learning platform through the open **QTI** and
**Common Cartridge** formats. It adds an offline item-writing reviewer, optional
AI assistance (on-device, your own API, or copy/paste), **discipline personas**
that tune the checks and AI to a field, competency-framework mapping, and
print/document export. Nothing the user writes leaves their Mac.

## Users

Instructors, instructional designers, and assessment writers, many of them not
programmers. They care about good test items, accessibility, and not being locked
into one LMS. They are wary of cloud tools that harvest their work. Some are
power users (item banks, QTI internals); many just want to write a good quiz and
get it into Canvas.

## Brand & tone

- **Calm, plain, and concrete.** Talk like a thoughtful colleague, not a sales
  deck. Lead with what the person can do, then why it helps.
- **Quietly confident, never breathless.** No "revolutionary," no "supercharge,"
  no exclamation marks. The work speaks.
- **Trust through specifics.** "An image can't leave the app until it has alt
  text" beats "accessibility-first." Name the real behavior.
- **Teacher-respecting.** Assume intelligence and limited time. Explain a format
  or standard in one clause, never condescend.
- **Privacy is identity, not a feature bullet.** "Nothing you write ever leaves
  your Mac" is the throughline; restate it where it naturally lands.

## Voice rules

- Second person ("you," "your quiz"). Active voice.
- **No em dashes and no en dashes in copy.** Use commas, colons, semicolons,
  periods, or parentheses. (The `--` in CSS custom properties is fine.)
- Series and rhythm via commas; occasional colon to set up a list of specifics.
- Every word earns its place. No heading restated as the first sentence, no intro
  that repeats the title.
- Prefer the smallest true claim. Hedge only when the truth requires it.
- Numbers spelled out in prose where it reads better ("Twenty-one built in").

## Anti-references (what we are not)

- **SaaS landing pages.** No hero-metric template (big number + gradient), no
  identical three-up icon-card grids, no "trusted by" logo wall, no gradient text.
- **Enterprise EdTech.** No stock photos of smiling students, no navy-and-teal
  corporate gloss, no jargon ("synergize learning outcomes").
- **Crypto/AI-startup maximalism.** No neon-on-black, no glassmorphism by default,
  no animated gradient blobs as the whole personality.
- **Walled-garden tools.** We are the opposite of lock-in; never imply it.

## Strategic principles

1. **Open formats over features.** The durable promise is that a quiz written
   today still opens cleanly if the school switches platforms. Lead with it.
2. **Local and private by construction.** Every claim must hold with Wi-Fi off.
3. **Accessibility is the floor.** Ship it accessible the first time; say so with
   concrete behaviors, not a badge.
4. **Advisory, never coercive.** The reviewer, AI, and personas suggest; they
   never block the author or alter an export's correctness.
5. **User-editable everything.** Personas and frameworks are starting points the
   user can fork, edit, and share, not a cage.

## Proof points to draw on

- Reads/writes QTI 1.2, QTI 2.1, `.imscc`; round-trip checked before export.
- Works with Canvas, Brightspace, Blackboard, Moodle, D2L, and any QTI/CC system.
- Offline reviewer + AI across three backends (Apple on-device, OpenAI-compatible,
  copy/paste).
- 21 discipline personas across five families; fully editable and shareable.
- macOS 14+, signed and notarized, MIT licensed, built only on Apple frameworks.
