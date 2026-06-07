# myedit roadmap

A small, Emacs-style GUI text editor written in Brood, on the standard editor
framework (`editor/buffer`, `editor/keymap`, `editor/layers`, `sexp`, `regex`,
`editor/display`, `editor/ui`) plus the editor's own `src/eval-command.blsp` (the
C-x C-e policy, moved out of `std/`). Nothing custom in any kernel — the
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
  (`src/eval-command.blsp`); result + captured output to the echo area / `*Messages*`.
  Eval runs **off the loop via `task`** (`(require 'task)`) so a long/looping
  form never freezes the loop; `C-g` (`cancel-task`) interrupts a running eval, and
  an optional `*eval-timeout-ms*` arms the task's built-in timeout to auto-kill a
  runaway one.
- ✅ **Structural navigation (brood-mode)** — `C-M-f/b/u/d/a` over the parse-source
  CST (`sexp`).
- ✅ **Syntax highlighting (brood-mode)** — live lexical colouring via the
  `:fontify` mode service over `editor/highlight`; spans lexed once per frame, region
  `:reverse` merged into the lexer face.
- ✅ **Bracket matching + eldoc (brood-mode)** — the `:bracket-match` service marks
  the pair at point; the `:eldoc` service shows the enclosing call's signature in
  the echo area as point moves (both reuse `editor/highlight`).
- ✅ **Generic mode-services host** — the view/completion ask the buffer's mode for
  `:fontify` / `:bracket-match` / `:eldoc` / `:complete-at` facets
  (`ed-mode-service`) without naming any language; brood-mode is the first to
  supply them. A `json`/`ruby`/`elixir` mode is the same registration (see §C).
- ✅ **Windows / splits** — tiled panes over a `editor/pane` layout tree: `C-x 2/3`
  split, `C-x o` other, `C-x 0/1` close; each pane has independent scroll/zoom and
  shares buffer text via the pool. **Mouse**: click selects a pane, divider drag
  resizes, Ctrl+wheel zooms / plain wheel scrolls the pane *under the pointer*.
  Per-pane line-number gutter (`C-x l`).
- ✅ **Live diagnostics (brood-mode)** — the advisory type-checker runs off the
  render path (recomputed only when buffer text changes), underlining flagged
  tokens, a `⚠N` count on the mode line, and the message on the echo row at point.
- ✅ **Files** — `C-x C-s` save, `C-x C-c` / `Esc` quit.

---

## A. Round out the everyday Emacs feel (next)

- ✅ **Incremental search** — `C-s` / `C-r` isearch + `M-%` **query-replace**
  (`src/isearch.blsp`): modal mini-loops beside the keymap, matches highlighted via
  point+mark over the region face, wrap-around, the search origin pushed to the mark
  ring on exit. Built on `editor/buffer` `buffer-search-forward`/`-backward` (over
  `string-index-of`/`string-last-index-of` in the prelude). Regex isearch waits on the
  `regex` gaps (§D).
- ✅ **`M-x` run-command-by-name** — `defcommand` marks a function interactive and
  registers it (`src/interactive.blsp`); `M-x` (`M-x`/`:alt-x`) completes against and
  runs the registry. Every `cmd-*` is interactive; reachable without a binding.
- ✅ **Comment / uncomment** — `M-;` (`cmd-comment-dwim`): toggles the region's lines
  (or the current line) — uncomments when every non-blank line is already commented,
  else comments. The token is a `:comment-syntax` mode facet (brood-mode → `";; "`);
  a mode without one reports it can't comment. (`#`/`//` modes are the same facet.)
- ✅ **Indentation** — `TAB` indents-or-completes (Emacs `tab-always-indent` =
  `'complete`), `C-M-i` always completes; in brood-mode `RET` is newline-and-indent.
  Sexp-aware via the `:indent` mode service over `sexp` (body forms +2, calls
  align under the first arg, vectors/maps under the first element); buffers with no
  `:indent` fall back to matching the previous line.
- ✅ **Projects — find-file-in-project** (`C-x p f`) — `src/projects.blsp` finds the
  root (nearest ancestor holding a `*project-markers*` entry — `project.blsp` or
  `.git`, so any repo opens as a project) and walks it for files (recursive,
  skipping `.git`/`target`/…); a minibuffer completes over the root-relative paths.
  The current project shows on the mode line. (Follow-ups under the `C-x p` prefix:
  project-wide grep, a multi-project switcher.)
- ✅ **Prefix args & mark ring** — numeric `C-u N` (default 4; further `C-u` ×4,
  digits set it) repeats the next command N times (the common-case mechanism;
  per-command interactive specs are a deferred `editor/layers` improvement); `C-u C-SPC`
  pops the mark. `C-SPC` now `push-mark`s, filling a per-buffer mark ring
  (`editor/buffer` `push-mark`/`pop-mark`).
- ✅ **find-file live candidates** — `C-x C-f` shows the directory's entries as you
  type (the same `view/ed-mb-candidates` path `C-x b` uses), via a shared
  `mincomplete/ed--dir-matches`.
- ✅ **Bind `cmd-kill-whole-line`** — `C-S-backspace` (best-guess encoding; rebindable).

## B. Structural editing for brood-mode

- ✅ **paredit-style** slurp / barf / raise / splice / wrap, and a sexp-aware
  `C-k` — tree edits over the CST re-serialised (the node API already exists). The
  edits are **pure `(text point) -> [text point]` functions in `std/tool/sexp.blsp`**
  (the prime-directive home — next to the navigation they mirror, reusable by any CST
  backend), applied via a whole-buffer splice (one undo unit). brood-mode binds them:
  `C-)`/`C-}` slurp/barf forward, `C-(`/`C-{` backward, `M-r` raise, `M-(` wrap,
  `C-M-s` splice (`M-s` is the search prefix), and `C-k` rebinds to the sexp-aware kill
  (won't break parens). All M-x-reachable (`slurp-forward`, …). Shifted-Ctrl chord
  encodings are best-guesses to confirm on a live GUI — see "Loose ends".

## C. Multi-language via tree-sitter (the big architectural piece)

- ⬜ **An editor Rust crate** that embeds the Brood runtime and adds host
  primitives (the embedder-extends-the-runtime hook).
- ⬜ **tree-sitter primitives** — an opaque tree/node resource: parse, node-at,
  parent/children/siblings, type, range, incremental reparse. Mechanism in Rust;
  policy in Brood.
- ⬜ **Node-abstraction backend** so the existing `sexp` structural commands
  work over tree-sitter trees unchanged (`{:kind :start :end :kids}` shape).
- ⬜ **`ruby-mode` / `elixir-mode`** — same layer shape as brood-mode, with a
  `:parser :tree-sitter` + `:grammar` facet instead of `:brood`.
- ⬜ Complements (not replaces) LSP: tree-sitter = fast local syntax/structure;
  `brood-lsp` & others = semantics.

## E. The actor-model editor (deferred — design note)

- ⬜ **Buffers (and services) as processes**, with **push-projection rendering** — the
  loop becomes a view aggregator over buffer processes that publish versioned
  viewport projections; point/scroll move to the pane, text+markers to the buffer
  process; kill-ring / fontify / LSP become supervised services. Unlocks concurrency,
  supervision/restart, and near-free collaboration (a buffer process on another node).
  Decided direction, **not building yet** — the single-process pure model serves us
  well today. Full reasoning, decomposition, hard-parts-and-answers, and a staged
  (non-big-bang) path: **`docs/actor-architecture.md`**.

## A.2 Emacs-parity round 2 (done)

A batch of everyday Emacs commands + discoverability, all on existing primitives
(no kernel changes; `src/*.blsp` is runtime-loaded):

- ✅ **More editing commands** — upcase/downcase **region** (`C-x C-u`/`C-x C-l`),
  `just-one-space` (`M-SPC`) / `delete-horizontal-space` (`M-\`), `transpose-words`
  (`M-t`) / `transpose-lines` (`C-x C-t`), `zap-to-char` (`M-z`), `fill-paragraph`
  (`M-q`, `*fill-column*` = 70; `ed-fill-text` is a candidate to promote to std).
- ✅ **Files / buffers** — `write-file` (`C-x C-w`), `revert-buffer`, read-only toggle
  (`C-x C-q`), `goto-line` (`M-g g`), **recentf** browser (`C-x C-r`) over the
  persisted `~/.cache/brood/recent-files.blsp` cache (find-file also floats last-used
  entries to the top of a directory listing).
- ✅ **which-key** — a live bordered panel of a pending prefix's continuations
  (`view/ed-which-key-ops` over the keymap data + shared `model/ed-key-label` /
  `ed-cmd-label`).
- ✅ **Help** — `describe-key` (`C-h k`, resolves a key sequence through the keymap and
  shows the command + docstring) and `describe-function` (`C-h f`, completes the M-x
  registry); docstrings via the `doc` primitive (`model/ed-doc`).
- ✅ **Registers** (`C-x r SPC`/`j`/`s`/`i`) and **persistent bookmarks** (`C-x r m`/`b`,
  in `~/.cache/brood/bookmarks.blsp`) — both on a reusable one-key reader
  (`model/ed-read-char` + a read-char transient).
- ✅ **Keyboard macros** (`C-x (` / `C-x )` / `C-x e`) — `ed-update` captures raw keys
  while recording and replays by re-feeding them.
- ✅ **occur** (`M-s o`) — matching lines in a read-only `*Occur*` buffer (occur-mode,
  like the process list); `RET` jumps to the source line. `M-s` is now the search
  prefix: `M-s s` is the fuzzy line search (was `M-s`), `M-s o` is occur.
- ✅ **Undo boundary on a typing pause** — a settled idle tick arms a one-shot
  `:undo-break` (Emacs `undo-boundary`), so `undo` after a pause removes just the last
  run, not the whole burst.

## D. Polish & deferred

- ✅ **Syntax highlighting** — lexical colouring in brood-mode via the `:fontify`
  mode service over `editor/highlight` (see the core list above). CST-/tree-sitter-query
  driven highlighting for other languages comes with §C. Plus **markdown-mode**,
  **env-mode** (`.env`), and **docker-mode** (`Dockerfile`) — fontify-only layers over
  `std/editor/{markdown,dotenv,dockerfile}`.
- ⬜ **Browsable `*Kill Ring*`** view. (which-key ✅ — see §A.2.)
- ⬜ **regex** ranges `[a-z]` / captures / `{m,n}` (`regex`, brood repo).
- ⬜ **layers** extras (brood repo): `:commands` manifest, per-binding `when`-guards,
  cross-layer chord merging, a browsable command list.
- ⬜ **Rectangles** (`C-x r r`/`k`/`y`/`t`) — column-based region kill/yank/insert.
  Pure editor work on `editor/buffer` (multi-line column slicing); not yet started.
- ⬜ **narrow-to-region / widen** (`C-x n n`/`w`) — **needs a Brood `std/editor/buffer`
  change** (a narrowing restriction the buffer ops + the view respect), so it's the one
  true language-gap item in the Emacs tail (the prime directive). Not yet started.
- ✅ **dired / file browser** (`C-x C-d`, `M-x dired`) — a read-only directory listing
  (`src/commands.blsp` `ed-show-dired`, mode `:dired` in `src/modes.blsp`), same
  generated-buffer pattern as occur/process-list. Single-key UX: `RET`/`f` visit-or-enter,
  `^` parent, `g` refresh, `q` quit, `+` mkdir, `R` rename, `C` copy, `D` delete (y/n
  confirm). Entry under point recovered by line-index into the model's `:dired-names` (no
  column re-parsing). Built on the kernel fs primitives — including a new **`copy-file`**
  builtin added to Brood (the one gap; binary-safe `std::fs::copy`, prime directive).
  Listing shows type + size + name; **richer `ls -l` columns (perms / owner / date) await
  a Brood `stat`/`file-info` builtin + a `std/time` epoch→calendar formatter** — the next
  language additions that would upgrade dired (deferred, not built).
- ✅ registers, bookmarks, keyboard macros, occur — see §A.2.

---

## Loose ends / caveats

- **Key encodings are best-guesses.** The `C-M-*`, `M-o`/`M-O`, `M-^`, `M-DEL`
  bindings pass tests by binding *name*, but the real keywords `gui-poll` delivers
  haven't all been confirmed on a live window — verify on a run and rebind in
  `src/modes.blsp` (`text-keymap`) if they differ. Bindings are data, rebindable
  live via `C-x C-e` on a `keymap-bind`.
  - ✅ **Shifted-punctuation chords now reach the GUI** (`M-<`/`M->`, `M-{`/`M-}`,
    `M-%`, `M-^`): the GUI frontend was stripping Shift from Alt/Ctrl chords
    (`key_without_modifiers`), so `Alt+Shift+.` arrived as `:alt-.` not `:alt->`.
    Fixed in Brood (`crates/lisp/src/gui.rs` `translate_key`/`shift_char`, 2026-06-02),
    matching the crossterm frontend — no editor binding change. Still unverified: the
    capital-letter chords (`M-O` vs `M-o`) collapse to one keyword (both frontends
    lower-case letters), so `M-O` open-line-above is M-x-only for now.
- Bindings live in `src/modes.blsp`; commands in `src/commands.blsp` (the
  `defcommand` macro + M-x registry in `src/interactive.blsp`); dispatch + minibuffer
  in `src/input.blsp`; model in `src/model.blsp`; pane geometry + mouse in
  `src/panes.blsp`; view in `src/view.blsp`. Completion: `src/complete.blsp`
  (in-buffer) and `src/mincomplete.blsp` (minibuffer prompts).
