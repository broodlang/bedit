# Handoff — what to do next, and the traps

**Replaced each session; this is the *current* picture, not history.** The narrative lives
in [`../ROADMAP.md`](../ROADMAP.md) (§the open ends) and in brood's `docs/devlog.md`; the
decisions in brood's `docs/decisions.md` (ADR-352 is this session's). Read this to pick the
work back up cold.

## State when written — 2026-09-15, 14:40

- **bedit** `main` = `07700563` (`release: 0.4.3`), tag `v0.4.3`, pushed, tree clean.
  `project.blsp` says `:brood ">= 0.28.0"` — an older `nest` refuses the project outright
  (that is what "files: 0" from the suite means), so install brood first.
- **brood** `main` = `c247c996` (`fix(check): the ADR-352 scan loops pass the strict gate over
  std`) on `916c505a` (the other session's `ci: BEDIT_REF -> 07700563`) on `aa5f2a15` =
  `chore(release): v0.28.0` on `2a750c08`, the regex change. Tag `v0.28.0` pushed; the
  Release workflow **succeeded** — tarballs for every target are on the GitHub release.
  **CI on `main` was red for `916c505a`** on two jobs: the strict gate over `std/` (12
  findings, all in the new scan loops — mine, fixed by `c247c996`: `check-allow
  :type-mismatch` on the three loops whose `(count codes)` bound is one to three calls up,
  plus sigs; 0 locally now) and the `differential (tree-walker)` job (observer, mcp,
  sequence and highlight tests under `BROOD_VM=0`) — that job was already red on the run
  before the release (`34955268473`, 09:57) and is the "faces-nil" hunt the other session's
  `ci(differential)` commit names; not this work. Check `gh run list -R broodlang/brood` for
  `c247c996`'s run.
- **Installed:** `~/.local/bin/nest` 0.28.0 (`aa5f2a15`, GUI build from this session's
  worktree), `~/.local/bin/bedit` 0.4.3 on it. Verified on that pair: 51/51 test files,
  `nest check` clean, `nest check --strict` = 58 (the ratchet's ceiling), `make check-modes`
  green for all eleven modes, a keystroke in a 173-line `.bashrc` **14.6 ms** (was 430).
- **Your primary brood checkout** (`~/src/broodlang/brood`) has `main` behind origin:
  `git pull` there. This session's worktree (`regex-dfa-tokens`, merged) lives under
  `/tmp/claude-1000/…/scratchpad/brood-wt` and disappears on reboot — `git worktree prune`
  afterwards. Its `target/` is a symlink to `~/.cache/brood-wt-target` (4.8 GB, on disk):
  keep it, the next worktree gets a warm release-fast build from it.
- Restart any `bedit` window opened before 12:36 — it is a pre-0.4.3 binary.

## What landed this session (bedit 0.4.2 → 0.4.3, brood 0.27.2 → 0.28.0)

**The bug.** `bedit ~/.bashrc` was "pretty much unresponsive" and the X button did nothing.
Not a hang: `editor/shell` ran `regex/find-all` twice per line over the whole file on every
keystroke — 430 ms each on brood's pure-Brood capture engine (~40 µs per character; the
bitset `match?` is 0.19 µs, a 200× gap measured on the file's own lines). Held keys queued
seconds of work; `:close` waited behind it. Then, once shipped, a second failure: the mode's
`:fontify-restart` named a symbol in a module nothing loads for a shell buffer, and a
throwing refresh made the loop drop every event — the close request included.

**brood (ADR-352):** `regex/tokens` scans a rule table on the anchored DFA (earliest
position, first rule in table order, longest match; `\b` only at a rule's edges);
`regex/tokenizer` is the pure-data handle a `def` holds (the compiled plan, with its table
handles, lives in the module's cache — a table cannot be imaged); `regex/paint` answers a
line rule's one grouped question as prefix / paint / suffix, three DFA runs; `find`/`find-all`
enter the VM only at a start the DFA found (`(find "$" "abc")` is now the empty match at 3);
`editor/lexer` and `editor/shell` are one scan per line with the word rule as the table's
last row; `editor/highlight/line-restart` beside `safe-restart`. Numbers: `shell-spans`
whole-file 303 → 12 ms, a 36-char line 2.0 → 0.11 ms, 40 YAML lines 17.8 → 5.6 ms.

**bedit:** the nine line-oriented modes declare `editor/highlight/line-restart` (a keystroke
lexes the band, never the 200-line backscan); `input/ed-refresh-spans-guarded` — the loop
tail's span refresh may not veto the event (error echoed, `:done` kept; two tests in
`modes_test`); `tools/check-modes.sh` / `make check-modes`; the tests that pin checker
output moved with brood's checker; `strict_ratchet_test` ceilinged at 58 with the classes
named; the tutor's dead `nil?` guard gone.

## Traps — each cost a round of confusion this session

1. **A mode service is a SYMBOL, resolved at render time** (`ed-mode-service` →
   `reflect/eval`). Name only a module `modes` always loads (`editor/highlight`,
   `editor/treesit`, the mode's own `-spans` module). The test image loads everything, so
   this class is invisible to `nest test`; only the released binary from `$HOME` on a file
   of that mode shows it — that is what `make check-modes` is for. Run it before calling
   any mode change done.
2. **Every `nest`/`cargo`/`make`/`git` command waits on `~/.cache/brood/build.lock`**
   (`~/.claude/hooks/with-build-lock.sh`), held by whichever session builds; a plain
   `git commit` can sit for 20 minutes. Check `build.lock.holder` before debugging a "hang".
   `nest test` bare is blocked; run the suite per file:
   `ls tests/*_test.blsp | xargs -I{} sh -c 'nest test {} 2>&1 | grep "tests," | sed "s|^|{}: |"' | grep -v " 0 failed"`.
   A `for x in …` in a command trips the hook's env pre-check — use `xargs`/explicit lists.
3. **In a brood worktree the binary embeds `std/`** — every std edit needs a rebuild before
   `require` sees it (the "baked-in std/ is OLDER" warning means exactly that); the std
   image cache is keyed by commit + binary, not content; `make install` from a worktree
   needs `<worktree>/target` to be a symlink to the on-disk cache (`BROOD_EMBED_RUNTIME`
   is `$(CURDIR)/target/release-fast/brood`).
4. **Installing a nest from a newer brood moves bedit's checker-dependent tests** — type
   strings in `playground_test`, the strict ratchet, a diagnostic count in
   `gitdiff_async_test`. Classify against that before blaming the change under test.
5. **The harness kills idle background watchers "for memory"** even with 30 GB free —
   poll `gh run list` by hand rather than arming an hour-long loop.
6. `web_fuzz_session_test` renders the repo's own working-tree diff: a comment containing
   the literal phrase `render error` read as a failure once; the predicate now looks for
   the error FRAME (a column-0 `render error:` text on the echo row).

## Work queue — in the order to take it up

### 1 — The strict ratchet: 58 → 0 under brood 0.28.0's checker
`nest check --strict 2>&1 | grep warning:` — the classes, with counts as of `07700563`:
- **`number` into an `int` parameter** (~15: `view.blsp` `(+ y k)`, `(- pos bol)`,
  `(math/max 0 n)` in `statusbar.blsp`, `model.blsp:1650`, `wrap_test`/`view_scroll_test`):
  int arithmetic answering `number`. Check first whether this is the checker's interval
  arithmetic widening on a bound it cannot prove — if so it is a brood precision item
  (ADR-350's "checked operations that widen on overflow"), not 15 casts in bedit.
- **`nil | x` where the context has ruled nil out** (~25: `(nth bols 2)` in `modes_test`
  1355–1359, `bol-of` call-arg/body, `(proc/whereis :editor)` into `send` in `frames.blsp`
  162/181, `ed-buffer-index-by-name` in `frames_test`, `file/slurp`/`file/mtime`/
  `find-file-buffer` on a `nil | string` path in `model.blsp` 1557/1595): declare or guard,
  the ADR-350 way (`(int 0 _)`, `(len …)`), or bind-and-check like the tutor used to.
- **`ordered` into `string/pad-left`/`pad-right`** (4): what `count` or `sort` answers
  there — likely a brood curated-table row.
- **six `ed-pane-line-at: expects pane, got nil | {…}`** (`wrap_test.blsp:78` and kin) and
  `panes/ed-selected-pane` declaring `pane` but yielding `nil | …` (`panes.blsp:28`): the
  selected pane is `nil` only before a layout exists; declare that or narrow at the callers.
- Singles: `hosted.blsp:309` `assoc` on `countable (link)`, `commands.blsp:4644`
  `ed-vim-add-digit` over `(get *vim-digits* …)`.
Each fix is its own small commit; lower the number in `tests/strict_ratchet_test.blsp` as
you go — it may only shrink.

### 2 — Why `editor/lexer/line-restart` did not auto-load in the released binary
`reflect/eval` of a qualified symbol loads its module on first use (verified:
`(reflect/eval 'editor/lexer/lexer-spans)` resolves in a fresh `nest run` with nothing
loaded), yet the 10:08 `bedit` binary painted `unbound symbol: editor/lexer/line-restart`
on every frame from `$HOME`, while `'editor/shell/shell-spans` on the same layer resolved.
The move to `editor/highlight` fixed the symptom; the mechanism is unexplained. Repro
recipe: build a bedit with `:fontify-restart 'editor/lexer/line-restart` on shell-mode, run
it from `$HOME` on a `.sh` file with stdout captured, grep `render error`. Suspects: the
release bundle's std image (is `editor/lexer` a section that is present but not loaded, so
the miss path never fires?), and whether the auto-load runs inside the view's `try`. A
brood known-issue once understood; it decides whether trap 1 is policy or a bug.

### 3 — Residual lexer cost is interpreter overhead per token
Profiles after ADR-352: ~7 µs per token (the result map, the substring, the vector append)
and ~2.5 µs per character on a long line, against 0.2 µs for the DFA step. Levers, if a
large YAML/TOML/shell file ever feels slow: tokens as `[start end tag]` vectors with `:text`
on demand (the word pass is the only consumer that needs it), the `into acc [m]` append
(O(n²) in tokens per line, fine below ~50), and `shell-line-spans`'s per-token cond.
Measure with `scratchpad`-style `rxbench`/`lexbench` scripts (the shape is in brood's
devlog entry for 2026-09-15) — the discipline that paid all day: a number before a change.

### 4 — `regex/tokens` housekeeping in brood
`regex-tokens-cache` is keyed by the rule table's printed form, so a table built per call
grows it without bound (hold a `tokenizer` in a `def`, as the std lexers do — document that
in the module doc if it bites). `paint` detects laziness textually (`*?` `+?` `??` anywhere
in the paint pattern). `\b` inside a rule errors at first scan, not at grammar definition.
Every `find` pattern now compiles two machines (DFA + capture), so first-call cost and memo
memory per pattern roughly doubled — fine, but the memo tables are unbounded as before.

### 5 — Everything else is in `ROADMAP.md` §the open ends
The tree-sitter batch with grammars by location, org-mode, visual-line motion, the wheel
and the cursor — unchanged by this session, in the order written there.

## How to verify a change here (the loop that caught every bug this session)
1. `nest check` clean; the suite per file (trap 2); `nest test --failed` for the loop.
2. `make check-modes` after any mode/service change (trap 1).
3. `nest run tools/profile-turn.blsp -- <file> 210 48` for a keystroke's cost — the
   "unresponsive" report was a 430 ms `update "x"` there, and it is 14.6 ms now.
4. A live run with `BROOD_UI_TRACE=1 bedit <file>` from `$HOME`, stdout captured: `view=`
   and `update=` per turn, and any `render error` line.
5. After a brood change: `make install` (GUI) from the brood tree, then `make install`
   here, then all of the above against the installed binaries — `nest test` runs under the
   installed `nest`, and a stale one is the trap that cost three sessions before this one.
