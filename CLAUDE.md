# CLAUDE.md — working in the myedit repo

Guidance for Claude Code (and humans) working in this project. For the machine
setup (Ubuntu, apt, Rust via rustup, etc.) see the global `~/.claude/CLAUDE.md`.

## What this project is

**myedit is an Emacs clone, written in [Brood](../brood).** Brood is a small,
immutable Lisp built specifically to be the language a modern, self-editing,
remotely-hostable editor is written in. This repo is that editor — the thing
Brood exists to make possible.

The editor is **pure Brood glue over the editor toolkit that ships in Brood's
`std/`**, nothing custom in any kernel:

| Layer | Toolkit module | Role |
|---|---|---|
| model | `std/editor/buffer.blsp` | immutable, rope-backed buffer — pure point/movement/editing ops |
| view  | `std/editor/display.blsp` | `clear` / `text` / `cursor` / `frame` render ops (plain data) |
| input | `std/editor/keymap.blsp` | rebindable `key → command-symbol` dispatch (late-bound, hot-swappable) |
| modes | `std/editor/layers.blsp` | per-buffer mode stacks: keymaps + language services as data |
| loop  | `std/editor/ui.blsp` `ui-run` | TEA-style render→poll→update loop over `(gui-display)`, a native window |

We're targeting Emacs behaviour: Emacs keybindings (`C-x C-e`, `C-f`/`C-b`/`C-n`/
`C-p`, `M-f`/`M-b`, prefix chords, …), multiple buffers, a `*Messages*` echo
area, eval-in-buffer, eventually a self-editing keymap you can redefine live.

## The prime directive: improve the *language*, don't hack the editor

**This is the most important rule here.** When the editor needs a core
abstraction Brood doesn't yet have, the correct move is **to go add it to the
Brood language** (in `../brood` — a kernel primitive or a `std/` module), then
build the editor feature on that clean primitive. **Do not** hack the missing
capability into myedit as a one-off workaround.

This is not a detour from building the editor — it *is* building the editor. A
self-editing Emacs clone is only possible if its abstractions live in a language
expressive enough to host them. Every gap the editor exposes is a gap in Brood
worth fixing properly. **Be actively on the lookout for these** — treat "myedit
wants X and can't express it cleanly" as a signal to improve Brood, and say so.

**Worked example (the live one).** Eval-in-buffer (`C-x C-e`: eval the form
before point, show its output in the `*Messages*` buffer) needs to *capture*
what the evaluated code prints. Brood has no output capture today — `print`/
`println` write straight to stdout (`crates/lisp/src/introspect.rs` flags the
missing `*out*` dynvar + `with-out-str` facility explicitly). The wrong fix is
to intercept output inside myedit. The right fix is to **add `*out*` +
`with-out-str` to Brood** — a general capability (REPL capture, test output
assertions, the MCP `EvalResult.stdout` field all want it) — and then have
myedit's eval command simply `(with-out-str …)`.

When you do change Brood, follow that repo's conventions (`../brood/CLAUDE.md`):
prefer Brood over Rust, keep the core small, add a builtin only when it genuinely
needs Rust, write tests, update `docs/`, record an ADR if it's a real decision.

## Writing a plan: always two parts

Every plan for this project **must have two explicit parts, in this order**:

1. **What we can do in Brood to improve this.** The language gaps this work
   exposes, and how we'd fix them *in Brood* (`../brood` — kernel primitive or
   `std/` module) rather than working around them here. This part comes first
   because it's the prime directive: if a core abstraction is missing, we improve
   the language before building on it. If a plan has nothing here, say so
   explicitly — "no language gap; builds on existing primitives" — so it's clear
   the question was asked, not skipped.
2. **What we will do.** The concrete editor work in myedit, built on the
   primitives from part 1 (and existing ones): the files, the order, the tests.

Keep the two separate so the language improvement never gets buried inside the
feature work — surfacing it is half the point of this project.

## Layout

```
src/main.blsp               entry point — window / daemon startup (--serve/--attach), runs the ui-run loop
src/model.blsp              the ui-run model: buffer pool, kill ring, minibuffer, *Messages*, scrolling
src/config.blsp             ~/.config/brood-edit/init.blsp — the declarative user config (data, not eval'd)
src/theme.blsp              every colour the editor paints (Catppuccin Mocha), referenced by role
src/panes.blsp              pane-layout geometry + mouse-event folding (model -> model)
src/view.blsp               pure view: model -> render frame (editor/display ops)
src/statusbar.blsp          the mode line as extensible segments (render ops + click/hover zones in one pass)
src/input.blsp              dispatch: fold a key/mouse/tick event into the next model
src/commands.blsp           the editing commands, each a (model key) -> model
src/keymaps.blsp            keybinding profiles (emacs / modal vim) as model-scope layers
src/interactive.blsp        the `defcommand` macro + the M-x command registry
src/modes.blsp              modes as layers: the keymaps (data) + brood-mode services
src/complete-at-point.blsp  completion-at-point (the in-buffer Tab popup) — multi-source merge
                            (named to dodge std's `tool/complete`, which shadows a bare `complete`)
src/lsp.blsp                LSP client (proc-spawn + JSON-RPC) — completion, goto-def/references, hover, rename, format, imenu
src/lsp-requests.blsp       the LSP request-kind records + `LspRequest` ability — the shape/fold vocabulary
                            shared by lsp (connection side) and commands (model side); eager-loaded so
                            commands can register fold impls while lsp stays deferred
src/mincomplete.blsp        minibuffer prompt completion (path / name)
src/completion.blsp         shared fuzzy ranking + vertical-menu card + ls -l perms (complete + plume + dired)
src/plume.blsp              the minibuffer completion UI — vertical list + marginalia + N/M counter (our Vertico/Marginalia)
src/debugger.blsp           the editor as the debugger (ADR-174/184): C-c d session, *Spy* trace
                            stream, *Debug* paused-process queue with resume/eval-in-scope,
                            trace-fn/break-fn by name — the collector process speaks std/debug's
                            wire protocol and forwards UiEvent records to the loop
src/isearch.blsp            incremental search + query-replace (C-s/C-r/M-%) modal mini-loops
src/eval-command.blsp       eval Brood source from a buffer (the C-x C-e core)
src/compile.blsp            M-x compile: run a build in the project root, C-x ` next-error
src/projects.blsp           project root + file walk (find-file-in-project)
src/bshell.blsp             per-project shell + Brood REPL buffer (C-x p e)
src/git.blsp                git porcelain: C-x g status buffer, diff/log/commit, C-x v = vc-diff
src/gitdiff.blsp            diff-hl change gutter: per-line added/modified/deleted vs HEAD
src/web.blsp                live HTTP mirror of the selected buffer (C-x w)
src/remote.blsp             --serve / --attach / --listen: the daemon/emacsclient model over node links
src/collab.blsp             shared-buffer collaboration: presence carets, delta merges, follow/mirror
tests/*_test.blsp           pure model/view tests, one suite per area (no window needed)
project.blsp                the nest manifest (:name "myedit")
```

## Commands

This project consumes the **installed** `nest` (`~/.local/bin/nest`), which must
be built with the GUI backend. Building it lives in the Brood repo:

```bash
# in ../brood — install a GUI-enabled nest (heavy deps, one-time):
./configure --with-gui && make install

# here:
nest run                 # open the editor on a scratch buffer (native window)
nest run -- notes.txt    # open (Ctrl-S saves) that file
nest test                # run the test suite (~5s, 829 tests)
nest test tests/git_test.blsp:42     # one file, or the one test at that line
nest test --failed       # just what failed last run — the edit/rerun loop
nest test --cover        # function-level coverage: what the suite never calls
nest test --repeat-until-failure 5 --seed 0   # shake out a flaky/order-dependent test
nest check               # advisory type/lint check
```

**Verify the GUI only via the installed `nest`** (or a `cargo build --features
brood/gui` in ../brood). A plain `cargo run -p nest -- test` rebuilds
`target/debug/nest` *without* the GUI feature and clobbers the installed binary's
counterpart — it won't reflect the windowed build.

**Don't run `nest format` here.** It reformats all ~55 files and hoists every
trailing `; comment` onto its own line above the form — this codebase documents
`(:use …)` clauses and assertions with trailing comments deliberately, so the
formatter's output is a large, lossy diff. Reformatting is a decision to take
explicitly, not a side effect of a change.

**Process tests use barriers, not sleeps.** `buffer-query` (and any other
synchronous call) is a FIFO round-trip: when it returns, every message the test
sent that process has been handled and every push it triggered is already queued.
`ct-settle`/`ht-settle` in `tests/collab_test.blsp` / `tests/hosted_test.blsp` are
that barrier — drain with `(after 0 …)` behind one, and assert "nothing was
pushed" *strictly* instead of racing a timeout. Only an event routed through a
third process (the collab registry learning of a `[:down]`) needs waiting, and
that polls (`ct-await-respawn`) rather than guessing a delay.

## Conventions

- **Write the editor in Brood.** Read `../brood/docs/brood-for-claude.md` and load
  the `writing-brood` skill before writing `.blsp` — Brood is immutable (no
  mutation, no loops; state is a process or a rope handle; iterate with
  tail-recursion / `fold`). Lists for code, vectors for data.
- **Commands are `model -> model`.** Keys dispatch through a `std/keymap.blsp`
  keymap to command *symbols* resolved at dispatch time, so a command redefined
  at runtime hot-swaps live — that late binding is the road to a self-editing
  editor. Keep `view` pure; thread all state through the `ui-run` model.
- **Refactor as you go.** After each step (a command, a service, a feature), pause
  and look for refactoring opportunities in what you just touched *and* what it
  builds on: duplication to fold into a helper, a one-off that wants to be a shared
  primitive, a clearer name, dead code to delete. Prefer pulling the shared shape up
  (often into a `std/` module — the prime directive) over copy-paste. Make the
  cleanup a small, separate step; don't let it balloon the feature.
- **No Claude/AI co-author trailer on commits** (matches the Brood repo).
- Commit/push only when asked.
