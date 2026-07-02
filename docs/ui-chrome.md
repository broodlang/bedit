# UI chrome: borders, surfaces, elevation

How the editor's *chrome* (the non-text furniture — status bar, pane seams, popups,
scrollbar) is drawn, and the rules for adding more. The goal is a **native, modern**
feel: crisp, quiet, consistent — not a terminal-in-a-window look (box-drawing glyphs,
reverse-video, heavy frames).

This is a **dark** UI rendered on a **cell grid** with **sub-cell** primitives
(`frect`/`vspans`, GUI only) available on top. Those two facts drive everything below.

## The core principle: surfaces + hairlines, never shadows

In dark themes a drop shadow is nearly invisible (dark-on-dark), so depth/elevation is
carried instead by **two cues used together**:

1. **Surface steps** — a raised element sits on a slightly *lighter* background than
   what's behind it.
2. **Hairline borders** — a ~1px line separates or frames the element.

This is the settled dark-mode consensus across Atlassian, Fluent, Material, and the
token-based systems (Radix/Primer/Tailwind): *replace shadows with a lighter surface +
a hairline* ([Atlassian Elevation](https://atlassian.design/foundations/elevation),
[Fluent 2 Elevation](https://fluent2.microsoft.design/elevation),
[designsystems.surf](https://designsystems.surf/articles/depth-with-purpose-how-elevation-adds-realism-and-hierarchy)).
We do **not** use shadows.

## Tokens (src/theme.blsp)

Reference chrome by **role**, never by raw colour, so a re-theme is one edit
([Tailwind theme tokens](https://tailwindcss.com/docs/theme)).

**Surfaces** (each step ~one shade lighter — the elevation ladder):

| token       | hex       | role                                             |
|-------------|-----------|--------------------------------------------------|
| `*base*`    | `#1e1e2e` | editor background (level 0)                      |
| `*surface0*`| `#313244` | raised chrome: status bar, popup cards (level 1) |
| `*surface1*`| `#45475a` | **borders** + the current-line band              |
| `*overlay0*`| `#6c7086` | dim furniture: line numbers, scrollbar track     |
| `*overlay1*`| `#7f849c` | scrollbar thumb                                  |

**Border** — one token, `face-border` = `{:bg *surface1*}`. `*surface1*` is our
"step-6" divider colour (the level most token systems reserve for borders — Radix uses
its step 6 for dividers; [Radix + Tailwind](https://blog.soards.me/posts/radix-colors-with-tailwind/)).
A finer hierarchy, if ever needed, is: **subtle** `*surface0*` · **default** `*surface1*`
(what we use) · **strong** `*overlay0*`. Don't invent per-component border colours.

## Rules

1. **Borders are hairlines.** `*hairline*` = `0.05` cell (a crisp sub-px rule), drawn as a
   thin `frect` in `face-border`. Never a full-cell solid block, never box-drawing glyphs
   (`│ ─ ┌ ┐`), never reverse-video. Keep it thin — a hairline reads as an edge, a fat one
   reads as a block.

2. **Anchor chrome to content with a border, not a gap.** A bar floating with no
   separator reads as "hanging". The **status bar** is framed by a **top *and* bottom**
   hairline — a distinct band ruled off from the buffer above and the echo area below
   (VS Code likewise borders the status bar off from the editor,
   [VS Code theme colors](https://code.visualstudio.com/api/references/theme-color)).
   Rules sit **flush on the row's edges**, never over the text, so the label keeps its
   full height. **Pane seams** are a hairline divider. **Popups** are a raised surface
   (rounded).

3. **Chrome is a distinct surface.** Status bar and popups fill `*surface0*` (one step up
   from `*base*`); the hairline is the crisp edge on top of that step.

4. **Floating things are rounded.** Popup cards + the selection pill use a rounded
   `frect` (macOS/modern-dropdown feel), radius ~0.35–0.5 cell. Flat, grid-aligned
   surfaces (status bar, dividers) are not rounded.

5. **Frontend-aware, GUI-first.** The real app runs the GUI backend, so it uses sub-cell
   `frect` for hairlines and rounded cards. The terminal (and pure tests) can't do
   sub-cell, so they fall back to a cell-quantised `rect`. Gate on the model's **`:gui`**
   flag (set in `main`; absent under `ed-init`, so tests stay frontend-agnostic).

6. **One system, applied uniformly.** Same border token, same hairline thickness, same
   corner radius everywhere. Consistency is what makes it read as "designed".

## Where each rule lives

| element        | code                              | GUI                          | terminal / tests |
|----------------|-----------------------------------|------------------------------|------------------|
| pane divider   | `view/ed-divider-ops`             | centred hairline `frect`     | solid `rect` bar |
| status bar     | `view/ed-pane-modeline` → `statusbar/statusbar-layout` | `surface0` fill + segments + top/bottom rules | `surface0` fill + segments |
| segment hover  | `statusbar/sb--hover-block`       | bordered inset `frect` block (surface1 fill + surface2 rim, Emacs `mouse-face`) | solid highlight band |
| completion card| `completion/completion-menu-ops` → `display/card-surface`+`card-pill` | rounded `frect` + pill | flat `rect` card |
| tooltip        | `statusbar/statusbar-tooltip-ops` → `display/tooltip` | rounded bordered card | flat bordered card |
| scrollbar      | `view/ed-scrollbar-ops`           | rounded `frect` pill         | (none)           |

## The status bar is a segment model (extensible chrome)

The status bar is not a hand-built string — it's a list of **segments** (`statusbar/seg`:
`{:id :text :face :on-click :tooltip}`) that `statusbar-layout` renders into ops **and**
interaction **zones** in one pass. The same layout feeds both the renderer and the mouse
hit-test (`view/ed-modeline-segment-at`), so a segment is clickable/hoverable exactly where
its glyphs are drawn — the discipline the completion card already uses. Layers extend the bar
two ways: a per-buffer mode adds a segment through its `:modeline` service; global chrome
(the git branch + working-tree indicator) is cached on the model (`:git-segments`, built off
the idle beat by `git/git-statusbar-segments`) and rendered for the selected pane.

**Interaction zones** (`display/zone` + `zone-at`) are the model-side dual of `cursor-zone`:
a plain `{:rect :id :cursor}` the *model* hit-tests on pointer-move / click (so it can react —
hover highlight, tooltip, run a command), where `cursor-zone` only asks the *frontend* for a
pointer shape. A hovered interactive segment gets a **bordered, inset block** behind it
(`sb--hover-block`) — Emacs `mouse-face` with a crisp edge: a `surface1` fill ringed by a
`surface2` hairline, floated within the bar with vertical margin + horizontal padding (the
terminal falls back to a flat bg band). A click runs the segment's late-bound `:on-click`.

**Floating cards + tooltips** share one surface primitive — `display/card-surface` (a rounded
`frect` in the GUI, flat `rect` in the terminal, with an optional rounded hairline **border**
done as a border-coloured `frect` *behind* the surface — never a shadow) + `card-pill` +
`tooltip`. The completion popup, context menu, and the segment tooltip all elevate through it,
so they read as one system. These live in `std/editor/display.blsp` as pure Brood over the
existing op vocabulary (`frect`/`rect`/`text`/`cursor-zone`) — **no new frontend/kernel op**:
capability is added as composable std abstractions, not by growing the GUI surface.

## Adding new chrome

Reach for an existing token + the hairline/surface pattern before adding anything. A new
floating panel = a `surface0` (rounded, in the GUI) card with `face-border` hairlines and
`frect`/`rect` gated on `:gui`. If you're about to type a box-drawing glyph or a
reverse-video face, stop — that's the terminal look we're moving away from.
