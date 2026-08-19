# bedit roadmap

A small, Emacs-style GUI text editor written in Brood, on the standard editor
framework (`editor/buffer`, `editor/keymap`, `editor/layers`, `sexp`, `regex`,
`editor/display`, `editor/ui`) plus the editor's own `src/eval-command.blsp` (the
C-x C-e policy, moved out of `std/`). Nothing custom in any kernel — the
editor is *policy* (commands, modes, keymaps) over that framework. The model is a
single `ui-run` loop; modes are **layers** carried by each buffer (see the layers
design-of-record in the brood repo: `docs/layers.md`).

Legend: ✅ done · 🟡 in progress · ⬜ not started

**Strategic direction — competing with Neovim/Emacs/VSCode:** the honest standing
vs the big three and the three tracks that would make someone *choose* bedit over
them are in **`docs/competitive-tracks.md`**. The flagship (Track 1 — remote &
multiplayer editing) is now **largely built** — see §E below and the as-built ledger
in **`docs/remote-multiplayer-plan.md`**; the user-facing runbook is
**`docs/working-from-another-computer.md`**.

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
- ✅ **The rest of Emacs' sexp/list family** — `C-M-n`/`C-M-p` `forward-list` /
  `backward-list` (step over the atom siblings, stop only at whole lists), `C-M-e`
  `end-of-defun`, `up-list` (the forward mirror of `C-M-u`'s `backward-up-list`;
  M-x-only, as in Emacs), the structural kills `C-M-k` / `C-M-DEL`, `C-M-t`
  `transpose-sexps` and `C-M-q` `indent-sexp`. The motions/kills/reindent sit on the
  shared `prog-mode-layer`, so a tree-sitter mode inherits them; the pure primitives
  are in `std/tool/sexp.blsp` (`point-list-forward` / `point-list-backward` /
  `point-up-forward` / `point-defun-end` / `point-transpose`) and mirrored in
  `std/editor/treesit.blsp` — the prime-directive home, next to the five they join.
  `mark-sexp` now marks by the same motion `C-M-f` uses, so it is mode-polymorphic too.
- ✅ **The non-structural Emacs motions** — `M-m` `back-to-indentation`, sentence
  motion `M-a`/`M-e` with `M-k` / `C-x DEL` to kill one, `M-@` `mark-word`, `M-g c`
  `goto-char`, and `M-g n`/`M-g p` `next-error`/`previous-error` (`C-x \`` still works).
  `back-to-indentation` / `forward-sentence` / `backward-sentence` are new
  `std/editor/buffer.blsp` primitives, next to `forward-word`/`forward-paragraph`.
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
- ✅ **`C-M-t` transpose-sexps** — `sexp/point-transpose`, the same pure-edit shape.
  On `brood-keymap` (a CST edit, like the paredit family) rather than the shared prog
  layer. Point inside a form counts as being before it, so the chord mid-symbol swaps
  that symbol with its predecessor, matching Emacs.

## C. Multi-language via tree-sitter (the big architectural piece)

Done — but **simpler than this section first sketched** (ADR-103 in the brood
repo). No editor Rust crate and no opaque tree/node resource: the right design
fell out of the prime directive. Because `tree-sitter-parse` projects the foreign
tree into the *same* positioned-node maps Brood's own reader gives
(`{:kind :start :end :named :kids/:text}`), there was nothing new to host — the
existing `std/tool/sexp` node abstraction and the editor's mode-services already
consume that shape. So the whole feature is one Rust builtin + Brood policy.

- ✅ **tree-sitter parse primitive** — `(tree-sitter-parse source lang)` (Rust,
  feature `treesit`; `crates/lisp/src/treesit.rs`). Parses Ruby/Elixir and projects
  the tree into the positioned-CST node shape (char offsets, `:named` to flag
  anonymous tokens) — **no new `Value` variant, no GC surgery**. Mechanism =
  parse+project; everything above is Brood. (No separate editor crate; no opaque
  resource — see ADR-103 for why eager projection beat a live-tree handle.)
- ✅ **Node-abstraction backend** — `std/editor/treesit.blsp`: generic `fontify`
  (a per-language kind→face table, whole-node colouring, a cross-language
  keyword heuristic) + structural motions (`point-forward/-backward/-up/-down/
  -defun-start`) over the node maps. The editor's `C-M-f/b/u/d/a` commands are now
  mode-polymorphic (dispatch on a `:ts-lang` facet — `commands/ed--structural`), so
  the *same* structural commands run over a tree-sitter tree unchanged.
- ✅ **`ruby-mode` / `elixir-mode`** — `src/modes.blsp`: same layer shape as
  brood-mode, with `:parser :tree-sitter` + a `:ts-lang` facet and a face table;
  `.rb` → ruby-mode, `.ex`/`.exs` → elixir-mode, `:comment-syntax "# "`. Syntax
  colouring + structural nav, all by data registration. Tests in
  `tests/modes_test.blsp`.
- 🟡 **Deferred (same data shape, no policy change needed):** incremental reparse /
  lazy node access (eager whole-(window) projection is fast enough today — ADR-103);
  query-driven call-head / def-name highlighting; `:indent` (RET stays the global
  newline, falling back to previous-line match); more grammars (each is one
  `Cargo.toml` dep + one `language_for` arm + a face table + a layer).
- ⬜ Complements (not replaces) LSP: tree-sitter = fast local syntax/structure;
  `brood-lsp` & others = semantics.

## E. Remote & multiplayer editing — Track 1 (largely BUILT, 2026-07-10/11)

The collaboration payoff of the actor direction shipped as a staged sequence
(each slice a pushed, tested increment — the full as-built ledger with the Brood
seams it forced is `docs/remote-multiplayer-plan.md`; usage is
`docs/working-from-another-computer.md`):

- ✅ **Daemon / emacsclient model** — `bedit --name ed --serve [file]`: sessions per
  client over Brood node links (`std/editor/serve`, ADR-090), the host's own window
  included (`--headless` to opt out), clean detach/teardown.
- ✅ **ONE shared mode** — `--serve --shared` (alias `--collab`): one document,
  everyone their **own** caret/panes/minibuffer. Content is authoritative in a
  buffer process; every file anyone visits is auto-shared (a per-daemon registry).
- ✅ **Presence** — named, coloured remote carets (quiet tags that fade after the
  caret moves), selections tinted per owner, viewport markers, join/leave echoes,
  a modeline chip, `M-x collab-status`. Markers are edit-adjusted **in** the buffer
  process and cleaned up when a participant dies (never a ghost caret).
- ✅ **`share-follow` (C-x f) / `share-mirror`** — ride a participant's caret across
  buffers; mirror also adopts their viewport (the classic one-view pairing). Any
  move of your own takes the wheel back; leaders leaving unfollow.
- ✅ **`M-x share-session` / `share-session-stop`** — a live editor becomes a host
  (no relaunch); stop ends every attached session, the registry, and every shared
  buffer process. Names: `--as NAME` → init.blsp `:share-name` → `$USER` → prompt.
- ✅ **Deltas + exact concurrent merges** — edits travel as based positional splices
  (O(change), the document never ships after the seed); the buffer process and the
  clients transform concurrent splices (std `splice-transform`), so typing in
  different places inside one round-trip merges exactly — no CRDT, no flicker
  (origin-tagged echo suppression), local undo intact. Ambiguous same-span
  collisions resync from the process.
- ✅ **Over the network** — `--listen [HOST:]PORT` adds a cookie-authenticated TCP
  listener beside the always-bound Unix socket (kernel dual-listen, ADR-074);
  `bedit --attach ed@HOST:PORT --as you`. Loopback-verified; cross-machine is the
  same code path (verify from a real second machine — the one untested leg).
- ⬜ **v2: CRDT** — offline / high-latency divergence (`std/text/replica`-shaped).
- ⬜ **Per-participant undo** — "undo *my* edits" semantics once histories interleave.

**Kernel bugs this track surfaced (all fixed upstream):** pid identity across
`node-start` (equality/hash normalize the local stamp — a captured pre-node pid
silently stopped matching); exit signals never reached a natively-nested `receive`
(the immortal-process bug — ADR-132); `%isolate`'s reap could kill its own caller.

### E.2 The actor-model endgame (BUILT, 2026-07-11)

- ✅ **Every buffer hosted as a process** — the live window backs every pool slot
  with a buffer process (`src/hosted.blsp` — `hosted-reconcile`/`hosted-step` at the
  loop tail); the pool value is the local projection cache the pure view renders
  unchanged, so commands stay `model -> model` and headless/test models stay pure.
  The protocol's client half is **std `editor/buffer-client`** (ADR-134) with a
  native `%str-splice-diff` (typing on a hosted 3000-line buffer: 0.94 ms/key).
  A collab-shared buffer = a hosted slot with remote subscribers; `collab` shrank
  to the presence layer.
- ✅ **Point off the buffer** — invariant explicit + test-guarded (pane point
  authoritative while displayed; the pooled `:point` only the Emacs saved default).
- ✅ **Per-buffer fault isolation** — hosted processes are monitored; a died local
  buffer rehosts from the pool cache, a shared one re-shares onto the registry's
  respawn; the registry mirrors every shared document's text (the same std client
  fold) and respawns died buffers from current content.
- ✅ **Services off the loop** — eldoc joins diagnostics on the `std/task` idle
  pattern; every LSP lookup is async (corr-matched, rope-guarded mutations);
  eval/web/logger/bshell/compile were already processes. diff-hl stays sync by
  decision (E0 exonerated the async reply path — the June-16 revert had
  misdiagnosed a stuck `:held-key`). Deferred with recorded triggers: kill-ring
  as a process, persistent fontify workers (see `docs/actor-architecture.md`).
- ✅ **View as aggregator** — definitionally complete: the pool IS the
  latest-projection cache, version-reconciled by `link-fold`.
- **Upstream this track won:** concurrent-safe `require` (a top-of-file `provide`
  let a racing require observe a half-loaded module — found by this track's suite
  churn), `[:io/write]` as a ring-recorded splice delta, `buffer-edit-reply`
  (read-then-decide edits), `std/editor/buffer-client` + `text-apply-splice`,
  native `%str-splice-diff`.

## F. The customization surface (deferred — design note)

- ⬜ **A settings registry + a real config surface** — the editor is internally
  layered and hot-swappable, but the user can configure almost none of it from
  `init.blsp` (a closed 3-key DSL today). The keystone is a `defsetting` registry
  (named/typed/defaulted/documented variables — Emacs `defcustom`), off which the rest
  hang: `(setting …)` in init, `bind-key` + `M-x global-set-key`, `add-hook` / named
  hooks, selectable themes (faces into one registry), and a `command-put`/`command-get`
  property table that folds in the five scattered command-list `def`s. Brood-side gaps:
  a `std/settings` registry, `key-parse`/`key-describe` in `std/editor/keymap` (the
  `kbd` bijection). Decided direction, **not building yet** — full reasoning + the
  prime-directive split + a staged path: **`docs/configurability.md`**. Prerequisite
  for §G.

## G. Packages — an extension ecosystem (deferred — design note)

- ⬜ **Load editor packages, almost like Emacs** — *an editor package is a Brood nest,
  published to **hive*** (Brood's registry, which `nest` already speaks: `:version` deps,
  `nest search`/`publish`, sha256-pinned immutable tarballs into `_deps/`). The user's
  `~/.config/bedit/` is itself a nest whose `:dependencies` are the installed packages;
  ADR-037's resolver + `project.lock.blsp` are the installer, and a lockfile in the config
  dir means a **reproducible editor config** (what Emacs needed straight.el for). A package
  hooks in by calling the same registration functions core uses (`register-type-layers`,
  `bind-key`, `defsetting`, …) — the registries *are* the plugin API. Live, restart-free
  install via the mutable `*load-path*` + late binding.
  Gaps — Brood/hive, and **generic by requirement**: nothing in `brood`/`nest`/`hive` may
  know bedit exists, so the marker is `:enhances {bedit ">= 0.1"}` (Debian's `Enhances:`
  — *not* `:extends`, which reads as OO inheritance, and *not* `:host`, which already means
  a machine here) — a manifest map of *application → version constraint* whose keys are
  author data, carried manifest → `nest publish` → hive → a `?enhances=<app>` search filter,
  with `version/satisfies?` promoted into `std` from the copy hive already hand-rolled (a
  predicate, not a resolver change — ADR-037's exact-version invariant stands) and the
  constraint checked by **the enhanced application** at load time.
  A Hatch plugin or a `nest` plugin then works with no new code. Also: a runtime
  **`load-nest`**; package-rooted
  namespaces (ADR-070 — the one real language investment, gating *third-party* packages;
  its prelude/heap groundwork landed 2026-08-02). Editor-side: config-dir-as-nest startup
  loader, a `*Packages*` buffer (`M-x package-list`, dired-style single keys, `C-h P`),
  `M-x package-install` through plume, all of it off the loop on `procstream`, `autoload`,
  and a `use-package`-style `(package …)` form — **data, never eval'd**, so user code lives
  in a local `:path` package. Decided direction, **not building yet** — full design +
  staged path: **`docs/packages.md`**.

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

## H. Brood (upstream) — gaps the editor needs

Prime-directive items: capabilities the editor wants that belong in **Brood** (`../brood`),
not hacked in here. Recorded as suggestions; implement upstream.

- ⬜ **Line-level breakpoints — a source-position-addressed break**. Today the gutter
  breaks at the **function boundary** only (`break-fn`, ADR-184: rebind the whole
  function), so `brood-gutter-click` resolves any click up to the enclosing `(defn …)`.
  Breaking on an *arbitrary line* needs a break addressed by `file:line:col`, which
  Brood can't express: `spy`/node instrumentation (`std/prelude` `spy--walk`) addresses
  nodes by s-expression **shape**, not source position, and while the reader knows
  positions (`source-location` per def, error `pos` per form) that info isn't threaded
  onto every sub-form. **The gap:** give forms retained source spans (a reader change +
  a `(form-location form)` accessor), then a `break-at` that parks when evaluation
  reaches the node at a span — reusing the existing `stepping-sink` node machinery.
  Editor side (small, once the primitive lands): map the clicked gutter line to its
  enclosing sub-form's span and register the break through the same `:run-breaks` →
  `C-c r` path project breakpoints already use. Pays off beyond debugging (precise
  error highlighting, structural nav). A pragmatic no-kernel version — spy-wrap the
  body and gate the park on a structural sub-form match — is possible but heuristic
  (identical sub-forms misfire; whole-fn spy is slow), so the real fix is the span
  primitive. Scoped 2026-07-30.
- ⬜ **Module cache for fast startup** (the big one). Cold start is **~680ms of module
  load** — Brood re-reads, parses, macro-expands and evals the *entire* editor + `std`
  source on every launch (there's no compiled-module cache). Measured 2026-06-16, ruling
  out the likely suspects:
  - **Not eval/alloc speed**: a pre- vs post-ADR-112/mimalloc binary evals 2000 `defn`s
    identically (5ms) and loads a std graph identically (61ms). The 2026-06-15 brood perf
    commits did **not** regress startup.
  - **Not a few heavy modules**: lsp / web / magit / bshell cost **~0ms incrementally**
    once the core is loaded (they only *look* heavy cold because they pull the shared
    core). Lazy-loading them buys nothing — the cost is the mandatory core graph
    (model + commands + view + input + their `std` deps).

  An **editor-side mitigation shipped 2026-07-05** (`a1647d8`: async deferred loading —
  ~1.1s → ~0.4s *perceived* startup), but the module-load cost itself is untouched; the
  real fix is a **Brood loader feature**, in increasing payoff/effort:
  1. a **compiled-form cache** (`.pyc`/`.elc`-style): cache each module's macro-expanded /
     bytecode form keyed by source hash; skip parse+macroexpand when the source is unchanged
     (editor source rarely changes between launches → near-100% hit rate);
  2. embed `std` **precompiled** in `nest` (it's embedded as *source* today, re-parsed each run);
  3. an **image snapshot** / portable dump (restore the fully-loaded image — fastest, hardest).
- ⬜ **Faster `std/diff`** (general, low priority). Stock `std/diff` is an O(n²) LCS table,
  documented "a few hundred items". The editor's diff-hl no longer needs it — it shells out
  to `git diff --no-index` (matching Emacs `diff-hl`) — but a Myers O(n·d) `std/diff` would
  help any other consumer.

(Other upstream gaps are noted inline above: narrow-to-region needs a `std/editor/buffer`
restriction (§D); `stat`/`file-info` + a `std/time` formatter for richer dired (§D); regex
ranges and `layers` extras (§D).)

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
    lower-case letters), so `M-O` open-line-above is M-x-only for now — and the same
    caveat applies to **`C-x F` (share-mirror)**: if the capital never arrives it's
    `M-x share-mirror` until verified/rebound on a live window.
- Bindings live in `src/modes.blsp`; commands in `src/commands.blsp` (the
  `defcommand` macro + M-x registry in `src/interactive.blsp`); dispatch + minibuffer
  in `src/input.blsp`; model in `src/model.blsp`; pane geometry + mouse in
  `src/panes.blsp`; view in `src/view.blsp`. Completion: `src/complete.blsp`
  (in-buffer) and `src/mincomplete.blsp` (minibuffer prompts).
