# myedit roadmap

A small, Emacs-style GUI text editor written in Brood, on the standard editor
framework (`std/buffer`, `std/keymap`, `std/layers`, `std/sexp`, `std/regex`,
`std/eval-command`, `std/display`, `std/ui`). Nothing custom in any kernel — the
editor is *policy* (commands, modes, keymaps) over that framework. The model is a
single `ui-run` loop; modes are **layers** carried by each buffer (see the layers
design-of-record in the brood repo: `docs/layers.md`).

Legend: ✅ done · 🟡 in progress · ⬜ not started

---

## ✅ Done — the current editor

- ✅ **Core loop & view** — `ui-run` (model/view/update); a mode line (buffer name,
  active mode, line:col, buffer count), an echo area / minibuffer, region drawn
  reverse-video, scrolling that keeps point on screen.
- ✅ **Modes as layers** — `text-mode` is the default (`:fundamental`); `brood-mode`
  triggers on a **regex** `:file-pattern` (`\.blsp$`) and stacks on text-mode. The
  active mode shows in the mode line. New modes are pure data — a layer + a
  `register-type-layers` / regex `register-file-type`.
- ✅ **Movement** — char/word/line/buffer (`C-f/b/n/p`, `M-f/b`, `C-a/e`, `M-</>`,
  arrows/Home/End), screenful scroll (`C-v`/`M-v`, PageUp/Down).
- ✅ **Editing** — self-insert, `Enter`, delete (`Backspace`/`C-d`/`Delete`),
  open-line (`C-o`/`M-o`/`M-O`), kill-line (`C-k`), kill-word (`M-d`/`M-DEL`),
  transpose (`C-t`), case (`M-u`/`M-l`/`M-c`), duplicate (`C-x d`), join (`M-^`).
- ✅ **Kill ring (Emacs semantics)** — `C-w`/`M-w`/`C-y`; consecutive kills
  coalesce; `M-y` yank-pop cycles/wraps; bounded (`ed-kill-ring-max` = 60). Built
  on `last-command`/`this-command` tracking in the dispatch loop.
- ✅ **Undo / redo** (`C-/`, `C-x u`, `M-/`), **region / mark** (`C-SPC`).
- ✅ **Multiple buffers** — `C-x b` switch (live candidate completion), `C-x C-f`
  find-file, `C-x →/←` cycle, `C-x k` kill; a persistent `*Messages*` buffer.
- ✅ **Minibuffer** — a real editable field (`C-f/b/a/e`, arrows, `Backspace`/
  `C-d`, `C-k`, insert at point, `Tab` complete, `Enter`/`C-g`).
- ✅ **Completion-at-point** — `Tab` popup; buffer words by default, **live global
  symbols in brood-mode** (the `:complete-at` mode service).
- ✅ **Evaluate Brood in the buffer** — `C-x C-e` (last sexp), region, whole buffer
  (`std/eval-command`); result + captured output to the echo area / `*Messages*`.
- ✅ **Structural navigation (brood-mode)** — `C-M-f/b/u/d/a` over the parse-source
  CST (`std/sexp`).
- ✅ **Syntax highlighting (brood-mode)** — live lexical colouring via the
  `:fontify` mode service over `std/highlight`; spans lexed once per frame, region
  `:reverse` merged into the lexer face.
- ✅ **Bracket matching + eldoc (brood-mode)** — the `:bracket-match` service marks
  the pair at point; the `:eldoc` service shows the enclosing call's signature in
  the echo area as point moves (both reuse `std/highlight`).
- ✅ **Generic mode-services host** — the view/completion ask the buffer's mode for
  `:fontify` / `:bracket-match` / `:eldoc` / `:complete-at` facets
  (`ed-mode-service`) without naming any language; brood-mode is the first to
  supply them. A `json`/`ruby`/`elixir` mode is the same registration (see §C).
- ✅ **Files** — `C-x C-s` save, `C-x C-c` / `Esc` quit.

---

## A. Round out the everyday Emacs feel (next)

- ⬜ **Incremental search** — `C-s` / `C-r` isearch (the biggest missing daily
  feature); then `M-%` **query-replace**.
- ✅ **`M-x` run-command-by-name** — `defcommand` marks a function interactive and
  registers it (`src/command.blsp`); `M-x` (`M-x`/`:alt-x`) completes against and
  runs the registry. Every `cmd-*` is interactive; reachable without a binding.
- ⬜ **Comment / uncomment** — `M-;`, per-mode comment syntax (`;;` for brood,
  `#`/`//` for others) as a mode facet.
- ✅ **Indentation** — `TAB` indents-or-completes (Emacs `tab-always-indent` =
  `'complete`), `C-M-i` always completes; in brood-mode `RET` is newline-and-indent.
  Sexp-aware via the `:indent` mode service over `std/sexp` (body forms +2, calls
  align under the first arg, vectors/maps under the first element); buffers with no
  `:indent` fall back to matching the previous line.
- ✅ **Projects — find-file-in-project** (`C-x p f`) — `src/projects.blsp` finds the
  root (nearest ancestor holding a `*project-markers*` entry — `project.blsp` or
  `.git`, so any repo opens as a project) and walks it for files (recursive,
  skipping `.git`/`target`/…); a minibuffer completes over the root-relative paths.
  The current project shows on the mode line. (Follow-ups under the `C-x p` prefix:
  project-wide grep, a multi-project switcher.)
- ⬜ **Prefix args & mark ring** — numeric `C-u N`; `C-u C-SPC` to pop the mark.
- ⬜ **find-file live candidates** — switch-buffer has them; give find-file the
  same (directory listing as you type).
- ⬜ **Bind `cmd-kill-whole-line`** (defined, currently unbound).

## B. Structural editing for brood-mode

- ⬜ **paredit-style** slurp / barf / raise / splice / wrap, and a sexp-aware
  `C-k` — tree edits over the CST re-serialised (the node API already exists).

## C. Multi-language via tree-sitter (the big architectural piece)

- ⬜ **An editor Rust crate** that embeds the Brood runtime and adds host
  primitives (the embedder-extends-the-runtime hook).
- ⬜ **tree-sitter primitives** — an opaque tree/node resource: parse, node-at,
  parent/children/siblings, type, range, incremental reparse. Mechanism in Rust;
  policy in Brood.
- ⬜ **Node-abstraction backend** so the existing `std/sexp` structural commands
  work over tree-sitter trees unchanged (`{:kind :start :end :kids}` shape).
- ⬜ **`ruby-mode` / `elixir-mode`** — same layer shape as brood-mode, with a
  `:parser :tree-sitter` + `:grammar` facet instead of `:brood`.
- ⬜ Complements (not replaces) LSP: tree-sitter = fast local syntax/structure;
  `brood-lsp` & others = semantics.

## D. Polish & deferred

- ✅ **Syntax highlighting** — lexical colouring in brood-mode via the `:fontify`
  mode service over `std/highlight` (see the core list above). CST-/tree-sitter-query
  driven highlighting for other languages comes with §C.
- ⬜ **Windows / splits** — one window, many buffers today.
- ⬜ **Browsable `*Kill Ring*`** view and a **which-key**-style popup for prefixes.
- ⬜ **regex** ranges `[a-z]` / captures / `{m,n}` (`std/regex`, brood repo).
- ⬜ **layers** extras (brood repo): `:commands` manifest, per-binding `when`-guards,
  cross-layer chord merging, a browsable command list.
- ⬜ **dired / file browser**, registers, bookmarks, rectangles, macros — the long
  Emacs tail, as needed.

---

## Loose ends / caveats

- **Key encodings are best-guesses.** The `C-M-*`, `M-o`/`M-O`, `M-^`, `M-DEL`
  bindings pass tests by binding *name*, but the real keywords `gui-poll` delivers
  haven't been confirmed on a live window — verify on a run and rebind in
  `src/modes.blsp` (`text-keymap`) if they differ. Bindings are data, rebindable
  live via `C-x C-e` on a `keymap-bind`.
- Bindings live in `src/modes.blsp`; commands in `src/commands.blsp`; dispatch +
  minibuffer in `src/input.blsp`; model in `src/model.blsp`; view in `src/view.blsp`.
- A stray `somefile.blsp` is untracked at the project root (delete if junk).
