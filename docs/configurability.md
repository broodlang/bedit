# The customization surface (design note, deferred)

**Status:** design-of-record for a direction we've decided on but are **not building
yet**. Captured so the reasoning isn't lost. Nothing here is implemented; the editor
today exposes only the closed 3-key `init.blsp` DSL described under "Where we are."

The question that started this: *the editor is internally layered and hot-swappable —
so why can the user configure almost none of it from their init file?* This note is
the answer: the one abstraction (a settings registry) that the rest hang off, and how
each user-facing surface (variables, keybindings, hooks, themes, command properties)
becomes a thin front door onto a registry the editor **already has internally**.

It pairs with [`packages.md`](packages.md): packages register through these same
registries — they *are* the extension API — so this note is the prerequisite for a
real package ecosystem.

## Where we are today, and why it's good

The editor is already far more layered than its surface suggests. The strong seams:

- **`std/editor/layers`** — modes are layers; keybinding **profiles** (emacs/vim) are
  layers on the *model* scope; dispatch composes both, late-bound by symbol, so
  everything hot-swaps on the next keystroke.
- **Mode-service facets** (`model/ed-mode-service`) — `:fontify` / `:eldoc` /
  `:indent` / `:diagnostics` / `:bracket-match` / `:gutter-*` / `:on-click` /
  `:comment-syntax`. A new language is pure data registration.
- **Data registries everywhere** — transient overlays (`input/ed--transient-handlers`),
  async events (`input/ed--event-handlers`), profiles (`keymaps/*profiles*`), buffer
  file-types (`layers/*auto-type-by-file*`), log routes (`model/*log-routes*`), and
  *two* per-command property registries (`interactive/*prefix-consuming*`,
  `interactive/*command-inverse*`).

So the **internal** extensibility is excellent. Every colour is a live-redefinable
`def` in `theme.blsp`; every keybinding is data; every command resolves late. A power
user with `C-x C-e` can already re-skin and rebind a running editor.

## The gap: the config *surface* is a closed 3-key DSL

`config.blsp` reads `~/.config/bedit/init.blsp` as **data** (not eval'd —
ADR-065, and correct), but understands exactly three keys: `:fullscreen`, `:hl-line`,
`:cursor`. There is **no general abstraction** for variables, user keybindings, hooks,
or theme selection. The tell: adding the `:hl-line` setting touched **four**
hand-maintained places —

1. `config/apply-to-model` (the apply branch),
2. `config/*init-default-source*` (the generated default file's documented stanza),
3. `config/config-warnings` (validation), and
4. `config/*cursor-values*` (the accepted-value list).

That 4-place coupling for one boolean is the smell that says an abstraction is
missing. Everything tunable in the editor either lives behind that closed DSL or isn't
reachable from init at all.

## The keystone: a settings registry (`defsetting`)

**One abstraction unlocks the rest:** a registry where every tunable has a named,
typed, documented, defaulted home — the runtime-customization analogue of Emacs
`defcustom`.

```clojure
(defsetting :hl-line
  :default true
  :type    :bool                       ; keyword-literal type (Brood ADR-105)
  :scope   :model                       ; applied onto the ui-run model
  :apply   (fn (m v) (assoc m :hl-line v))
  :doc     "Highlight the current line full-width (Emacs hl-line).")
```

A setting is just a map `{:name :default :type :doc :apply :scope}`. The registry then
gives, *for free*:

- **Validation** — `config-warnings` becomes a fold over the registry's `:type`s;
  delete `*fullscreen-values*` / `*cursor-values*`.
- **The default init file** — `*init-default-source*` is *generated* from each
  setting's `:doc` + `:default`, never hand-maintained again.
- **`apply-to-model`** — a fold over `:model`-scoped settings; adding a setting is
  **one `defsetting`**, not four edits.
- **A generic `(setting :key v)` form** in `init.blsp` that sets **any** registered
  setting — the DSL stops being closed.
- **`M-x set-variable` / `M-x customize-variable`**, live, listing/reading/writing the
  registry.
- A home for the scattered constants (`model/*scroll-margin*`, `commands/*fill-column*`,
  `model/*blink-ms*`, `commands/ed-tab-width`, …) — still `C-x C-e`-redefinable, but now
  also init-settable and documented.

This is the piece every other surface below registers through.

## The other surfaces (each a thin front door)

### Keybindings as data — `bind-key`

The keymaps are data, profiles are a registry, dispatch is late-bound — *everything is
in place except a user surface*. Need: an init form `(bind-key "C-c g" 'magit/cmd-git-status)`
plus a live `M-x global-set-key`, folding user binds into a highest-precedence layer on
the model scope.

The **only** missing primitive is an Emacs `kbd`-style **string parser**
(`"C-c C-e"` → `[:ctrl-x :ctrl-e]`). Tellingly, the *label* half already exists
(`model/ed-key-label`), but in the editor, not in `std/editor/keymap` where its inverse
belongs. Put both `key-describe` / `key-parse` in `std/editor/keymap` — and the
"best-guess chord encoding" caveats littering `keymaps.blsp` (`(keyword "alt-%")`, …)
go away.

### Hooks — `add-hook` / `run-hooks`

`std/layers` already fans events across layers (`run-event`: `:activate` / `:on-focus`
/ `:on-close`). What's missing is the *named, user-extensible* hook — Emacs
`after-save-hook`, `find-file-hook`, `<mode>-hook`. A `*hooks*` registry (name → list
of late-bound `(m) -> m` fn-syms) with `add-hook` / `remove-hook` / `run-hooks`, fired
at the obvious command seams (`cmd-save` → `:after-save`, layer activation →
`<mode>-hook`). This is the single biggest "feels like Emacs configurability" win:
`(add-hook :prog-mode-hook 'my/enable-line-numbers)`.

### Faces + named themes

`theme.blsp` is a flat file of `def`s — live-redefinable but not *selectable*
(no `(setting :theme :catppuccin-latte)`), and `apply-syntax-theme!` is a hardcoded
list. Move the chrome faces into the same `editor/face` registry the `:syntax/*` faces
already use, so the renderer reads every colour by name from one place and a **theme is
pure data**. Add `register-theme`; `:theme` becomes a setting. Shipping a light theme
becomes a data-only change.

### Command properties — generalize the two registries into one

The editor already invented per-command property registries *twice*
(`*prefix-consuming*`, `*command-inverse*`) — but then *also* hand-maintains
`input/*repeat-commands*`, `input/*view-resume-keys*`, `input/ed--shift-deactivators`,
`model/*typing-commands*`, and `commands/ed--kill-commands` as separate global lists.
These are all "properties of a command." Generalize to **`command-put` / `command-get`**
(declared next to each command, exactly as the inverse/prefix registries already are)
and fold the five lists in. Bonus: a user (or a package) can then mark *their own*
command repeatable / a kill command / shift-deactivating.

## Prime-directive split (what's Brood vs. what's the editor)

**Part 1 — Brood / `std`.**
- A general **settings registry** (`std/settings.blsp` or folded into an existing
  module): named, typed, defaulted, documented, observable variables. Not
  editor-specific — the build tool's `~/.config/brood/config.blsp`, the REPL, and any
  Brood app with a config file want the same thing. Leans on the keyword-literal type
  work (ADR-105) for `:type` validation.
- **`key-parse` / `key-describe`** in `std/editor/keymap` — the `kbd` string ↔ key-vector
  bijection (the label half is currently mislocated in the editor).
- Optionally, generalize `std/layers`' `run-event` fan-out into a **named-hook
  registry** (name key instead of layer scope).

**Part 2 — the editor.**
- `config.blsp` rewritten as a fold over the settings registry (kills the 4-place
  coupling); a generic `(setting …)` init form.
- A user-keybinding layer + `bind-key` / `M-x global-set-key`.
- Named hooks fired at command seams; `add-hook`.
- Chrome faces into `editor/face`; `register-theme`; `:theme` as a setting.
- `command-put` / `command-get`; the five scattered lists folded in.

## A staged path

In dependency order — each stage stands alone and is independently shippable:

1. **`defsetting` + the registry** (the keystone). Rewrite `config.blsp` as a fold;
   migrate the existing three keys + a few scattered constants. Immediately deletes the
   worst coupling in the codebase.
2. **`bind-key` + `add-hook`** (in parallel; both depend on 1 for the `(setting …)`/init
   plumbing). Needs `key-parse` in Brood.
3. **Faces/themes** — registry + `register-theme` + `:theme` setting.
4. **Command properties** — `command-put`/`command-get`; fold in the five lists.

## When to actually do this

Sooner than the actor model — this is pure-model work that lands today with no
language rewrite, and it's the **prerequisite for packages** (a package configures the
editor through exactly these surfaces). Start with the settings registry the moment we
want `init.blsp` to do more than three things; the rest follow as the package ambition
(see [`packages.md`](packages.md)) makes them load-bearing.

Two notes worth keeping:

- All of this keeps `init.blsp` **declarative data** (ADR-065 holds) — `(setting …)` /
  `(bind-key …)` / `(add-hook …)` are data forms a registry *interprets*, not eval'd
  code. User-authored *function bodies* (a custom command) belong in a small local
  module the config nest `(require)`s, not inline in `init.blsp`.
- Nothing here needs the actor-model rework (`docs/actor-architecture.md`); these are
  all single-process, pure-model abstractions.
