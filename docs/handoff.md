# Handoff — what to do next, and the traps

**Replaced each session; this is the *current* picture, not history.** The narrative lives
in [`devlog.md`](devlog.md) and brood's `docs/devlog.md`; decisions in brood's
`docs/decisions.md`; the open backlog is [`../issues.md`](../issues.md). Read this to pick
the work back up cold.

## State when written — 2026-09-23, evening

- **bedit** `main` is pushed and the tree is `nest format`-clean (the whole tree was
  reformatted once today; CI's `nest format --check` had kept it red since 09-22).
  `~/.local/bin/bedit` was rebuilt today on brood `50161f5d`.
- **brood** `main` carries today's three landings: the Magit support (`std/editor/section`,
  `std/diff` reading a unified diff — ADR-388), **native regex** (ADR-389, below), and the
  pre-push hook no longer leaking `GIT_DIR` into the tests (`1054c7ba`).
- **Installed `nest`** is `0.33.0 (50161f5d-dirty)` — built from the `ci-green` worktree,
  i.e. `main` plus the unpushed CI fixes below. bedit's whole suite (2,426), `nest check`
  and `--check-boot` are green on it.
- **brood CI was red** on v0.33.0 (six gates) and on the regex push (same six plus the
  downstream smoke's old pin). The fixes exist twice: a brood session live in
  `~/src/broodlang/brood` (uncommitted there, its own KI-187), and this session's
  `~/.cache/brood-wt-ci` branch `ci-green` (`55f306cd`, `39dc66ba`: the adopted fixes,
  KI-186, KI-187 and `BEDIT_REF` → `6cbe57e6`). Whichever lands first, the other rebases or
  is dropped; **the `BEDIT_REF` bump must land either way** (the smoke job is red on the old
  pin's callers of changed APIs).

## What landed today

**Magit parity** — the git porcelain is section buffers (`src/sectionbuf.blsp`), every view
(`src/gitview.blsp`), smerge, and every Magit menu; brood's half is ADR-388.

**The git window painted slowly** — not git: every frame asked each visible row "is this a
`file:line` link?", and *git-status* answered by running the error-pattern regex table over
every commit and hunk line. It now reads its link map only (`results/line-links-only-loc`),
and the view memoises link zones like it memoises rows (ADR-336). 25 → 3 ms a frame.

**Native regex** (brood ADR-389) — `std/regex` keeps Brood's dialect (its parser, the
forgiving rules for a stray metacharacter) and translates each pattern for `regex-automata`,
which matches. `find` ~2 µs, `tokens` ~9 µs a line, the `file:line` table ~8 µs a line
(was ~0.5 ms). `\w \s \b` are Unicode now, `\d` ASCII. bedit needed no change.

## Traps — each cost a round today

1. **A pre-push hook's `GIT_DIR` reaches every child.** Tests that shell out to git (brood's
   `package_test`) wrote into the real repository — `core.bare = true`, a `Test` identity,
   commits on the branch, junk tags. Fixed in the hook (`1054c7ba`); if a push ever fails
   with "could not lock config file", check `.git/config` for `bare = true` and a `[user]`
   before anything else.
2. **`cargo test` is not how brood CI runs the lib tests.** Its threads share one process,
   and `*features*` is shared by every interpreter in it, so `image_sigs`'s transitive-scan
   test fails beside anything that loads its probe module. CI runs nextest (a process per
   test) — judge by that.
3. **The disk fills.** The 620 G disk hit 100% today (~230 G of it brood build targets) and
   an edit failed with ENOSPC. `target/debug/incremental` and the `.claude/worktrees/agent-*/
   target` directories are cache; they were cleared (~90 G).
4. **The Bash hook blanks shell variables** — in a loop, and inside a heredoc that WRITES a
   script. Write a script with the Write tool, pass arguments, run it.
5. **Two sessions on one bug.** A brood session and this one both fixed KI-187 today. Before
   starting on brood, check for a live `claude` process whose cwd is brood
   (`readlink /proc/<pid>/cwd`), not just the transcript time.

## Work queue

1. **Land brood CI green** (see State) and confirm `gh run list -R broodlang/brood` goes
   green, the downstream smoke included.
2. **`issues.md`** — sixteen open or partly-done items; in progress this session.
3. **The `regex` benchmark row** now measures the native engine and is no longer a dogfooding
   signal for the interpreter (ADR-389 says to replace it). **Ask Wilhelm before starting.**

## How to verify a change here

1. `nest check` clean; the suite per file (the bare `nest test` is blocked by a hook):
   `for f in tests/*_test.blsp; do …; done` (2,426 tests); `nest test --failed` for the loop.
2. `nest format --changed` before committing — CI checks it.
3. `make check-modes` after a mode/service change; `make drive` for the live pty drivers.
4. After a brood change: `make install` (GUI) from a brood **worktree** with the `target`
   symlink, then `make install` here, then all of the above.
