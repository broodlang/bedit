# CLAUDE.md — working in the bedit repo

Guidance for Claude Code (and humans) working in this project. For the machine
setup (Ubuntu, apt, Rust via rustup, etc.) see the global `~/.claude/CLAUDE.md`.

## What this project is

**bedit is an Emacs clone, written in [Brood](../brood).** Brood is a small,
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
capability into bedit as a one-off workaround.

This is not a detour from building the editor — it *is* building the editor. A
self-editing Emacs clone is only possible if its abstractions live in a language
expressive enough to host them. **Be actively on the lookout for these** — treat "bedit
wants X and can't express it cleanly" as a signal to improve Brood, and say so.

**A capability, not a feature.** The gap has to be one the *language* has: a
primitive, a protocol, a mechanism that bedit cannot express without it. A feature
built from capabilities Brood already has belongs in bedit, however reusable it
looks: Org-mode, Magit's transient menus and section trees, form buffers, the format
highlighters and the mail parser all started in Brood's std and moved here (brood
ADR-417). A std module has to pass three questions:

1. Is it a mechanism rather than a feature?
2. Would something besides bedit use it (Brood's REPL, the observer, `nest`, the eval
   server, a program that is not an editor)?
3. Does it have to version with the kernel?

If it fails 1 and 2, it lives in bedit. If other projects would want it but it fails 3
(a file format's highlighter, a mail parser), it is a hive package.

**Worked example (the live one).** Eval-in-buffer (`C-x C-e`: eval the form
before point, show its output in the `*Messages*` buffer) needs to *capture*
what the evaluated code prints. Brood has no output capture today — `print`/
`println` write straight to stdout (`crates/lisp/src/introspect.rs` flags the
missing `*out*` dynvar + `with-out-str` facility explicitly). The wrong fix is
to intercept output inside bedit. The right fix is to **add `*out*` +
`with-out-str` to Brood** — a general capability (REPL capture, test output
assertions, the MCP `EvalResult.stdout` field all want it) — and then have
bedit's eval command simply `(with-out-str …)`.

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
   the question was asked, not skipped. A proposed std module names the caller
   besides bedit that needs it; without one, it is part 2 work.
2. **What we will do.** The concrete editor work in bedit, built on the
   primitives from part 1 (and existing ones): the files, the order, the tests.

Keep the two separate so the language improvement never gets buried inside the
feature work — surfacing it is half the point of this project.

## Layout

**The full map, one entry per module, is [docs/layout.md](docs/layout.md)** — read the entry
for a module before changing it. A new `src/` module gets its entry THERE
(`tests/layout_doc_test.blsp` enforces it); this section stays a list of families, one line each.
Never add module detail here: it is loaded into every session.

| Family | Modules (`src/`) |
|---|---|
| startup + loop | `main` `startup` `model` (the registries every feature plugs into) `input` `events` `lifeline` `offloop` |
| text model | `textpos` `bufferops` `wrap` `inlinetext` `folds` `codefold` `stringstate` `stringlex` `stringwarm` `conventions` `editorconfig` `dirlocals` |
| view | `view` `panes` `panegeometry` `panebody` `spanpaint` `spancache` `syntaxtree` `linecache` `treewarm` `modeline` `statusbar` `headerline` `echoarea` `hittest` `overlayview` `ui-kit` `theme` `themes` `systemtheme` `appearance` `scrollbar` `scroll` `eolview` `eolnotes` `linkview` `foldview` `gutter` |
| decorations | `whitespace` `fillindicator` `glyphless` `rainbow` `pulse` `spell` `diffhl` `codecrumbs` `tsbrackets` |
| commands | `commands` `motion` `structural` `indent` `typing` `killing` `editing` `region` `textops` `comment` `fill` `electric` `kmacro` `registers` `window-commands` `search-commands` `isearch` `query-replace` `avy` `embark` `menu` `mouse` `clipboard` `browse-kill-ring` `yankmedia` |
| keys + modes | `keymaps` `vim` `userkeys` `interactive` `transient` `transient-core` `whichkey` `keyhelp` `help` `modes` `brood-mode` `lisp-modes` `lang-*` `language-core` `lex-*` `org` `org-mode` `mail` `mail-message` |
| minibuffer + completion | `minibuffer` `lossage` `mincomplete` `filename` `completion` `plume` `complete-*` `cape` `snippet` `savehist` `passwd` |
| files | `pool` `file-save` `lifecycle` `autosave` `backup` `sidecar` `autorevert` `recover` `charset` `charset-tables` `filecoding` `hexl` `imageview` `docview` `sudoedit` `remotejob` `ssh*` `dired` `wdired` `fileops` `fileperm` `lastsession` `saveplace` `reopen` `solong` `sibling` `thingatpt` |
| config + packages | `config-paths` `config` `display-rules` `hooks` `ownership` `package-*` `packages` `grammars` `grammarcheck` `about` `bugreport` `slowlog` `turnprofile` |
| projects + build | `projects` `project-commands` `project-search` `toolchain` `compile` `results` `formatter` `xrefgrep` `projectdiag` `editspans` `searchedit` `testrun*` `testadapter` `brood-test` `elixir-test` `apprun` |
| diagnostics + LSP | `diagstore` `diagcheck` `diagnostics` `eldoc` `lsp*` |
| eval + playgrounds | `eval-command(s)` `shell-command` `sandbox` `sandbox-events` `session` `liveeval` `playground-core` `playground` `elixir-*` `tutor*` `aside` `workings` `mdpreview` `debugger` `beam` `process-list` `attach` |
| processes | `procstream` `ansicolor` `comint` `bshell` `terminal` `formbuf` |
| VCS | `vcscore` `vcsproc` `diffpaint` `section` `sectionbuf` `git*` `mur*` `timemachine` `smerge` |
| multi-frame + remote | `hosted` `frames` `tabbar` `winner` `remote` `guest` `collab*` `web` |
| tests + tools | `tests/support/testkit.blsp` (shared helpers), `tests/guards_test` `tests/strict_ratchet_test` `tests/layout_doc_test`, `tools/drive-*.blsp` (live pty drivers), `tools/screenshot.blsp`, `tools/affected-tests.sh`, `tools/ci/*` |

## Commands

This project consumes the **installed** `nest` (`~/.local/bin/nest`), which must
be built with the GUI backend. Building it lives in the Brood repo:

```bash
# in ../brood — install a GUI-enabled nest (heavy deps, one-time):
./configure --with-gui && make install

# here:
nest run                 # open the editor on a scratch buffer (native window)
nest run -- notes.txt    # open (Ctrl-S saves) that file
nest test                # run the test suite (~3s, 900+ tests)
nest test tests/git_test.blsp:42     # one file, or the one test at that line
nest test --failed       # just what failed last run — the edit/rerun loop
nest test --cover        # function-level coverage: what the suite never calls
nest test --repeat-until-failure 5 --seed 0   # shake out a flaky/order-dependent test
nest check               # advisory type/lint check
nest eval --test '(config-paths/config-dir)'   # ask the code a question, as a test sees it (below)
nest eval --test --in linkview '(ed-hovered-text-link {} {} {})'   # inside a module: its private names
make drive               # live pty drivers: the real editor, driven (tools/README.md)
tools/affected-tests.sh --run   # every test file the change reaches, one at a time (the pre-push sweep)
```

**Ask the code with `nest eval`, never a probe file.** To learn what a function answers or what
shape a value has, `nest eval 'EXPR'` evaluates it with the project loaded and prints the value.
`--in MODULE` evaluates inside a module, its private names and imports bare. `--test` runs it
as a test sees the world: `test/running?`, and a scratch home, so nothing touches
`~/.config/bedit`. `-` reads several forms from stdin (`nest eval - <<'EOF' … EOF`). Never
write a throwaway `tests/zz_probe_test.blsp`: other sessions' `nest test` and `nest check`
read the tree while you work, and trip on a file that appears and vanishes.

**Verify the GUI only via the installed `nest`** (or a `cargo build --features
brood/gui` in ../brood). A plain `cargo run -p nest -- test` rebuilds
`target/debug/nest` *without* the GUI feature and clobbers the installed binary's
counterpart — it won't reflect the windowed build.

**CI builds brood's `last-green`, not `main`** — the newest brood commit whose own CI passed
every job (brood's ci.yml advances the branch). A bedit change that needs a new brood name is
pushed after brood's run for that commit is green, or bedit's CI reports it unbound.

**The tree is `nest format`-clean, and CI enforces it** (`nest format --check`). Run
`nest format --changed` before committing — the whole tree was reformatted once, on
2026-09-23, after the check had kept CI red for a day. The formatter keeps a trailing
`; comment` on a `(:use …)` clause or a simple form, but moves one off a `cond` clause or
out of a vector/map literal onto its own line — so write those comments above the form.

**Process tests use barriers, not sleeps.** `buffer-query` (and any other
synchronous call) is a FIFO round-trip: when it returns, every message the test
sent that process has been handled and every push it triggered is already queued.
`ct-settle`/`ht-settle` in `tests/collab_test.blsp` / `tests/hosted_test.blsp` are
that barrier — drain with `(after 0 …)` behind one, and assert "nothing was
pushed" *strictly* instead of racing a timeout. Only an event routed through a
third process (the collab registry learning of a `[:down]`) needs waiting, and
that polls (`ct-await-respawn`) rather than guessing a delay.

**A test never touches the user's own config.** Every file the editor keeps lives under
`config-paths/config-dir`, which follows `$XDG_CONFIG_HOME` — and a test run points that at a
scratch home of the run's own (brood ADR-602; `test/running?`, `test/scratch-dir`, which
bedit reads as `config-paths/under-test?`). That holds for `nest test` and for C-c t from inside
the editor: both of its runners start their child with `sandbox/*test-runner-env*`
(`BROOD_TEST_ARM=1`, brood ADR-608) — the cold runner's `nest run` and the warm test child —
so the child arms before any test code loads; a new runner that runs tests must do the same
(`tests/testrun_test.blsp` "a C-c t run gets a scratch home"). The REPL's history
(`BROOD_HISTORY`) goes to the scratch home too. `persist-write!` and `ensure-init!` also
refuse a path under the real `~/.config/bedit` while a test runs (compared normalized; a test
of the guard binds `config-paths/*user-config-base*` to a stand-in). A new
kind of persisted file goes under `config-dir` (or `editor-state-dir`), never `$HOME`
directly; a test that wants its own file binds the module's dynvar (`*config-base*`,
`bshell/*bshell-history-file*`).

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
