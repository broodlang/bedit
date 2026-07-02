# Dev log — brood-edit

A skimmable record of work, **newest first**. One entry per feature: what shipped, *why*,
the key files, the tests, and the commit. Use it to recover the *why* without reading every
diff; the commit (`git show <sha>`) has the full change. In-editor, `C-x g` + `TAB` and
`C-x v =` review the diffs directly.

Language-level changes live in the Brood repo's `docs/devlog.md` + `docs/decisions.md`
(ADRs) — e.g. the native `string-split` builtin this work depends on is **ADR-109** there.

---

## 2026-06-15

### design notes: the customization surface + a package ecosystem — (uncommitted)
- **Why:** the editor is internally layered and hot-swappable, but the user can
  configure almost none of it from `init.blsp`, and there's no way to load third-party
  extensions. Captured the design-of-record for both before building, so the reasoning
  isn't lost (the `docs/actor-architecture.md` pattern).
- **What:** two design notes.
  - **`docs/configurability.md`** — a `defsetting` settings registry as the keystone
    (kills the 4-place coupling adding one config key costs today), off which `bind-key`,
    `add-hook` / named hooks, selectable themes, and a `command-put`/`command-get`
    property table all hang. Prime-directive split: Brood gets a `std/settings` registry
    + `key-parse`/`key-describe` in `std/editor/keymap`; the editor rewrites `config.blsp`
    as a fold + adds the user-facing forms.
  - **`docs/packages.md`** — *an editor package is a Brood nest*; the user's
    `~/.config/brood-edit/` is itself a nest whose `:dependencies` are the installed
    packages, and **Brood's existing package manager** (ADR-037) is the package system. A
    package registers through the same functions core uses. Live, restart-free install via
    the runtime-mutable `*load-path*` + late binding. The one real language gap is ADR-070
    package-rooted namespaces (gates third-party packages); a runtime `load-nest` is the
    small one.
- **Files:** `docs/configurability.md` (new), `docs/packages.md` (new), `ROADMAP.md`
  (§F customization surface, §G packages). **Tests:** none — design notes, nothing built.
- **Next:** start with the settings registry (§F.1) — pure-model, lands today, and is the
  prerequisite for packages (§G).

## 2026-06-14

### view: region selection fills blank / short lines through end-of-line — `0b21cc0`
- **Why:** selecting across blank lines only tinted the text, not the empty lines or the
  ragged end-of-line gap — the opposite of the hl-line band, which covers the whole line.
- **What:** `ed--region-eol-bands` — the full-width counterpart to `ed--hl-line-band`. For
  each visible line whose terminating newline falls inside the region it paints a
  `face-region` `rect` from end-of-text to the pane's right edge, so blank lines and the
  end-of-line gap show the selection (Emacs behaviour). The char-range tint still paints the
  text; the band only fills past it (no overlap), and scales with font zoom like the hl-line
  band. **No language gap** — pure view geometry on existing primitives.
- **Files:** `src/view.blsp` (`ed--region-eol-bands`, wired into `ed-pane-ops`).
  **Tests:** +1 in `tests/view_scroll_test.blsp`.

### gutter: reserve a minimum line-number width so the text doesn't jump — `27dad3e`
- **Why:** the gutter was sized from the buffer's current line-count digit count, so crossing
  99→100 / 999→1000 lines widened it a column and shifted all the text right mid-edit.
- **What:** `line-number-min-digits` (4) — `line-number-width` reserves `max(actual, min)`
  digit columns, so files up to 9999 lines keep a stable gutter (Emacs
  `display-line-numbers-width`); it still grows beyond that. **No language gap** — pure
  editor geometry.
- **Files:** `src/modes.blsp` (`line-number-min-digits`, `line-number-width`).
  **Tests:** updated the hardcoded 2-col gutter expectations in
  `tests/panes_projects_test.blsp` (+ mouse click columns) and `tests/web_logging_test.blsp`.

### git: syntax-highlight the diff / log / status buffers — `3951530`
- **Why:** make the diff page (and status/log) readable at a glance.
- **What:** a `:fontify` per git mode — diff lines coloured by prefix (green `+`, red `-`,
  blue `@@` hunks, dim file headers/metadata); the classifier trims indent so it serves both
  raw `*git-diff*` and the inline diff in `*git-status*`. Status section headers bold-blue;
  log commit hashes coloured. Split the shared report layer into `:git-diff`/`:git-log` so
  each gets its own fontify.
- **Files:** `src/magit.blsp` (fontify), `src/modes.blsp` (`:fontify` + layer split).
  **Tests:** +4 in `tests/magit_test.blsp`.

### magit: TAB expands a file's diff inline; click / RET visits the file — `0b76e4a`
- **Why:** review changes without leaving the status buffer, and open files by clicking.
- **What:** in `*git-status*`, `TAB` toggles the file's diff inline below its row
  (`:git-expanded` set, diffs fetched once per open path); `RET` and a mouse click open the
  file. Click is wired through a new generic `:on-click` mode service the mouse handler runs
  after a left-press — so any mode can opt into click-to-act and `panes`/`input` stay free
  of magit specifics. `d` still opens the diff in `*git-diff*`.
- **Files:** `src/magit.blsp` (cmd-git-expand/visit, inline render), `src/modes.blsp`
  (`:on-click`, TAB/RET binds), `src/input.blsp` (`ed--mouse-on-click`). **Tests:** +2 in
  `tests/magit_test.blsp` (inline-expand render).

### git: view changes — `C-x v =` diffs current file; whole-tree diff from status — `5b6d23a`
- **Why:** see a file's changes vs HEAD from any buffer, and the whole tree from status.
- **What:** `cmd-vc-diff` (Emacs `vc-diff`) shows the current file's diff in `*git-diff*`;
  in `*git-status*`, `RET`/`d` on a section header shows the whole working tree vs HEAD.
- **Files:** `src/magit.blsp`, `src/keymaps.blsp` (`C-x v =`), `src/modes.blsp`.

### git integration: diff-hl change gutter + magit-style status — `b99a266`
- **Why:** see per-line changes inline (diff-hl) and drive git without leaving the editor.
- **What:** diff-hl paints a per-line change bar (green/yellow/red) in the line-number
  gutter vs HEAD, cached on the buffer, refreshed on open/save (no per-keystroke cost). The
  gutter cell can now be *chunked* so it carries the bar + the dim number. `C-x g` opens a
  read-only `*git-status*` (dired pattern: a `:git-status` mode, per-row file on the model)
  with stage/unstage/discard/commit/refresh/quit/log/push/pull.
- **Files:** `src/gitdiff.blsp` (new), `src/magit.blsp` (new), `src/view.blsp` (chunked
  gutter), `src/modes.blsp`, `src/commands.blsp` (`ed-annotate-git`), `src/input.blsp`,
  `src/keymaps.blsp`. **Tests:** +15 (`tests/gitdiff_test.blsp`, `tests/magit_test.blsp`).
- **Depends on:** Brood `std/diff` (`diff-lines`) and the native `string-split` (ADR-109).

### LSP navigation: goto-definition, references, hover, rename, format — `77ac9aa`
- **Why:** the standard "LSP goodies" for any server-backed buffer.
- **What:** `M-.` goto-definition (cross-file, jump-marker stack), `M-,` pop-back, `M-?`
  find-references, `C-c C-d` hover, `C-c C-r` rename (applies the WorkspaceEdit across every
  file), `C-c C-f` format. Generalised the LSP client to one `lsp--issue` transition +
  `lsp--shape` (route-by-kind dispatch).
- **Files:** `src/lsp.blsp`, `src/commands.blsp`, `src/keymaps.blsp`. **Tests:** +15 in
  `tests/lsp_test.blsp`. Caught a real bug: JSON object keys parse to keywords, so a
  rename's `:changes` URIs arrive as `:file:///…` — coerced back with `name`.

### imenu: `M-g i` jumps to a symbol via LSP documentSymbol, with live preview — `5f80045`
- **Why:** jump within a file by symbol; preview as you move, restore on cancel.
- **What:** `M-g i` lists the buffer's symbols (qualified names) in a Vertico minibuffer;
  moving the selection previews (point tracks the highlight, view scrolls), `RET` lands,
  `C-g` returns to where you started. Added two general minibuffer hooks — `:on-preview`
  and `:on-abort`. Registered `brood-lsp` for `.blsp` so it works out of the box.
- **Files:** `src/lsp.blsp`, `src/commands.blsp`, `src/input.blsp` (minibuffer hooks),
  `src/keymaps.blsp`. **Tests:** +10 (`tests/lsp_test.blsp`, `tests/minibuffer_commands_test.blsp`).

### per-project bshell, per-buffer default-directory, faster project files, persistence — `f493ad5`
- **Why:** a project shell per project; project commands follow the buffer you're in;
  faster `C-x p f`/`p p`; reliable, unified state on disk.
- **What:** per-project bshell buffers; a generic per-buffer `:dir`; git-aware project-file
  listing; one shared atomic `persist-read`/`persist-write!`/`persist-mru` layer under the
  XDG state dir for projects/recent/bookmarks/bshell-history.
- **Files:** `src/bshell.blsp`, `src/projects.blsp`, `src/commands.blsp`, `src/modes.blsp`,
  and more. The project-files speedup is what motivated the `string-split` ADR-109 work.
