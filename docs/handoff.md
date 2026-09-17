# Handoff — what to do next, and the traps

**Replaced each session; this is the *current* picture, not history.** The narrative lives
in [`devlog.md`](devlog.md) (newest entry: the per-pane zoom) and brood's `docs/devlog.md`;
the decisions in brood's `docs/decisions.md` (**ADR-363**, `cell-region`, is this
session's). Read this to pick the work back up cold.

## State when written — 2026-09-17, 17:00

- **bedit** `main` = `ad446851` (`chore(strict): the ratchet reads 0 under brood's
  trusted-sig lint`), on `23fc57f4` = `release: 0.4.9`, **tag `v0.4.9` pushed**, tree clean.
  `~/.local/bin/bedit` is 0.4.9 (built 13:30 UTC) and passes `make check-modes` on all
  eleven modes. `project.blsp` still says `:brood ">= 0.30.0"` — read the comment above it:
  0.4.9 needs `gui/cell-size` + `cell-region`, which are on brood **main** and in **no brood
  release yet**. A released 0.30.x opens 0.4.9 fine and raises `unbound symbol:
  gui/cell-size` on the first Ctrl+wheel. The floor moves the day brood ships.
- **bedit is NOT published** to the registry: `nest search bedit` says 0.4.2 (0.4.3–0.4.9
  were tagged, never published). Publish only after the brood release, floor bumped —
  a registry package whose zoom fails on every released runtime is worse than 0.4.2.
- **brood** `origin/main` = `03e955c6` (`ci: BEDIT_REF -> ad446851`) on `989af614`. This
  session's commits: `f8827ab1` (cell-region, ADR-363), `b312370e` (wasm stub + doc
  examples), `03e955c6`. **CI on main is red** on the OTHER brood session's checker work,
  not on the cell-region work — see queue item 1. The primary checkout
  `~/src/broodlang/brood` is that session's: `main` at `989af614` (behind origin) with
  uncommitted `types/*.rs` edits and a fresh build at 16:48; **do not edit there**.
- **Installed `nest`** = `0.30.1 (cd87c8c1-dirty)` — the other session's install from its
  uncommitted tree. It carries cell-region (`cd87c8c1` is after `b312370e`) and the new
  checker lints; it is the runtime baked into bedit 0.4.9 (`nest release` embeds the
  installed nest's runtime). Not a released brood.
- **Disk:** `/` was at 100% during this session (brood's `target/debug` had grown to 195 GB
  of `cargo test` binaries in one day); `target/debug` and `target/tmp` were deleted under
  the build lock, `/` is 67% now. `~/.cache/brood-wt-target` (8.7 GB, on disk) is the warm
  `release-fast` for worktree installs — keep it. All stale worktrees pruned; brood has
  one checkout again.
- **`~/.claude-hst/settings.json` now has the build-lock + no-full-suite hooks.** A session
  started under that config dir had none, ran a bare `cargo test -p brood --features gui`
  in the terminal's own cgroup, and systemd-oomd killed the whole tab (28 GB peak) — that
  was the "you crashed AGAIN". The hooks are the fix; the scripts stay in `~/.claude/hooks`.

## What landed this session (bedit 0.4.8 → 0.4.9; brood main, unreleased)

**The zoom is per pane, and it is a render op — not a font change.** Ctrl+wheel zooms the
pane under the pointer a pixel a notch; `C-x C-=` / `C-x C--` / `C-x C-0` (`M-x
text-scale-*`) the selected pane; the window's font never moves. A zoomed pane's mode line
carries a chip (`⌕ 20px`) whose click is 100% again. Full story in `devlog.md`; the short
version: five pacing fixes to a whole-window font change each moved the jank elsewhere
because the model was wrong, so the capability went into the language — brood's
`[:cell-region x y w h px ops]` paints a block at another font size inside a rect given in
the parent's cells, and `gui/cell-size` measures the cell a size produces (13×29 px at 21 px
over 9×21 at 15 — not the ratio, which is why it is measured). bedit stores `:zoom {:px
:ratio}` on the pane payload; every geometry read (`panes/ed-zoom-ratio`, `ed-pane-cols`,
`ed-pane-vrows`, `ed-pane-row-index`, `ed-buf-offset-at`) divides by the ratio; the view
lays the body out at origin 0,0 and wraps it. The integer `:scale`, `ed-scale-op`, the `s`
parameter through seven view helpers and the window-zoom throttle/timer are gone. It began
as a per-BUFFER zoom (Emacs's `text-scale-adjust`) and a split showing one buffer twice
zoomed both sides — the user's "all the buffers zoom" — so it moved to the pane.

**The status bar hit-test answers for the pane whose bar holds the cell** (it answered for
the selected pane only), selects that pane before a segment's command runs, anchors the
tooltip on the hovered bar, and lights the hover pill only there — what a per-pane chip
needed.

**bedit is strict-clean under brood's new trusted-sig lint** (A5 in
`docs/type-system-status.md`): `declared return type T is trusted, not verified` fires when
a `sig`'s return cannot be verified because the body's result is the unknown. 26 sites in
bedit — a pane payload (`any` in `std/editor/pane`), a command resolved late through
`reflect/eval`, an annotation's value, an open map — each acknowledged with `(check-allow
:trusted (defn …))` and a comment naming which; two test helpers' sigs fixed at the leaf
(`any` → the real parameter type). If the lint ever learns the pane payload's shape, the
acknowledgements come off.

## Traps — each cost a round of confusion this session

1. **Which `~/.claude` a session runs under decides its hooks AND where its transcript
   lives.** A `CLAUDE_CONFIG_DIR=~/.claude-hst` session's transcript is under
   `~/.claude-hst/projects/…`; a "lost" session is usually in the other dir. Both dirs now
   carry the hooks — check `settings.json` before trusting a session is capped.
2. **A `try … (catch e nil)` in a probe/harness `receive` is not the trap — the mailbox
   is.** `(receive (_ nil) (after 400 nil))` returns at once, because the window posts
   resize/focus events to the process; wait with a pattern nothing sends
   (`(receive ([:probe-never] nil) (after 400 nil))`). `BROOD_GUI_DUMP=x.ppm` writes the
   LAST paint, so draw the frame you want to see last; `ffmpeg -i x.ppm x.png` to look.
   The recipe is in `tools/`-less form in the devlog; `zoom-probe.blsp` lived in the
   session scratchpad and is gone — 40 lines, easy to rewrite from the memory note.
3. **A test that hands `zoom-step` a laid-out pane feeds it a stale accumulator** — the
   wheel is many events, and the pane's payload changes under each. `zoom-step` reads the
   LIVE payload (`pane-payload-at` by the pane's `:path`); anything else that folds a
   stream over a pane must too.
4. **`ed-modeline-click`'s command runs on the SELECTED pane** (`(m key) -> m`), so a
   per-pane segment must select its pane first — done in `ed-modeline-click`; a new
   per-pane segment gets it for free, a new *entry point* to segment commands must repeat it.
5. **A brood ADR number is a race between sessions.** ADR-362 was taken while this one
   rebased; the cell-region ADR is 363. Renumber before pushing, not after.
6. **Every `nest`/`cargo`/`make` command waits on the build lock**; bare `nest test` is
   blocked — the per-file loop is in "How to verify". A `$b`-style one-letter shell
   variable in a Bash tool command trips the hook's env pre-check and empties it (it
   truncated a test file once); use longer names or a script file.
7. **The runtime collects `cursor-zone`s from a frame's top-level ops only** — inside a
   `cell-region` (and a `scroll-region`, which was already so) a zone is never hit-tested,
   so the pointer-hand over a results buffer's links is lost in a zoomed pane. Queue item 3.

## Work queue — in the order to take it up

### 1 — Brood green → release → bedit floor → `nest publish`
Brood main is red on the other session's checker work (`3cbeb090`…`989af614`):
- `test` and `differential (tree-walker)`: two nest differential tests **TIMEOUT at 120 s**
  — `nest::check_order_differential a_files_verdict_depends_on_neither_the_list_order_nor_the_process`
  and `nest::derivation_cache_differential the_site_walk_cache_changes_no_verdict_and_no_inferred_signature`
  (their B8 work; that session has `types/tests.rs` open).
- `downstream smoke (bedit @ BEDIT_REF)`: was the trusted-sig lint at the old ref; fixed
  by `ad446851` + `03e955c6` — expect green on the next run.
When `gh run list -R broodlang/brood` shows main green: in a worktree (`git worktree add
-b release-0.31 …/brood-wt origin/main`; `ln -s ~/.cache/brood-wt-target target`; copy
`config.mk`), bump `Cargo.toml`, `project.blsp`, `std/system.blsp`'s example, move
CHANGELOG's `## Unreleased` under `## v0.31.0 — …` (cell-region is a feature → minor),
commit `chore(release): v0.31.0`, tag `v0.31.0`, `git push origin HEAD:main --tags` — the
Release workflow builds the tarballs (`gh release view v0.31.0`). Then `make install`
there; in bedit set `:brood ">= 0.31.0"` (and drop the comment), `release: 0.4.10`, tag,
push, `make install`, `make check-modes`, then `nest publish`. The ecosystem script
(`brood scripts/release-ecosystem.blsp`, `PUBLISH=1`) publishes the themes after bedit.

### 2 — The trusted-sig lint: 26 acknowledgements that want to be one type
Every `(check-allow :trusted …)` in `panes`/`model` says the same thing: the pane payload
is `any` in `std/editor/pane` (`(deftype pane (record &open :path list :payload any …))`).
The language fix (prime directive) is a payload type parameter or bedit declaring its
payload record and std's `pane-*` functions carrying it through; then `(:top payload)` is
`nil | int` and nine acknowledgements come off. The `reflect/eval` ones stay — a late-bound
command's result is unknown by design.

### 3 — Cursor zones through regions (brood)
`crates/lisp/src/host/gui/backend.rs`, `UserEvent::Draw`: `w.zones` is
`ops.iter().filter_map(CursorZone)` — top level only, cells. Recurse into `ScrollRegion`
(same cells, the scroll offset applies) and `CellRegion` (the region's cells: a zone at
region `(x, y, w, h)` is at parent px `(rx*cw + x*cw', ry*ch + y*ch', w*cw', h*ch')`, from
`renderer.metrics_at(px)`), and store zones as **pixel** rects so the hover test compares
the pointer's pixel position (it has it before `px_to_cell`). A Rust test per shape. Then
bedit's `ed-pane-link-ops` zones (inside the scrollable block, inside the region) work
unchanged.

### 4 — Everything else is in `ROADMAP.md` §the open ends
The tree-sitter batch, org-mode, visual-line motion — unchanged by this session.

## How to verify a change here (the loop that caught every bug this session)
1. `nest check` clean; the suite per file:
   `ls tests/*_test.blsp | xargs -I{} sh -c 'nest test {} 2>&1 | grep "tests," | sed "s|^|{}: |"' | grep -v " 0 failed"`
   (1,701 tests, ~3 s each file); `nest test --failed` for the loop; `nest check --strict`
   must read 0 (`tests/strict_ratchet_test.blsp` is the gate).
2. `make check-modes` after any mode/service change — it opens a window per mode.
3. `make drive` — the pty drivers (the real editor over `*term-display*`).
4. A real paint: a probe script over `gui-display` + `ed-update` + `ed-view` +
   `(:draw disp)` under `BROOD_GUI_DUMP` (trap 2), sandbox off — it opens a window on the
   desktop, so not while someone is working on it.
5. After a brood change: `make install` (GUI) from a brood **worktree** with the `target`
   symlink, then `make install` here, then all of the above — `nest test` runs under the
   installed `nest`. Check `nest --version` first: `-dirty` means someone's uncommitted
   tree is your runtime.
