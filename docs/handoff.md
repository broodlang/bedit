# Handoff — what to do next, and the traps

**Replaced each session; this is the *current* picture, not history.** The narrative lives
in [`devlog.md`](devlog.md) and brood's `docs/devlog.md`; the decisions in brood's
`docs/decisions.md` (**ADR-363** `cell-region` and its **ADR-080 amendment** are the two
this work rides on); the open bug it left behind is brood's **KI-163**. Read this to pick
the work back up cold.

## State when written — 2026-09-17, 18:00

- **bedit** `main` = `a14f4de5` (`refactor(types): guard the payload reads…`), tree clean.
  `4aaa117a` (the zoom/zone test) **is pushed**; `a14f4de5` **is not** — decide and push.
  Still on `23fc57f4` = `release: 0.4.9`, tag `v0.4.9` pushed. `~/.local/bin/bedit` is
  0.4.9 (built 13:30 UTC) and is *older than the working tree* — nothing in this session's
  work is in it.
- **`project.blsp` still says `:brood ">= 0.30.0"`** — read the comment above it. 0.4.9
  needs `gui/cell-size` + `cell-region`, which are on brood **main** and in **no release
  yet**; a released 0.30.x opens it and raises `unbound symbol: gui/cell-size` on the first
  Ctrl+wheel. The floor moves the day brood ships. **bedit is NOT published**: `nest search
  bedit` says 0.4.2 (0.4.3–0.4.9 tagged, never published) — publish only after the brood
  release with the floor bumped.
- **brood** `origin/main` = `07550da7` (`fix(gui): a cursor-zone inside a region is
  hit-tested again`) — **this session's, pushed, and CI GREEN** (run `35252303517`: every
  job, including the tree-walker differential and the bedit downstream smoke). That is
  the thing that changed today — the two differential timeouts the last handoff named are
  **gone** (both tests pass, merely slow), and the dangling `ADR-364` citation that
  reddened the run after them went with the other session's C9 landing. **The release
  train's blocker is cleared.**
- **A worktree is open at `~/src/broodlang/brood-wt`** (branch `gui-zones-through-regions`,
  `target` symlinked to `~/.cache/brood-wt-target`, `config.mk` copied). It holds one
  **unpushed** commit: `63957769`, KI-163's entry. Push or drop it, then
  `git worktree remove`. The primary checkout `~/src/broodlang/brood` is the OTHER
  session's (checker work, uncommitted) — **do not edit there**.
- **Installed `nest`** = `0.30.1 (cd87c8c1-dirty)` — still the other session's install from
  its uncommitted tree, i.e. **it does not carry this session's zone fix**. Everything
  below was verified against it, which is sound (bedit's tests are model/view-level), but
  a live hover over a zoomed pane's link needs `make install` from a brood worktree first.

## What landed this session

**Zones survive a region (brood, ADR-080 amendment).** `cell-region` landed yesterday and
quietly took the hot-zones inside it: the collector on `UserEvent::Draw` was
`ops.iter().filter_map(CursorZone)` — the frame's top level and nothing else — so a zone
under a `cell-region` (or a `scroll-region`, true since ADR-114) was never stored and never
hit-tested. Zoom a results pane and its links stopped showing the hand, though they still
painted and still clicked. The walk (`paint.rs`'s `cursor_zones`) now recurses into both
with `render_ops`' own coordinate math, and stores each zone as a **pixel** rect relative
to the grid origin — a region's cell is not the window's, so cells cannot carry the answer
out. The hit-test compares the pointer's pixel position on every `CursorMoved` rather than
only when the window cell changes: inside a zoomed region two zones can share one cell.
Five tests beside the region ones; bedit's side needed no change (its body ops are already
laid out in the region's cells) and is pinned by `testrun_test.blsp`'s "a zoomed pane's
link zones ride INSIDE its cell-region".

**The trusted-sig acknowledgements went 24 → 10, at the leaf.** A pane payload is `any` by
std's design — a pane carries whatever its app puts there — so every read off it was a
declared type nothing verified. A *built-in* predicate at the read proves the same type for
free: `(let (top (get-in pane [:payload :top])) (if (int? top) top 0))` reads as `int`
where `(or … 0)` read as unknown. Fourteen `(check-allow :trusted …)` came off — the pane
geometry, the selected-pane reads, the eol-note annotations, the Vim accumulator — and it
is better behaviour, pinned by a new test: a stale or hand-edited payload (a string `:top`,
a keyword `:ratio`) now falls back instead of reaching the arithmetic, where it used to
surface as `*: expected number, got nil` from inside the renderer.

## Traps — each cost a round this session

1. **`nest check --strict` is the fastest language probe you have.** Every question here
   ("does a guard narrow?", "does `vector?` prove a tuple?") was answered in seconds by a
   six-line file in the scratchpad and one `nest check --strict` — do that before reading
   any checker source.
2. **A `map?` guard satisfies an open record return; a `vector?` guard does NOT satisfy a
   tuple.** The second reports a *different*, non-suppressible warning (`declared return
   type area but the body yields vector`), so `ui-kit`'s `(tuple int int int int)` stays
   acknowledged while `commands`' `vim-pending` record did not.
3. **A declared `(is T)` guard narrows nothing** — see brood's KI-163. Do not reach for it
   to clear an acknowledgement until that is fixed; the repro is in the entry.
4. **A `sed` sabotage that silently does not match reads exactly like a passing test.**
   Twice a "sabotage-verified" claim here was a no-op `sed` (`?` and `(` in the pattern).
   Check the file changed — `git diff` — or sabotage with the Edit tool, then restore.
5. **Pushing again cancels the in-flight CI run**, and a cancelled run is not evidence of
   anything (brood's `known-issues.md` says so at length). Wait for the verdict before the
   next push to the same ref.
6. **Every `nest`/`cargo`/`make` command waits on the build lock**; a `$b`-style one-letter
   shell variable in a Bash tool command trips the hook's env pre-check and empties it.
   `make install` from a worktree replaces `~/.local/bin/nest` for **every** session on
   this box, including the one whose dirty tree built the current one.
7. **The runtime collects a frame's zones per pixel now.** Anything that reasons about
   hover in the kernel (`shape_at`, `Win::zones`) is in grid-relative *pixels*, not cells.

## Work queue — in the order to take it up

### 1 — Brood green → release v0.31.0 → bedit floor → `nest publish`
The blocker the last handoff named is gone; what remains is the verdict on `07550da7`.
When `gh run list -R broodlang/brood` shows main green: in a worktree (`git worktree add -b
release-0.31 …/brood-wt2 origin/main`; `ln -s ~/.cache/brood-wt-target target`; copy
`config.mk`), bump `Cargo.toml`, `project.blsp`, `std/system.blsp`'s example, move
CHANGELOG's `## Unreleased` under `## v0.31.0 — …` (`cell-region` + the zone fix are
features → minor), commit `chore(release): v0.31.0`, tag, `git push origin HEAD:main
--tags`, check `gh release view v0.31.0`. Then `make install` there; in bedit set
`:brood ">= 0.31.0"` (drop the comment), `release: 0.4.10`, tag, push, `make install`,
`make check-modes`, then `nest publish`. The ecosystem script
(`brood scripts/release-ecosystem.blsp`, `PUBLISH=1`) publishes the themes after bedit.

### 2 — The ten acknowledgements left, and the language gap under them
Seven are late-bound `reflect/eval` command results (unknown by design — a `map?` guard
would "work", but silently swallowing a command that did not answer a model is a policy
decision, not a type fix; make it deliberately or leave them). The other three — a
`(tuple int int int int)` off an open widget context, `ed-stamp`'s std return,
`ed-where-is-named`'s keymap-data string — each want **KI-163** fixed: one
`(sig p? (any -> (is T)))` and the read proves itself. That is brood work, in
`types/check/guards.rs`, in the same files the other session is living in — coordinate
before starting.

### 3 — A live look at a zoomed pane's links
Everything about the zone fix is verified by Rust tests and bedit's op-level test; the
*hover* itself has not been seen. After the release's `make install`, open a results
buffer (`C-c t`), zoom it (Ctrl+wheel), and check the pointer turns into a hand over a
row — the thing that was broken.

### 4 — Everything else is in `ROADMAP.md` §the open ends
The tree-sitter batch, org-mode, visual-line motion — unchanged by this session.

## How to verify a change here
1. `nest check` clean; the suite per file:
   `ls tests/*_test.blsp | xargs -I{} sh -c 'nest test {} 2>&1 | grep "tests," | sed "s|^|{}: |"' | grep -v " 0 failed"`
   (**1,702 tests**, ~3 s each file); `nest test --failed` for the loop; `nest check
   --strict` must read 0 (`tests/strict_ratchet_test.blsp` is the gate, ~21 s).
2. `make check-modes` after any mode/service change — it opens a window per mode.
3. `make drive` — the pty drivers (the real editor over `*term-display*`).
4. A real paint: a probe script over `gui-display` + `ed-update` + `ed-view` + `(:draw
   disp)` under `BROOD_GUI_DUMP` — it writes the LAST paint, so draw the frame you want to
   see last, and wait with a `receive` pattern nothing sends (the window posts resize and
   focus events, so a bare `(receive (_ nil) …)` returns at once).
5. After a brood change: `make install` (GUI) from a brood **worktree** with the `target`
   symlink, then `make install` here, then all of the above. Check `nest --version` first:
   `-dirty` means someone's uncommitted tree is your runtime.
