# Plan: a first-class UI for the editor — `std/editor/ui-kit`

Status: draft (2026-07-30). A baseline **widget kit** so the editor's chrome stops being
hand-rolled per feature, and so **both the GUI and the terminal are first-class**, not one
polished and one an afterthought.

This follows the repo's two-part rule (CLAUDE.md): **Part 1** is what we add to *Brood*
(`../brood/std/editor`) — the prime directive — and **Part 2** is the editor work built on
it. The kit lives in Brood; bedit becomes thin usage.

---

## 1. Goal & non-goals

**Goal.** One composable widget/layout/style layer, in Brood, over the display-op
vocabulary we already paint. Every overlay (context menu, completion popup, Plume,
which-key, tooltips, status bar) becomes a *config of shared widgets* instead of a bespoke
renderer paired with a bespoke hit-test.

**Non-goals.** No GPU-retained UI framework in the frontend. No moving widget logic into
`gui.rs`. No proportional/pixel layout for chrome. No animation-forward "modern" feel we
can't make rock-solid.

## 2. The feel we're aiming for: **Emacs-solid**

The north star for *feel* is Emacs, not Zed. Emacs is world-class at **both** tty and GUI
and has been for 40 years, and its feel is **deterministic, instant, predictable,
consistent** — a synchronous redisplay that never janks. Zed (GPUI) is prettier in stills
but feels *off* in the hand: GPU-retained trees bring frame-pacing/input-latency
inconsistencies, animations that read as lag, and focus/state edge cases. We deliberately
**do not follow Zed's architecture or its feel.**

Our `ui-run` loop + synchronous data-op frame is already Emacs-shaped. Lean into it: the
kit's job is to make chrome *predictable and identical across backends*, with quiet
refinement (surfaces + hairlines — see `docs/ui-chrome.md`), never flash.

## 3. What we take from each reference

| Reference | Take | Reject |
|---|---|---|
| **Emacs** | the *substrate* (faces/roles that **degrade per backend**; decoration as data) **and** the *feel* (solid, instant, consistent). Also the *warning*: Emacs never built a composable widget layer, so every package re-rolls popup geometry — our exact duplication, unsolved for decades. | its clunky `widget.el` / bolted-on native menus |
| **Helix** | the *component structure*: a component renders itself into an `area` **and** owns its events (a compositor stack). | terminal-only renderer |
| **Ratatui** | the *layout algebra*: constraint splits (`len`/`fill`/`min`/`max`/`pct`). | manual mouse handling |
| **egui** | *render and hit-test are one pass* — a widget returns its click targets. This is our `zone`. | pixel/GPU immediate mode |
| **Zed / GPUI** | at most the *idea* that style+layout should be declarative data. | the architecture (in-frontend, GPU-retained) **and** the feel |

## 4. Where we already are (five seams, in embryo)

We are much closer than it feels — the kit *consolidates* what exists, it doesn't invent:

1. **Two painters, one op vocabulary.** `crates/lisp/src/gui.rs` (GPU) and
   `builtins/terminal.rs` (crossterm) both paint a frame that is *a Brood vector of render
   ops* (`term-draw` / the GUI frame). `terminal.rs` says it outright: "a remote frontend
   can implement the identical op vocabulary." **The dual-backend boundary is already
   shipping.**
2. **The op set** (`std/editor/display.blsp`): `clear` `text` `rect` `frect` `cursor`
   `card-surface` `card-pill` `tooltip` `zone` `zone-at` `zone-cursor-ops`. `frect` /
   `card-*` already **lower by a `gui?` flag** (sub-cell rounded in GUI, flat cells in tty)
   — the exact "one style, two renderings" move, in miniature.
3. **`zone` = fused hit-test-as-data.** `(zone [col row w h] id cursor)` → `{:rect :id
   :cursor}`; `zone-at` returns the hit zone; `zone-cursor-ops` turns the *same* zones into
   pointer-shape ops. This is egui's `Response`, already here.
4. **The `Overlay` ability (ADR-183)** = the behavior seam (a component's key handling):
   `menu-overlay`, `isearch-overlay`, … already encapsulate "how this transient handles
   keys."
5. **Style roles + elevation** (`src/theme.blsp` + `docs/ui-chrome.md`): a role ladder
   (`*base*`/`*surface0*`/`*surface1*`/`*overlay*`), "reference by role, never raw colour",
   "surfaces + hairlines, never shadows." **The style leg's philosophy is already written
   and Emacs-solid.**

**The gap** is only the *middle*: no widget that emits ops **and** zones from one pass, no
layout algebra, no style struct tying roles to widgets. So five+ modules hand-roll "a
floating card of rows" (`completion`, `complete-at-point`, `plume`, the context menu,
`statusbar`, `apprun` chips), each recomputing clamp/pad/border, each pairing a renderer
with a *separate* hit-test that can drift (the bug I hand-patched building the dropdown).

## 5. Part 1 — Brood: `std/editor/ui-kit`

Three added legs over the existing ops, plus a small component set. Illustrative Brood
(design sketch, not yet wired):

### Leg A — style: semantic roles, one struct, dual lowering (the Emacs-faces lesson)

```lisp
;; A style is DATA: roles (not colours) + border/pad/align. The SAME style renders on
;; both backends — the panel/pill primitives lower it per :gui?. Roles resolve against the
;; theme's elevation ladder (theme.blsp / docs/ui-chrome.md).
(defrecord ui-style (fg bg border radius pad align bold))
;; fg/bg    role keys: :surface :on-surface :muted :selection :on-selection :border
;; border   nil | :hairline           (a *surface1* line; NO shadow — dark-UI chrome)
;; radius   cells (GUI only); pad  n | [t r b l]; align :left|:right|:center

(defn ui-color (theme role) (get (:roles theme) role))

(defn ui-face (theme style)                 ; -> a {:fg :bg :bold} face for `text`/`rect`
  (merge
    (if (:fg style)   {:fg (ui-color theme (:fg style))} {})
    (if (:bg style)   {:bg (ui-color theme (:bg style))} {})
    (if (:bold style) {:bold true} {})))
```

### Leg B — layout: Ratatui-style constraint splits over cell rects

```lisp
;; A rect is [col row w h] (same order as `zone`). Constraints size a child along the
;; container axis: [:len n] fixed · [:fill w] weighted share of the leftover ·
;; [:min n]/[:max n] bounds · [:pct p]. Cell-quantised: TUI-true, GUI insets within.
(defn split (area axis constraints) …)      ; -> vector of child rects (the solver)
(defn column (area gap children) …)          ; vertical stack, `gap` rows between
(defn row    (area gap children) …)          ; side by side
(defn ui-pad (area pad) …)                    ; shrink a rect by its padding
```

### Leg C — the widget contract: render + zones in ONE pass (Helix + egui)

```lisp
;; widget :: (area ctx) -> {:ops [...] :zones [...] :cursor <op|nil>}
;;   area = [col row w h]           ctx  = {:theme … :gui? bool :focus <id>}
;; The zones a widget returns ARE its click targets AND its pointer-shape source
;; (zone-cursor-ops). Render and hit-test cannot drift — there is no second function.
```

The **panel** (floating card) and the **list** (the one widget behind the menu, the
completion popup, Plume, which-key):

```lisp
(defn ui-panel (area ctx style body)
  "A raised card: card-surface (rounded frect + hairline in GUI, flat panel in tty — it
already lowers by :gui?), then `body` inside the padded inner area. Surfaces + hairlines,
no shadow."
  (let (inner (ui-pad area (:pad style))
        [c r w h] area
        surface (card-surface r c w h (ui-face (:theme ctx) style) (:gui? ctx)
                  {:border (ui-color (:theme ctx) :border) :radius (:radius style)})
        body-res (body inner ctx))
    {:ops (append surface (:ops body-res)) :zones (:zones body-res)}))

(defn ui-list (spec)
  "A vertical selectable list. spec: :items :selected :row (item i sel?)->{:label :key
:enabled|:sep} :tag :style. Returns a widget fn. Each row emits its paint AND its click
zone in the same step — the hit-test IS the zone list."
  (fn (area ctx)
    (let ([col row w h] area  theme (:theme ctx)  gui? (:gui? ctx))
      (ui-fold-rows                                 ; -> {:ops … :zones …} merged
        (fn (i item)
          (let (r ((:row spec) item i (= i (:selected spec))))
            (if (:sep r)
              {:ops [(text (+ row i) (+ col 1) (string-repeat "─" w) (ui-face theme {:fg :muted}))]
               :zones []}                            ; a divider: paint, no zone
              (let (sel? (= i (:selected spec)))
                {:ops   (ui-row-ops (+ row i) col w r sel? gui? theme (:style spec))
                 :zones [(zone [col (+ row i) w 1] [(:tag spec) i]
                           (if (:enabled r) :pointer nil))]}))))
        (range (count (:items spec)))))))
```

Component set on top: `ui-panel`, `ui-list`, `ui-menu` (panel+list preset), `ui-field`
(line editor), `ui-tooltip`, `ui-table`, `ui-segments` (status bar).

## 6. Part 2 — bedit: migration

The context menu — which I just rebuilt by hand — becomes one `ui-list` in a `ui-panel`.
**`ed-menu-ops` geometry and `ed-menu-hit` both disappear**; the zones are the hit-test:

```lisp
;; src/view.blsp
(defn ed-menu-widget (m)
  (let (menu (:menu m))
    (ui-panel (context-menu-area menu) (ui-ctx m)
      (ui-style {:fg :on-surface :bg :surface :border :hairline :pad 1 :radius 0.5})
      (ui-list {:items (:items menu) :selected (:sel menu) :tag :menu-run
                :row (fn (it i sel?) {:label (:label it) :key (:key it)
                                      :enabled (:enabled it) :sep (:sep it)})
                :style (ui-style {:fg :on-surface :bg :surface})}))))

;; src/input.blsp — ONE generic click dispatch for every widget's zones
(defn ed-widget-click (m zones col row)
  (let (hit (zone-at zones col row))                 ; the zone, or nil
    (if (nil? hit) m
      (let ([tag i] (:id hit))
        (case tag
          :menu-run      (ed-menu-activate m i)
          :complete-pick (ed-complete-pick m i)
          :plume-pick    (ed-plume-pick m i)
          m)))))
```

As each overlay moves onto the kit, delete its bespoke renderer **and** its separate
hit-tester. Net: less code, and the render/hit-test-drift bug class is gone by
construction.

## 7. Phasing

- **Phase 0 — proof (the context menu).** Build `ui-style`/`ui-face`, `ui-pad`, `ui-panel`,
  `ui-list` + `ui-fold-rows` in `std/editor/ui-kit`. Rewrite the context menu against them.
  Done = it paints on **both** `gui.rs` and `terminal.rs`, `ed-menu-hit` is gone, and the
  existing menu tests pass (now asserting on the widget's `:ops`/`:zones`).
- **Phase 1 — fold the popups.** Move completion popup, Plume, which-key onto `ui-list`.
  Delete `completion--menu-ops-*` duplicates + their hit-tests.
- **Phase 2 — status bar & tooltips.** `ui-segments` (`row` + zones) and `ui-tooltip`.
- **Phase 3 — layout algebra hardening.** Generalize `panes.blsp` split geometry onto
  `split`/`row`/`column` so no feature computes a clamp by hand.
- **Phase 4 — TUI hardening (make the terminal genuinely first-class).** Audit every op's
  terminal lowering (a `frect`/`card-pill` must read well as cells), theme-role → tty
  attr/color mapping, mouse + pointer-shape parity. Ship a documented `--tui` path.
- **Phase 5 (optional) — quiet GUI refinement.** A *few* new cosmetic paint primitives in
  `gui.rs` (subtle hairline AA, smooth caret) as ops the tty ignores. Bounded frontend
  growth, never widget logic — and only where it makes the feel *more* solid, not flashier.

## 8. Testing strategy

The kit stays a **pure `data → {ops, zones}`** function, so it keeps the existing
discipline: assert on ops/zones with no window (the flat path). A widget's click test is
`zone-at` over its own `:zones` — the same data the frontend uses — so tests exercise the
real hit-test, not a parallel one. This is why the drift bug can't come back.

## 9. Risks & open questions

- **Per-frame widget trees & perf.** Building `{ops,zones}` every frame must stay cheap
  (chrome is small; the buffer body is the hot path and is untouched). Measure; if needed,
  memoize a widget's result by its props (fine-grained reactivity is the escape hatch, à la
  Floem — but only if measured).
- **Role taxonomy.** Settle the semantic role set (`:surface`/`:on-surface`/`:muted`/
  `:selection`/`:on-selection`/`:border`/`:accent`/…) as the theme's public contract; map
  the existing `*surface0*`/`*overlay*` ladder onto it. One ADR.
- **How much sub-cell.** The line where GUI refinement stops and "faithful to the cell
  grid" holds, so tty never feels second-class. `docs/ui-chrome.md` is the guide.
- **Behavior/render seam.** Keep keys on `Overlay` and mouse on zones, or unify a component
  into one record carrying both (Helix's `Component`)? Lean unify *after* Phase 1 proves
  the render side.

## 10. ADRs to write

1. **The `ui-kit` widget contract** (`(area ctx) -> {:ops :zones}`; zones are the
   hit-test) — in Brood.
2. **Semantic style roles** as the theme's public token contract (formalises
   `docs/ui-chrome.md`).
3. **The layout constraint algebra** (`split`/`row`/`column`).

## 11. Success criteria

- The five hand-rolled "floating card of rows" collapse into **one** `ui-list`.
- **Zero** overlays with a render function *and* a separate hit-test function.
- Every widget paints correctly on **both** `gui.rs` and `terminal.rs` from one definition.
- The terminal build is a first-class target with documented parity — not test scaffolding.
- Net **fewer** lines than today, and the feel stays Emacs-solid on both backends.
