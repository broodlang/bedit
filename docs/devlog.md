# Dev log — bedit

A skimmable record of work, **newest first**. One entry per feature: what shipped, *why*,
the key files, the tests, and the commit. Use it to recover the *why* without reading every
diff; the commit (`git show <sha>`) has the full change. In-editor, `C-x g` + `TAB` and
`C-x v =` review the diffs directly.

Language-level changes live in the Brood repo's `docs/devlog.md` + `docs/decisions.md`
(ADRs) — e.g. the native `string-split` builtin this work depends on is **ADR-109** there.

---

## 2026-08-31

### two suite failures reproduce ON DEMAND under `taskset -c 0,1` — the CPU count was the missing variable
- **Why:** both had been seen only on a CI runner and read as flaky infrastructure.
  `tests/remote_test.blsp`'s own comment says as much — "observed on a 2-core CI runner
  (and once locally)" — and its mitigation (one key per await) was pacing rather than a
  fix, because nobody could make it fail when they wanted to. It turns out the variable
  is simply **core count**, not luck: pinning the suite to two cores fails both cases
  *every* run, while all 28 cores pass 3/3 and either case alone passes 3/3.

  ```bash
  ( ulimit -v 16000000; taskset -c 0,1 nest test )   # both fail, every time
  nest test                                          # 1378/1378
  ```

- **What fails, and what it means:**
  - `tests/remote_test.blsp:203` (two collab sessions) — expected `"Zq"`, got **`"qZ"`**.
    Exactly the mechanism the comment predicts: A's first press lands, then the attach
    SEED rewinds the server-side session's point, so the next press splices at 0. The
    pacing does not close it; the fix the comment already names does — **version-guard
    the seed against in-flight edits** — and it is a real collab bug, not a test artifact.
    A remote editor that silently transposes your keystrokes under load is the user-facing
    shape of this.
  - `tests/tutor_test.blsp:1612` (every shipped answer solves its exercise) — a note comes
    back `:fail` where `:pass` is required. The assertion is inside a double `dotimes` with
    no lesson/box in the message, so the next step is to name them before diagnosing.

  **Both are now fixed** (same day). Naming the lesson took the second straight to its
  cause: **lesson 32 box 2**, `first: … got keyword (:noproc)` — the tutorial's own answer
  for *"When a process dies"* failing its own exercise, because `(spawn …)` then
  `(monitor p)` is racy and brood had no atomic form. That became **brood ADR-309**
  (`spawn-monitor`), and the lesson now teaches it. The collab one was the seed clobber the
  `link-fold` guard closes (brood 9ddcfd8a). 1378/1378 twice under two cores.

- **Not caused by the brood 0.20.0 / data-first migration.** bedit's own CI was red on
  `0e61442f` and `1b9a03a2` — both pre-migration — and `672952f6` was red only on
  `nest format --check` (39 files, since fixed in `32bdcf0a`). Found while making brood's
  `downstream-bedit` gate green for the 0.20.0 release, which is the job that keeps
  hitting it.

## 2026-08-02

### the tail-call lesson stops contradicting itself; every display truncates — Brood ADR-207
- **Why:** the tutorial's "Recursion is the loop" box counts a million tail calls down to prove
  O(1) stack — and it *overflowed*: `recursion too deep: exceeded the VM's 1048576-frame
  non-tail-call limit`. The tutorial boundary-traces every box (the *Workings* pane follows the
  cursor), and a trace wrapper emits its `:return` AFTER the call, so each level of a traced
  self-call is a real frame. The number had already been walked back to 250 000 with an
  apologetic comment; the instrumentation was contradicting the lesson it illustrated.
- **Brood (prime directive), not worked around here — ADR-207:** a `*spy-sink*` may answer
  `:spy-stop` ("I have all I want"), and `debug/trace-fn` then restores the original and
  delegates in TAIL position — so past its budget a traced loop is a plain tail loop.
  `eval-server`'s sink answers it at `*spy-entry-cap*`. Separately, `pr-str-bounded` gained
  `*print-string-length*` (a *leaf* bound — collections and nesting were bounded, a 10 MB string
  was not) and every display protocol now prints through it. Measured through the sandbox's own
  path: 250k traced calls 641 ms → 73 ms, 1M 2493 ms → 227 ms (was over the 2 s box budget), 4M
  from overflow → 844 ms.
- **What (here):** the box is a million again, and its comment records why that is now honest;
  the lesson body teaches the budget note as the point ("watching costs something"). The
  *Workings* header says *"the first 200 traced calls"* when the cascade filled the budget,
  instead of claiming "every traced call and return" — it also footers that the code carried on.
  Display paths bounded: the *Spy* tap's JSON fields, the `*Debug*` locals preview, the trace
  lines, eval-in-scope, and `C-x C-e`'s `=> …` (Emacs bounds this too —
  `eval-expression-print-length`).
- **Files:** `src/tutor-lessons.blsp`, `src/tutor-workings.blsp` (`budget-spent?`),
  `src/debugger.blsp`, `src/eval-command.blsp`. **Tests:** +3 in `tests/tutor_test.blsp`
  (a short cascade vs one that filled the budget); suite green (1205).
- **A false green fixed, and the driver that would have caught it:** `tools/term-tutor.blsp`
  never called `sandbox-start` (that is `cmd-tutorial`'s job, and the harness opens the tutorial
  by calling `tutor--show`), so `sandbox-eval` was a documented **no-op** — every box sat at
  "⋯ evaluating…". `drive_workings.py` passed anyway, because "sum-doubles" and "*Workings*" are
  on the page as box source and prose. It now asserts on the pane's own vocabulary (`= 12`, a
  return line only a real cascade produces) and on the verdict note. New
  **`tools/drive_tailcalls.py`**: a million traced tail calls answer `=> :liftoff` in the real
  editor — unreachable from model tests, which deliberately instrument nothing.
  `term-tutor.blsp` takes the lesson from `BEDIT_DRIVE_LESSON`, so a new check is a new driver,
  not a second copy of the harness.

## 2026-07-11 (later)

### The actor-model endgame (§E.2) — every buffer a process — `b6937fa`…
- **Why:** close `docs/actor-architecture.md` — the design-of-record since June. The
  collab track had proven the seam on SHARED buffers; the endgame makes it the
  editor's normal state: every buffer a fault-isolated, subscribable process, the
  pure model kept as its projection cache.
- **What (each slice its own commit, suite green throughout):**
  - **E0 exoneration:** the June-16 "async replies don't land" revert was
    misdiagnosed — the real bug was a stuck `:held-key` gating the idle beat
    (`cac0ce3` had the truth); the task-reply contract is now test-pinned, so
    services can trust the event bus.
  - **hosted machinery** (`src/hosted.blsp`, model key `:shared` → `:hosted`):
    `ed-host-slot`/`ed-unhost-slot`/`hosted-step` (loop-tail propagate with an O(1)
    rope-handle guard)/`hosted-apply-content`; **the flip** — `:host-buffers?` on
    the live window's model + `hosted-reconcile` hosts every slot as it appears;
    kill-buffer stops local processes and remaps the index-keyed links (also fixing
    the stale-index gap for shared slots).
  - **fault isolation:** hosted processes monitored; `[:down]` → rehost from the
    pool cache (local) or re-share onto the registry's respawn (shared); the
    registry mirrors every document's text via the std client fold and respawns
    died buffers from CURRENT content.
  - **services:** eldoc joins diagnostics on the `std/task` idle pattern; every LSP
    lookup async (corr-matched `:lsp-pending`, rope-guarded format/rename, stale
    replies drop; completion keeps its bounded modal wait). kill-ring + persistent
    fontify workers deferred with recorded triggers.
  - **collab = hosted + people:** `collab-edit`→`hosted-edit`, propagate delegate
    deleted, module doc rewritten — presence (markers, tags, follow, registry) is
    all that remains there.
- **Brood (prime directive), forced by this track:** **concurrent-safe `require`**
  (defmodule's top-of-file `provide` let a racing require observe a half-loaded
  module — surfaced as a 1-in-5 suite flake, fixed with `*features-loading*` +
  waiter takeover); **`editor/buffer-client`** (ADR-134 — the protocol's client
  half: `link-init/-propagate/-fold`, `text-splice`, `view-parts`,
  `text-apply-splice`); `[:io/write]` as a ring-recorded splice delta;
  `buffer-edit-reply`/`-value` (read-then-decide edits); native `%str-splice-diff`
  (the per-keystroke diff: 40 ms → 0.4 ms on a 300-line hosted buffer).
- **Tests:** `tests/hosted_test.blsp` (new — host/converge/echo/fault/flip/kill),
  window_point invariants, registry-mirror respawn + reshare, async eldoc/LSP folds,
  the std merge matrix + an 8-process require race upstream.

## 2026-07-10/11

### Remote & multiplayer editing — Track 1 built end to end — `dff66ab`…`628c385`
- **Why:** the flagship strategic track: one editor you attach to from anywhere, and
  real multi-person editing with presence — the "ultimate pairing experience."
- **What:** the daemon/emacsclient model (`--serve`/`--attach`, host window,
  `--headless`); ONE shared mode (`--shared`, alias `--collab`) — shared content, a
  caret per participant, every visited file auto-shared via a per-daemon registry;
  presence (named coloured carets with fade-after-move tags, per-owner selection
  tints, viewport markers, join/leave echoes, a modeline chip, `M-x collab-status`);
  `share-follow` (C-x f) across buffers and `share-mirror` (leader's viewport);
  `M-x share-session`/`-stop` (a live editor becomes a host; stop tears everything
  down); names from `--as` → init `:share-name` → `$USER` → prompt; deltas + OT
  (based splices, `splice-transform` at the process AND the client, origin-tagged
  echo suppression — concurrent typing in different places merges exactly, undo
  survives); `--listen` TCP beside the Unix socket (kernel dual-listen, ADR-074).
- **Brood (prime directive), forced by this track:** serve identity opts +
  event-bus pass-through in the daemon displays + `serve-stop`; buffer-process
  subscriber lifecycle (monitor + pid-keyed marker cleanup), structured
  `buffer-splice`/`buffer-marker-move` deltas, splice transforms; **pid equality/hash
  across `node-start`** (captured pre-node pids silently stopped matching — the
  "second attach sees nothing" bug); the **immortal-process bug** (exit signals never
  reached a natively-nested receive; landed as ADR-132, independently from both
  machines); `%isolate`'s reap no longer kills its own caller. Plus, found while
  testing: `safe-restart`/`sexp--defun-start` had gone O(pos) interpreted (~3.3 s
  eldoc stalls on 3K-line files) — now the native `scan-form-start` (ADR-093 family).
- **Files:** `src/collab.blsp` (the whole presence/delta/follow layer),
  `src/remote.blsp`, `src/commands.blsp` (share-session/-follow/-mirror/collab-status),
  `src/input.blsp` (`collab-step` at `ed-update`'s tail; `:buffer-updated`/
  `:client-opts` handlers), `src/view.blsp` (carets/tints/chip), `src/keymaps.blsp`,
  `src/config.blsp` (`:share-name`). **Tests:** collab/remote suites (~40 new),
  brood buffer/serve/exit-signal suites. **Docs:** `remote-multiplayer-plan.md`
  (as-built ledger), `working-from-another-computer.md` (runbook),
  `fuzz-diag-overrides-anomaly.md` (an open JIT compiled-vs-source lead found en
  route). Open: v2 CRDT, per-participant undo, cross-machine verification.

## 2026-06-16 → 2026-07-09 — catch-up (condensed)

The devlog lapsed for three weeks. What shipped, newest first — one line each; the
commits (`git log --since=2026-06-16 --until=2026-07-10`) have the detail:

- **Buffer placement + CLI polish** — `ed-display-buffer` placement policy (git-log
  pops a new pane) `daff168`; `bedit DIR` opens dired `9a4631b`; a Makefile install
  target for the standalone `bedit` binary `7a9da03`.
- **Git porcelain round 2** — Magit-style section nav, branch ops, unpushed/unpulled
  sections, collapsing `b10a42e`; side-pane diff preview from status `5ad9c15`;
  viewport-aware diff loading `e3c970c`; hunk-apply newline fix `0178763`.
- **Startup** — async deferred loading, ~1.1 s → ~0.4 s perceived `a1647d8` (the
  compiled-module-cache language gap remains — ROADMAP §H).
- **Scrolling & chrome** — window title + smooth pixel scrolling (ADR-114) `a57c1da`;
  macOS-style overlay scrollbar `f74fee6`/`6903958`; boundary-bounce and
  cursor-vs-scroll-region fixes `63b572a`…`4607b6f`; themed padding, zero inset,
  gutter margins.
- **Compile mode & friends** — `M-x compile` + `C-x \`` next-error, auto-save,
  `repeat`, M-x history, perf caches `0914ac0`.
- **Status bar as segments** — clickable/hoverable segments + a git working-tree
  indicator `882b2c4`; the design is `docs/ui-chrome.md`.
- **diff-hl hardening** — synchronous recompute so the gutter follows edits,
  blink-tick refresh, `C-g` cancels workers `b385e97`…`cac0ce3`.
- **Meta** — LICENSE + CONTRIBUTING + the configurability/packages design notes
  `645f9cd`; rename magit → git + idiomatic cleanup passes `823a2b5` `acde663`;
  code-review fix batches `ad1b97b` `57067bc` `0ce6085` `84b92ef`.

## 2026-06-15

### design notes: the customization surface + a package ecosystem — `645f9cd`
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
    `~/.config/bedit/` is itself a nest whose `:dependencies` are the installed
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

### Tab completion like Emacs; one symbol boundary; playground drops are logged — uncommitted
- **Why:** Tab on a function just written in the buffer often offered nothing: the
  mode source (`symbol-prefix-at`) and the buffer-word source (`complete-word-char?`)
  disagreed on where a prefix starts after `'`, `` ` ``, `~`, `^`, so `complete-at`
  dropped the buffer words; and the fuzzy re-rank reordered prefix matches for no
  visible reason.
- **What:** every source uses std's `symbol-char?`/`symbol-prefix-at`. `cmd-complete`
  follows `completion-at-point`: unique → insert; several → longest common prefix; the
  popup only when nothing more expands; candidates alphabetical. `/` is a word boundary
  for `M-d`/`M-DEL`/`M-f`/`M-b` (std `buffer-word-char?`), so `math/floor` is two words.
  `playground-sandbox-reply` logs (`log/warn`) the reason whenever it drops a reply.
- **Files:** `src/complete-at-point.blsp`, `src/lsp.blsp`, `src/playground.blsp`.
  **Tests:** +10 (`tests/complete_test.blsp`).

### 2026-08-30 — no catch swallows an error unread (`:discarded-catch` at zero) — uncommitted
- **Why:** bedit ran for hours with ten unbound `gui/font!`-style references (renamed by
  brood ADR-302) because each sat in `(try … (catch e nil))`. brood's new `:discarded-catch`
  lint flagged 55 more handlers of that shape across `src/` and `tests/`.
- **What:** each site got the honest fix, none a refactor. *Best-effort I/O* (init/auto-save/
  persist/cache writes, `file/rm` of an auto-save or the sandbox script, `os/close` — which is
  idempotent, so a throw there is a fault — clipboard read, `require-one` of a deferred
  command module, the eldoc/doc-at/gutter-click/close-context mode services, `git`
  subprocesses, a project-walk `file/ls`, LSP-frame and web-key JSON decodes, the package
  manifest and plugin-entry reads) now `log/warn`s `error-message` into *Messages* and
  returns the same fallback. *Probes where the error is the answer* (reading half-typed text:
  `liveeval`, `eval-command`, `brood-arglist-of`/`brood-doc-block`, the two `parse-int`s,
  `tutor` box checking; path completion against a directory that may not exist yet in
  `mincomplete`/`bshell`; `ed-doc`'s first-of-two `doc` evals; `ed-json-event-line` on
  non-JSON runner output; `os/exe-path` and the candidate-runtime `os/spawn` in `sandbox`;
  the SSE emit / keepalive whose failure IS the browser-gone signal in `web`) keep their
  catch under `(check-allow :discarded-catch …)` with a one-line reason at the site.
  *Tests* (`apprun`, `testrun`, `tutor`) return sentinels (`:close-failed`, `:inserted`/
  `:refused`) instead of nil/false. `theme/gui-only` no longer matches the error string: it
  is `(when (gui/available?) (apply f args))`.
- **Files:** `src/{about,bshell,commands,compile,config,eval-command,interactive,liveeval,
  lsp,mincomplete,model,modes,packages,panes,playground,procstream,projects,sandbox,theme,
  tutor,web}.blsp`, `tests/{apprun,testrun,tutor}_test.blsp`. `nest check` reports zero
  "catch discards" warnings; the suite is red from the in-flight data-first argument-order
  migration (`empty?: expected collection, got fn`), not from these edits.
