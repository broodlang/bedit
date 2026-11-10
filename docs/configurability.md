# The customization surface (design note)

**Status:** design-of-record, partly built. What exists today (2026-11-04):

- **Stage 1, the settings registry** — brood's `std/settings` (ADR-428). `config.blsp`
  declares every init.blsp key once with `settings/define` (its default, type and doc); the
  check, the fallback (`config/setting`) and the generated default file come from that
  declaration, an unknown key warns, and a package declares its own under
  `:bedit/settings`. nest's own user config is its other caller.
- **Stage 2's keybinding half** — not as a `bind-key` form but as two DATA keys,
  `:keys` (Emacs `global-set-key`) and `:mode-keys` (`define-key` in one mode's map),
  read by std's `key-parse` (brood ADR-535) and compiled by `src/userkeys.blsp`. A
  binding's command is its M-x name; `nil` unbinds. `C-h k` and `C-h w` report them.
  `M-x global-set-key` / `M-x local-set-key` bind a key live for the session into the
  same amendments (`:session-keys` on the model); M-x reload-config keeps them unless
  init.blsp now binds that key itself.
- **Directory-local settings** (Emacs's `.dir-locals.el`): a project's
  `.bedit-locals.blsp`, `(dir-locals :fill-column 100 :indent-width {python 4})`, read as
  data by `src/dirlocals.blsp` for the files under it. Only a setting declared `:safe true`
  is taken; the rest is refused and said. It sits under `.editorconfig` and over init.blsp.
- **Stage 3, named themes** — `:theme` is a setting, themes are a registry
  (`themes/register-theme!`, `M-x theme-select`), and a package may add one.
- **Hooks as data** — `:hooks {:after-save [cmd …] :mode {rust [cmd …]}}`, commands by
  their M-x names (`src/hooks.blsp`): after a save lands, and the first time a buffer is
  current in a mode. Not an `add-hook` of functions: init.blsp defines none.
- **Not built:** an `add-hook` of functions, command properties (`command-put`), a live
  `M-x set-variable`. Nothing in init.blsp can define a function.

`M-x reload-config` re-reads the file and applies every setting, the keys, the theme and
the font without a restart; the problems it finds go to *Messages* and the echo area.

The sections below are the design as it was written before stage 1, kept for its
reasoning; where they name a form (`(setting …)`, `(bind-key …)`, `defsetting`) the built
surface is the one above.

## What init.blsp is today

`~/.config/bedit/init.blsp` is ONE `(config …)` form, read as data — never evaluated, so
it cannot hold a `defn`, a `defdyn` or any other code (`M-x eval-buffer` on it reports
`unbound symbol: config`):

```clojure
(config
  :font "JetBrains Mono"
  :font-size 16
  :theme "Catppuccin Latte (light)"
  :show-whitespace {:default false :prog true}
  :lsp-autostart false
  :keys {"C-c f" project-find-file     ; bind, by M-x name
         "<f5>" compile
         "C-z" nil}                    ; unbind
  :mode-keys {markdown {"C-c C-c" markdown-preview}})
```

The first launch writes the file with every key documented and commented out. Code — a
command of your own — lives in a package: a directory under `~/.config/bedit/packages`
whose `project.blsp` `:enhances bedit` ([`packages.md`](packages.md)), loaded at startup;
or, for the session only, in any buffer with `C-x C-e`.

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

### Keybindings as data — `bind-key` (built as `:keys` / `:mode-keys`)

The keymaps are data, profiles are a registry, dispatch is late-bound — *everything is
in place except a user surface*. Need: an init form `(bind-key "C-c g" 'magit/cmd-git-status)`
plus a live `M-x global-set-key`, folding user binds into a highest-precedence layer on
the model scope.

The **only** missing primitive is an Emacs `kbd`-style **string parser**
(`"C-x C-e"` → `[:ctrl-x :ctrl-e]`). Tellingly, the *label* half already exists
(`keyhelp/ed-key-label`), but in the editor, not in `std/editor/keymap` where its inverse
belongs. Put both `key-describe` / `key-parse` in `std/editor/keymap` — and the
"best-guess chord encoding" caveats littering `keymaps.blsp` (`(keyword "alt-%")`, …)
go away.

### Hooks — `add-hook` / `run-hooks` (built as `:hooks`, commands by name)

`std/layers` already fans events across layers (`run-event`: `:activate` / `:on-focus`
/ `:on-close`). What's missing is the *named, user-extensible* hook — Emacs
`after-save-hook`, `find-file-hook`, `<mode>-hook`. A `*hooks*` registry (name → list
of late-bound `(m) -> m` fn-syms) with `add-hook` / `remove-hook` / `run-hooks`, fired
at the obvious command seams (`cmd-save` → `:after-save`, layer activation →
`<mode>-hook`). This is the single biggest "feels like Emacs configurability" win:
`(add-hook :prog-mode-hook 'my/enable-line-numbers)`.

### Faces + named themes (built: `:theme`, `M-x theme-select`)

`theme.blsp` is a flat file of `def`s — live-redefinable but not *selectable*
(no `(setting :theme :catppuccin-latte)`), and `apply-syntax-theme!` is a hardcoded
list. Move the chrome faces into the same `editor/face` registry the `:syntax/*` faces
already use, so the renderer reads every colour by name from one place and a **theme is
pure data**. Add `register-theme`; `:theme` becomes a setting. Shipping a light theme
becomes a data-only change.

### Command properties — `interactive/declare-trait` (built, in part)

What the core must know of a command it does not name is a TRAIT, declared by symbol beside
the command: `:typing`, `:kill`, `:repeat`, `:completion-auto`, `:guest`. Bonus: a user (or a
package) can mark *their own* command repeatable or a kill command. Still separate lists:
`*prefix-consuming*`, `*command-inverse*`, `input/*view-resume-keys*`,
`input/ed--shift-deactivators`.

### A mode's editability — the `:writable` facet (built)

How a buffer becomes writable is its MODE's answer, not a flag flipped under whatever keys
the mode binds: C-x C-q in Dired once made the listing writable with Dired's keymap still in
force, so `m` marked a file instead of typing an m. C-x C-q (`editing/cmd-toggle-read-only`,
M-x toggle-read-only) asks the buffer's layers for `:writable` (`modes/writable-policy`):

| value | C-x C-q | who |
|---|---|---|
| `:toggle` | flips the flag; the mode's keys stay commands (Emacs's special-mode) | special-mode and the reports over it, the git / mur views, the menus, the rebase plan |
| `{:enter command}` | runs the mode's EDIT VARIANT | Dired → wdired, *Occur* → occur-edit, *Project Search* → wgrep's edit |
| `{:commit c :abort a}` | leaves the variant — at once if unchanged, else asks: y applies, n puts back | wdired, occur-edit, the search edit (`editspans/edit-layer`) |
| `{:never why}` | refuses, saying `why` | the hex, image and document views |

No layer declaring it means `:toggle`, which is right for text and code. **A new mode whose
keymap binds a printable key to a command must declare `:writable`** on that layer (or one
above it) — `tests/writable_test.blsp` walks every registered type and fails otherwise, then
presses C-x C-q in a buffer of each type to check it does what was declared. An edit variant
is a layer built with `editspans/edit-layer layer commit abort`: its C-c C-c / C-x C-s /
C-c C-k / C-c ESC and its `:writable` come from that one call, and its stack may bind no
letter (the test checks that too). The per-type decisions, with the Emacs behaviour each
follows, are the table in `src/modes.blsp`.

A letter bound to a command declared `:typing` (`interactive/declare-trait`) counts as typing,
so the guard allows it: wdired's permission toggles (`:wdired-allow-to-change-permissions true`,
Emacs's `wdired-toggle-bit`) bind `r` `w` `x` `s` `t` `S` `T` `-` and SPC to
`wdired/cmd-wdired-set-bit`, which sets the permission character under point inside a permission
span and inserts the letter anywhere else — a file name still takes every letter. wdired's
other spans: a symlink's target after ` -> ` (`:wdired-allow-to-redirect-links`, on by default,
as Emacs), and the nine permission characters (off by default; `:advanced` makes them free
text). C-c C-c re-points the links and sets the modes before it renames (`file/symlink`
`{:replace true}` and `file/chmod`, brood ADR-697; another machine's through the file handler's
`:make-symbolic-link` / `:set-file-modes`), each change standing alone.

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

- All of this keeps `init.blsp` **declarative data** (ADR-065 holds) — what it says is
  data a registry *interprets* (as `:keys` / `:mode-keys` are), not eval'd code.
  User-authored *function bodies* (a custom command) belong in a local package under
  `~/.config/bedit/packages` (see "What init.blsp is today" above), not inline in
  `init.blsp` — Brood has no `require` form for an init file to call.
- Nothing here needs the actor-model rework (`docs/actor-architecture.md`); these are
  all single-process, pure-model abstractions.
