# DESIGN.md — Quiz Editor landing page

> The design system for `docs/index.html`. Derived from the shipped page. Register:
> **brand** (the page IS the product here). Pair with `PRODUCT.md`.

## Concept

**A Scantron / OMR examination instrument.** The whole page reads like a bubble
sheet under good light. The answer bubble is the through-line motif: a filled teal
bubble marks "correct," and it recurs as list markers, eyebrows, the hero kicker,
and a footer rhythm strip. Light mode is exam paper under daylight; dark mode is
late-night drafting. Avoid the EdTech category reflexes (navy/teal corporate, white
clinical, stock students); the OMR concept is what keeps it specific.

## Color (OKLCH, committed periwinkle + teal)

Strategy: **committed.** One saturated periwinkle/indigo carries identity; teal is
the second voice (correctness, accents); a marking-pen red is used once or twice.
Every neutral is tinted toward hue 286. Never `#000`/`#fff`.

Tokens (see `:root` and the `prefers-color-scheme: dark` block in the page):

- `--paper` / `--paper-2`: surface (light: ~oklch(0.985 .006 286); dark: ~0.205).
- `--ink` / `--ink-soft`: text and secondary text.
- `--line` / `--line-strong`: hairlines and stronger borders.
- `--indigo` (links/text, AA), `--indigo-fill` (buttons), `--indigo-deep`
  (drenched bands).
- `--teal` / `--teal-deep`: filled bubble, "correct," accents.
- `--pen`: oklch(~0.56 .18 25), the marking pen, sparingly.
- `--on-indigo`: near-white text on indigo surfaces.

Drenched indigo bands (`.band`) carry full sections (standards, get-it). A separate
deliberately-dark band (`.a11y`) holds accessibility in both color schemes.

## Theme

Respects the system color scheme (`prefers-color-scheme`); both modes are
first-class, neither is a default. The scene: an instructor drafting a quiz at a
desk, sometimes in daylight, sometimes late at night.

## Typography

- **Display:** Bricolage Grotesque (700/800), tight tracking (-0.015em),
  `text-wrap: balance`, line-height ~1.04.
- **Body:** San Francisco (the app's own type) via `-apple-system`, ~1.62
  line-height.
- **Mono:** Spline Sans Mono, only for literal formats, labels, code, and chips
  (the `.mono` / `.sample` / `.chip` / `.stamp` contexts).
- Fluid type scale `--step--1` … `--step-4` via `clamp()`. Hierarchy from scale +
  weight contrast, not color. Body measure capped ~40–62ch.

## Layout & spacing

- Centered `.wrap` (max ~1160px) with fluid `--gutter`. Don't container things
  that don't need it.
- Vertical rhythm via `.pad` (`clamp(3rem, 8vw, 6rem)`); vary, don't pad uniformly.
- Feature rows: `.feature` two-column, alternating with `.feature.flip`. Bands and
  spotlights break the rhythm on purpose.
- Margin "timing ticks" (`.ticks`) echo a scantron edge.

## Components

- **Eyebrow** (`.eyebrow`): teal-deep label with a leading filled bubble.
- **Bubble checklist** (`.checklist`): filled-bubble marker + bold lead-in + soft
  detail. The primary "list of specifics" pattern (replaces icon-card grids).
- **Stamps** (`.stamp`): mono chips with a teal dot, on the indigo band (formats).
- **Discipline board** (`.disc-board` / `.chip`): paper-side mono chips grouped by
  family, one `.chip.on` (active) to echo the persona picker. Type-as-imagery in
  place of a screenshot.
- **Marked-text sample** (`.sample`): mono code block with `.k`/`.c`/`.d`/`.cap`
  spans; type as imagery.
- **Buttons**: `.btn-primary` (indigo fill), `.btn-ghost` (outline),
  `.btn-onindigo` (on bands). Lift 2px on hover.
- **Screenshots** (`.shot`): soft radial indigo glow behind app captures.

## Motion

- Progressive reveal (`.reveal` + `IntersectionObserver`), content fully visible
  without JS. Ease-out cubic curves (`cubic-bezier(0.16,1,0.3,1)`), no bounce.
- The hero "correct" bubble fills on load. Never animate layout properties.
- Everything collapses gracefully under `prefers-reduced-motion: reduce`.

## Accessibility (non-negotiable, matches the product)

- WCAG 2.1 AA contrast in both schemes; indigo focus ring, swapped to a light ring
  on dark bands.
- Color is never the only signal (a "correct" bubble has fill + shape + label).
- Semantic landmarks, a skip link, real alt text on app screenshots, decorative
  bubbles `aria-hidden`, and `role="img"` + a text alternative on type-as-imagery
  blocks (the sample and the discipline board).

## Banned here (in addition to the global impeccable bans)

- No gradient text, no side-stripe accent borders, no glassmorphism-by-default, no
  hero-metric template, no identical card grids, no modals.
- No em/en dashes in copy.
- Don't drift to a generic light SaaS look: the OMR bubble motif and the committed
  periwinkle/teal must remain legible as the identity.
