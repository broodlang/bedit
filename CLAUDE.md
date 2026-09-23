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
expressive enough to host them. Every gap the editor exposes is a gap in Brood
worth fixing properly. **Be actively on the lookout for these** — treat "bedit
wants X and can't express it cleanly" as a signal to improve Brood, and say so.

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
   the question was asked, not skipped.
2. **What we will do.** The concrete editor work in bedit, built on the
   primitives from part 1 (and existing ones): the files, the order, the tests.

Keep the two separate so the language improvement never gets buried inside the
feature work — surfacing it is half the point of this project.

## Layout

```
src/main.blsp               entry point — window / daemon startup (--serve/--attach), runs the ui-run loop
src/model.blsp              the ui-run model: buffer pool, kill ring, minibuffer, *Messages*, scrolling
src/config.blsp             ~/.config/bedit/init.blsp — the declarative user config (data, not eval'd)
src/about.blsp              M-x version · --version · C-h C-a *About bedit* — bedit's version,
                            the brood under it and the build date, all from project-release/build-info
                            (named to dodge std's `version`, whose `version/newer?` packages uses)
src/theme.blsp              every colour the editor paints (Catppuccin Mocha), referenced by role
src/themes.blsp             the theme registry (M-x theme-select): a live picker that swaps the
                            whole palette AND the window font — a theme is a plain map, so
                            adding one is data (theme.blsp is the palette; this is the registry)
src/packages.blsp           bedit's package manager (M-x package-list): install / update / remove
                            hive packages that `:enhances bedit` at RUNTIME, into
                            ~/.config/bedit/packages (the elpa model) — never the build's _deps
src/panes.blsp              pane-layout geometry + mouse-event folding (model -> model)
src/view.blsp               pure view: model -> render frame (editor/display ops)
src/statusbar.blsp          the mode line as extensible segments (render ops + click/hover zones in one pass)
src/ui-kit.blsp             the widget kit over editor/display: a widget is `(area ctx) ->
                            {:ops :zones}` — paint and hit-test in ONE pass, styled by semantic
                            role. The shared shape behind the context menu, popup, plume, which-key
src/input.blsp              dispatch: fold a key/mouse/tick event into the next model
src/commands.blsp           the editing commands, each a (model key) -> model
src/keymaps.blsp            keybinding profiles (emacs / modal vim) as model-scope layers
src/interactive.blsp        the `defcommand` macro + the M-x command registry
src/transient.blsp          TRANSIENT MENUS (magit's `P`): the editor half of std's
                            `editor/transient` (brood ADR-387) — the modal overlay, the
                            minibuffer read behind a `:read` outcome, and the MEMORY (a
                            menu reopens with the arguments it had last time, in
                            state/transients.blsp). A command invoked from a menu reads
                            its flags with `ed-transient-args` and cannot tell it was
                            reached from one. A keymap has nowhere to put a FLAG, which
                            is why `--force-with-lease` was untypeable before this
src/modes.blsp              modes as layers: the keymaps (data) + brood-mode services.
                            `deflanguage` declares a tree-sitter language from ONE spec
                            (faces, indent, heredocs, formatter) and generates its whole
                            service set — checked against
                            editor/treesit/language-contract, so an incomplete language
                            fails at load rather than at the keypress that needed it
src/grammars.blsp           M-x grammar-list / grammar-reload: what tree-sitter grammars
                            are installed (ABI, path), the recipe to build one, and a live
                            swap — drop a new .so in and reload, no restart
src/format.blsp             M-x format-buffer + format-on-save: the language's own
                            formatter (mix format, black, rubocop), declared per language
                            and run over the FILE, so a failing formatter costs nothing
src/complete-at-point.blsp  completion-at-point (the in-buffer Tab popup) — multi-source merge
                            (named to dodge std's `tool/complete`, which shadows a bare `complete`)
src/lsp.blsp                LSP client (proc-spawn + JSON-RPC) — completion, goto-def/references,
                            hover, rename, format, imenu, and `publishDiagnostics` folded into
                            the model's diagnostics, so every language gets the underline / ⚠ note
                            / gutter mark the Brood checker used to have to itself. Answers
                            server->client requests too (`client/registerCapability` — a server
                            BLOCKS on that reply) and starts the server IN the project root, which
                            is how one that builds the project finds it. Elixir is Expert
                            (expert-lsp.org), which narrates its own startup — forwarded to
                            *Messages*, because it answers nothing until its engine is up
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
src/testrun.blsp            native test runs (C-c t): a dedicated nest subprocess streams per-test
                            JSON (std's *test-report-sink*) into the *Tests* buffer — never
                            in-image (%isolate would revert the editor's globals + kill its pids).
                            A project with a WARM test session uses it instead (`*warm-backends*`,
                            one row per language: Elixir's `MIX_ENV=test` node, Brood's
                            eval-server child) — same rows, same marks, without the runtime
                            start. A warm run RECOMPILES / RELOADS what changed first, so it
                            never reports on the code the session booted with, and says so
                            when it had to. The cold path stays and is never slower: a run
                            with no warm session uses it AND starts one
src/session.blsp            ONE event vocabulary for every evalsession the editor keeps
                            (`session-ready` / `session-reply` / `session-down`, each carrying
                            the session's NAME) plus the shared emit and client API. Each
                            backend used to carry its own three records and its own emit
                            purely so the router could tell whose event it was — a fact the
                            session already knows, and now says
src/brood-test.blsp         C-c t in a Brood project without the project load: an eval-server
                            child answering `:test` / `:teststop`, streaming per-test
                            verdicts AND the spy entries a test traces.
                            Measured here — 1.21s cold (435ms of it loading sixty modules)
                            against ~200ms warm, and it reloads changed src/ per run
                            (project/reload-changed), so it is never stale
src/apprun.blsp             run the project (C-c r): nest run in a subprocess with debug taps —
                            app output + spy/trace traffic into *Run*; live stats on a statusbar chip
src/hosted.blsp             THE FLIP: every pool buffer backed by its own process (hosted-reconcile)
src/frames.blsp             frames (C-x 5 2 / o / 0): a second OS window is a PROCESS with its own
                            ui-run whose pool slots link to the same buffer processes, named by
                            std/editor/buffer-registry — a buffer opened, edited or killed in one
                            frame is in every frame (docs/frames-plan.md)
src/procstream.blsp         the shared streaming-subprocess worker (testrun's :testrun and
                            apprun's :apprun ride it): line-buffered stdout -> handler fns
src/wrap.blsp              visual-line-mode: the pure break rule (a line → `[from to]` row
                            segments, word-wrapped at the pane width) that the row↔line owner
                            (panes), the view and the scroll clamp all read — markdown wraps
                            by default (a `:visual-line` mode facet); M-x visual-line-mode toggles
src/isearch.blsp            incremental search + query-replace (C-s/C-r/M-%) modal mini-loops
src/eval-command.blsp       eval Brood source from a buffer (the C-x C-e core)
src/sandbox.blsp            the Brood eval session's BACKEND over std's `editor/evalsession`:
                            find a runtime, start it on a generated eval-server script
                            (ADR-198), the pr-str-line codec, and session events -> UiEvent
                            records. The supervision (queue-until-ready, id-matched replies,
                            the watchdog, strikes, respawn) is std's and shared with Elixir
src/liveeval.blsp           the live-evaluating buffer as a VOCABULARY, shared by tutor +
                            playground: parse-state, result/type/timing notes, spy cascade
src/sandbox-events.blsp     routes the shared sandbox's UiEvents to every client that wants
                            them (an `impl` is per record type, so one client can't own them)
src/playground-core.blsp    the live-evaluating buffer as a MECHANISM, parameterised by a
                            language spec: form diffing, the marker-anchored notes, the
                            launch plan, the reply fold, the pane following the cursor —
                            everything about a playground that is not about a language
src/playground.blsp         M-x brood-playground: a free-text Brood buffer that runs as you
                            type — results as ghost text, *Playground Spy* pane beside it
                            (the Brood half of playground-core: how Brood text splits into
                            forms, what its deps are, where to send one)
src/elixir-sandbox.blsp     the Elixir session: one `mix run` child (the project COMPILED and
                            STARTED, so the playground can call your contexts and hit your
                            Repo), supervised by std's `editor/evalsession`, speaking a
                            base64/JSON line protocol to `elixir/bedit_agent.exs`
src/elixir-playground.blsp  M-x elixir-playground (C-c p e): the second client of
                            playground-core — tree-sitter form splitting,
                            `editor/treesit/parse-state` for mid-typing vs broken, a
                            defmodule/binding dependency rule, and the term's type as the
                            hint (the BEAM computes it; no checker can)
src/elixir-test.blsp        C-c t without the VM boot: a SECOND agent, booted
                            `MIX_ENV=test mix run` (`:dev` and `:test` are different
                            environments — different config, different database, an Ecto
                            sandbox in only one), answering `TEST` by requiring the named
                            files and calling `ExUnit.run/1`. Verdicts stream back one per
                            test (evalsession's `:more` replies) into the same *Tests*
                            buffer the cold runner fills. The cold path stays and is never
                            slower: a run with no warm node uses it AND starts one
elixir/bedit_agent.exs      bedit's agent ON the BEAM: a session (binding + modules across
                            requests), IO capture, per-request timeout, `:erlang.trace`
                            over the modules the SESSION defined (the spy cascade), and the
                            ExUnit formatter that streams a warm run's verdicts. An
                            ordinary .exs file, spliced in by `include-str` at compile time
                            because a release bundle carries code and no assets (ADR-038).
                            Needs Elixir 1.14+ (`dbg/2`'s `:dbg_callback`); below that it
                            still evaluates and says so once (`elixir-sandbox/version-notice`)
src/tutor.blsp              the interactive Brood tutorial (C-h t): playground boxes that
                            eval-on-type in the sandbox — ✓/✗ gutter, ghost results, prose guard
src/aside.blsp              the ASIDE pane: a named buffer shown beside the page, refreshed in
                            place, latched closed once the reader closes it, reopened only by
                            asking — the discipline under every preview pane (workings, mdpreview)
src/workings.blsp           the "show me how it actually ran" pane over `aside`: the per-region
                            report cache and the rule for what earns a split — the tutorial's
                            *Workings* and the playground's *Playground Spy* are its two clients
src/mdpreview.blsp          C-c C-p in a .md buffer: the document rendered beside it
                            (std's `markdown-render`, faces as data on the buffer), following
                            the cursor per key and re-rendering on the idle beat (`:on-idle`)
src/tutor-workings.blsp     the tutorial's *Workings* pane: the per-box cascade cache, its body
                            text, and its open/follow/close (knows a pane + a box INDEX; the
                            tutorial owns the box parser and passes the index — acyclic)
src/tutor-lessons.blsp      the tutorial's CONTENT only — the lessons vector (grow the course here)
src/toolchain.blsp          the project TYPE as data: marker file -> which commands compile,
                            test, run and REPL here (mix / nest / cargo / npm / go / make),
                            and which tasks it can list. projects.blsp derives its root
                            markers from this table, so a language is ONE edit
src/results.blsp            the results-buffer abstraction behind *Tests* / *Run* / *compilation* /
                            *Occur* / *git-status*: the `file:line[:col]` location vocabulary, the
                            `location-jump-layer` that makes every such row navigable, and
                            `ed-append-follow` — the streaming append that follows the tail
                            only in a pane already at the bottom
src/testadapter.blsp        one result vocabulary, two runners: Brood's structured
                            *test-report-sink* lines and ExUnit's `mix test --trace` text
                            both decode into the same {:group :name :passed :where …}, so
                            C-c t means the same thing in every project
src/compile.blsp            M-x compile: run a build in the project root, C-x ` next-error,
                            M-x project-task (mix tasks / npm scripts). The error locations
                            are an Emacs-style regexp TABLE (`*error-patterns*`), which
                            needed brood's regex captures to be expressible at all
src/projects.blsp           project root + file walk (find-file-in-project)
src/bshell.blsp             per-project shell + Brood REPL buffer (C-x p e): a line
                            typed at bedit's own prompt runs as `sh -c` (pipes, output
                            stripped) or, starting with `(`, evaluates as Brood in the
                            worker; owns the input-region vocabulary (`:input-start`, the
                            boundary guard, ↑/↓/C-r history) that a line-mode terminal
                            reuses
src/term.blsp               a TERMINAL buffer (C-x p t, C-x p r, M-x claude, C-u M-x term):
                            a program under a pty, its screen emulated by std/vt
                            (brood ADR-384) in the buffer's worker and painted into the
                            buffer's tail. CHAR mode (a full-screen program: claude,
                            htop, vim): every key goes to it (input/term-overlay); C-x
                            stays the editor's, C-y pastes, C-x c is the C-c map, C-x C-x /
                            C-x C-y send the literal. LINE mode (the project REPL: iex -S
                            mix, nest repl): the input after the program's prompt is
                            bedit's, with bshell's history and boundary keys, RET sends
                            it — C-c C-j / C-c C-k switch. The mouse reaches a program
                            that asked for it; the program's cursor shape and visibility
                            are painted; history above the screen keeps its colour and
                            is capped; the mode line chip says which program and mode
src/sectionbuf.blsp         the SECTION BUFFER: a read-only buffer whose text is a
                            std/editor/section tree (brood ADR-388) — tree, rows and
                            visibility live ON THE BUFFER, faces come from the mode's
                            `:section-faces` service as data (`:face-spans`), and TAB · n/p ·
                            ^ · M-n/M-p · 1-4 · M-w are shared by every such buffer. A lazy
                            section (a status file whose diff was never fetched) asks the
                            mode's `:section-reload`
src/git.blsp                git porcelain, Magit's: C-x g *git-status* is a section tree —
                            in-progress line, Head:/Merge:/Push:/Tag:, Unmerged / Untracked /
                            Unstaged / Staged files (TAB fetches a file's hunks), unpushed,
                            unpulled, stashes, recent commits; one blank line between
                            sections and nothing indented. s/u/k act on what is at point: a
                            REGION of a hunk's lines (std/diff `hunk-select`), a hunk, a file,
                            several files, a whole list, a stash; k on a conflict offers
                            ours/theirs, e opens it at its first marker (smerge). RET goes to
                            the line a diff line became. `$` is the PROCESS LOG (magit's
                            `magit-process-buffer`) — every command, exit code, duration and
                            output; one logged seam (`git-run` / `git-run-hunk`, `git-do` to
                            refresh after), credentials redacted, `\r` progress applied
src/git.blsp (cont.)        every Magit menu on Magit's letter, each a transient of flags:
                            c commit (extend · reword · amend · fixup · squash · instant
                            fixup/squash; off the loop, the staged diff beside the message,
                            M-p/M-n message history, a failed commit keeps its draft) · b
                            branch (a remote branch checks out as a tracking local one;
                            create from a start point, spin off, upstream, reset, delete
                            asking before -D) · P push (where it pushes / upstream /
                            elsewhere / another branch / tags; a branch with nowhere to go
                            is asked and remembers) · F pull · f fetch · m merge (+preview) ·
                            r rebase (interactive from the commit at point, and reword /
                            modify / remove ONE commit, autosquash — a plan handed to git as
                            `sequence.editor=cp <file>`, so no editor ever opens) · A · V ·
                            X (mixed/soft/hard/keep, index, worktree, file) · z (at point) ·
                            t · M · B bisect · % worktrees · W/w patches · o submodules · T
                            notes · i ignore · K untrack · R rename · j jump · ? all of them.
                            The SEQUENCER is one idea not five: git records which operation is
                            half-done in .git, so one continue/skip/abort dispatches on it
src/gitview.blsp            the git VIEWS, section buffers acted on in place: *git-revision*
                            (a commit's message then files and hunks — RET to a line, a applies
                            a hunk, v reverses it), *git-diff* (s/u/k as in the status, + / -
                            context), *git-log* (graph, refs, author/age margin; RET shows,
                            SPC peeks, + doubles; A/V/X/r i act on the commit at point), the
                            reflog, *git-blame* (chunks per commit; b blames the version
                            before), *git-refs* (y), a file at a revision and C-c g p / n to
                            step through its history
src/smerge.blsp             conflicts resolved IN the file, Emacs's smerge: C-c ^ n/p between
                            conflicts, u/l/a/b keep upper / lower / both / base
src/gitdiff.blsp            diff-hl change gutter: per-line added/modified/deleted vs HEAD
src/beam.blsp               the BEAM, from the editor. C-c b p processes · C-c b s the SUPERVISION
                            TREE (indented by depth, supervisors marked) · C-c b e ETS
                            (biggest first — where the memory went) · C-c b t trace a named
                            function into *BEAM Spy* · C-c b B BREAK on one (suspends the
                            caller; *BEAM Debug* lists it, `r` resumes) · C-c b a/d attach.
                            Three observations and a debugger over one `*views*` table and
                            one session, so a fourth is a row rather than new plumbing.
                            M-x beam-processes (C-c b p): every process in
                            the node your app runs in (name, mailbox, memory, reductions/sec,
                            current function), busiest first, `g` refresh `k` kill, over the
                            SAME agent the playground evaluates in. C-c b a ATTACHES that
                            agent to a node bedit did not start (`Node.connect/1`, then
                            `:erpc` for every eval and observation) — node typed not
                            discovered, cookie asked for not assumed, and the mode line
                            names the node the whole time, because the risk is forgetting
src/web.blsp                live HTTP mirror of the selected buffer (C-x w)
src/remote.blsp             --serve / --attach / --listen: the daemon/emacsclient model over node links
src/collab.blsp             shared-buffer collaboration: presence carets, delta merges, follow/mirror
tests/*_test.blsp           pure model/view tests, one suite per area (no window needed)
tests/strict_ratchet_test   the `nest check --strict` ceiling: the count may only shrink —
                            a new function that adds a finding declares its contract instead
tools/drive-*.blsp          live drivers: run the real editor over a pty (std/vt reads what it
                            paints) or its own ui-run loop, and assert — the wiring the model
                            tests can't see (`make drive`, tools/README.md)
assets/                     the desktop identity: the icon (SVG) + the .desktop entry the
                            window's `:app-id` is matched against (`make install` places both)
project.blsp                the nest manifest (:name "bedit")
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
nest test                # run the test suite (~3s, 900+ tests)
nest test tests/git_test.blsp:42     # one file, or the one test at that line
nest test --failed       # just what failed last run — the edit/rerun loop
nest test --cover        # function-level coverage: what the suite never calls
nest test --repeat-until-failure 5 --seed 0   # shake out a flaky/order-dependent test
nest check               # advisory type/lint check
make drive               # live pty drivers: the real editor, driven (tools/README.md)
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
