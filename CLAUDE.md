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

```
src/main.blsp               entry point — window / daemon startup (--serve/--attach), runs the ui-run loop
src/model.blsp              the ui-run model: buffer pool, panes, kill ring, minibuffer, *Messages*,
                            the timers — and the REGISTRIES the rest plugs into: idle-beat jobs
                            (`register-idle-job`), off-loop task replies, inbound `[:tag …]`
                            event handlers, feature timers, process deaths
                            (`register-down-handler`). The core names no feature: a
                            module registers its rows when it loads
src/keyhelp.blsp            key / command LABELS for help text: `C-x C-e` spellings, where-is
                            over the live keymap, `\[command]` substitution, docstrings
src/scroll.blsp             keeping point on screen: the scroll-margin clamp, horizontal scroll,
                            `ed-max-top`, and the snap that ends a glide on a line; in a
                            row-wise (wrapped) buffer the pane starts on a screen ROW of its top
                            line (`:top-row`, `[line row]`) and the clamp, C-v / M-v and C-l move
                            it by rows, as Emacs's window-start is a screen line — and the
                            LONG-LINES policy (`ed-long-lines`): :wrap / :truncate / :scroll per
                            buffer and per line — the buffer's toggle (M-x toggle-truncate-lines,
                            visual-line-mode), the `:long-lines` setting for its mode, the line's
                            KIND (`:line-kinds`: a section heading truncates, its body wraps),
                            the mode's `:long-lines` facet, the setting's `:default`
src/autosave.blsp           `#file#` auto-save sidecars + auto-revert of files changed on disk
                            (idle-beat jobs)
src/diagcheck.blsp          the advisory diagnostics CHECK, off the loop on the idle beat — in
                            the sandbox child for a brood buffer (its own session client), an
                            in-image task otherwise; folds into the model's diagnostics cache
src/eldoc.blsp              the idle beat's point-driven hints: the eldoc line (off the loop),
                            when an LSP signature hint is due, the inline completion preview
src/treewarm.blsp           a large tree-sitter buffer's parse warmed off the loop, so the first
                            structural query does not pay for it on a keypress — and its held
                            tree (syntaxtree) opened in the task and handed back
src/syntaxtree.blsp         the tree-sitter parse each pool buffer KEEPS (brood ADR-443):
                            `:syntax-trees` by pool index, updated incrementally per edit by the
                            span refresh, freed on kill; panes colour a band from it
                            (`fontify-tree`, with the mode's injections) and keep a band its
                            `tree-changes` left alone. A
                            runtime without tree handles keeps the slice path. Past
                            `*tree-sync-max*` (250 KB) the update runs OFF the loop, one in
                            flight, coalescing a burst; meanwhile the band is carried (spans
                            shifted past the edits) and a structural key catches the tree up once
src/linecache.blsp          the line-state highlight cache a LEXER mode keeps (brood ADR-471):
                            a mode's `:line-lexer` builder (markdown's fence, org's #+BEGIN_
                            block, the `lex-*` formats stateless), `:line-caches` by pool index,
                            threaded by the span refresh, dropped on kill; an edit re-lexes the
                            lines it touched, exact at any depth — no lead-in, no restart. A
                            mode's `:line-band-pass` then sees the band: what spans lines, as
                            markdown's fences coloured as their language (brood ADR-489)
src/config.blsp             ~/.config/bedit/init.blsp — the declarative user config (data, not eval'd).
                            Every key is ONE `settings/define` (std `settings`, brood ADR-428):
                            its default, type and doc give the check, the fallback
                            (`config/setting`) and the generated default file. A package
                            declares its own under `:bedit/settings`
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
src/panes.blsp              pane-layout geometry + mouse-event folding (model -> model); the
                            row table every row↔line question reads (`ed-pane-rows`), from the
                            pane's start row
src/view.blsp               pure view: model -> render frame (editor/display ops). Names no
                            feature: a pane body's layers share ONE geometry map, and the
                            mode line's feature chips come from the statusbar registry
src/hittest.blsp            the mouse side of the view: every hit-test / hover fold that takes
                            a model and returns one (:hover, :diag-hover, :link-hover, a chip
                            click, the context menu's hit) — recomputed from the same widget /
                            segments / layout the view drew, so input never imports the renderer
src/headerline.blsp         the HEADER LINE above each pane (Emacs breadcrumb-mode, on with `:header-line`):
                            the file by its project and path, then the mode's `:breadcrumbs` at point
                            (an Org heading's path); the layout takes the pane's top row for it
                            (`panes/ed-header-layout`), so nothing below knows it is there
src/pulse.blsp              a flash on the line after a JUMP (Emacs pulsar, `:pulse`): a post-step row tells a
                            key command's jump (another window or buffer, 5+ lines) from typing and
                            the mouse by `:command-count`, a timer fades the band the view lays over it
src/winner.blsp             C-c ← / C-c → window-layout undo and redo (Emacs winner-mode, `:winner`): a
                            post-step row keeps the layouts the window SHAPE changed from
src/whitespace.blsp         trailing whitespace and tabs as highlight ranges (Emacs whitespace-mode,
                            `:show-whitespace`, per mode through `scroll/ed-mode-setting`)
src/avy.blsp                jump to a visible position by label (Emacs avy): C-' char-timer, M-g w / e
                            word starts — targets from each pane's row table, over the read-char overlay
src/embark.blsp             C-. act on the thing at point or the selected candidate (Emacs embark): the
                            target (region > URL > file > symbol), a transient of actions that NAME
                            existing commands, C-; its default, C-h B every binding as a prompt
src/spell.blsp              spell checking (Emacs jinx, `:spell-check`): the visible prose, and the
                            comments and strings of code, checked off the loop by a long-lived
                            `enchant-2 -a` (else aspell); M-$ correct, C-M-$ the dictionary
src/cape.blsp               completion sources beside the mode's (Emacs cape): file paths, and words
                            from other open buffers, ranked after this buffer's
src/savehist.blsp           minibuffer answers kept per prompt across sessions (Emacs savehist,
                            `:savehist`): seeds the prompt's ↑ / M-p history; off until `main` turns it on
src/saveplace.blsp          a file reopens where it was left (Emacs save-place, `:save-place`): its
                            point kept when its buffer is killed or the editor quits
src/statusbar.blsp          the mode line as extensible segments (render ops + click/hover zones in one pass),
                            and the chip REGISTRY (`register-modeline-segment`): a feature puts
                            its chip on the bar when its module loads — presence (collab), the
                            running app (apprun), the findings count (results), the attached
                            node (attach) — ordered by rank
src/ui-kit.blsp             the widget kit over editor/display: a widget is `(area ctx) ->
                            {:ops :zones}` — paint and hit-test in ONE pass, styled by semantic
                            role. The shared shape behind the context menu, popup, plume, which-key
src/input.blsp              dispatch: fold a key/mouse/tick event into the next model
src/commands.blsp           the GENERAL editing commands, each a (model key) -> model — motion,
                            editing, kill ring, panes, buffers, prompts. A feature's commands
                            live in its own module (dired, help, vim, registers, hexl,
                            eval-commands, shell-command), bound by qualified symbol
src/registers.blsp          registers (C-x r SPC / j / s / i) behind a `Register` ability, and
                            bookmarks (C-x r m / b)
src/hexl.blsp               hexl-mode: a non-UTF-8 file opened as a read-only hex view (pool's
                            find-file reaches it late-bound); the mode's `:no-write` facet is
                            what makes C-x C-s / C-x C-w refuse it
src/pool.blsp               the buffer pool and where its buffers are shown — open / select /
                            kill, `ed-display-buffer` (Emacs display-buffer), `ed-pop-to-file`
                            (next-error), find-file + its path prompt, the default dir and
                            project root, saving. What most modules `:use` instead of
                            `commands`: showing a report buffer needs none of the commands
src/menu.blsp               the right-click context menu's model ops (open / move / run /
                            close); an item names its command by SYMBOL, resolved when it
                            runs, so a redefined command reaches the menu too
src/keymaps.blsp            keybinding profiles (emacs / modal vim) as model-scope layers
src/interactive.blsp        the `defcommand` macro + the M-x command registry
src/transient.blsp          TRANSIENT MENUS (magit's `P`): the editor half of
                            `transient-core` (brood ADR-387) — the modal overlay, the
                            minibuffer read behind a `:read` outcome, and the MEMORY (a
                            menu reopens with the arguments it had last time, in
                            state/transients.blsp). A command invoked from a menu reads
                            its flags with `ed-transient-args` and cannot tell it was
                            reached from one. A keymap has nowhere to put a FLAG, which
                            is why `--force-with-lease` was untypeable before this
src/transient-core.blsp     the transient MECHANISM, no editor in it: a menu spec, its keymap,
                            the argument value it builds and the rows it renders (Magit's
                            transient.el; moved from brood's std by ADR-417)
src/modes.blsp              modes as layers — the INFRASTRUCTURE: text-mode, the shared
                            `prog` base (C-M-* motions), `register-language-mode` /
                            `register-prog-mode`, and the generic read-only modes
                            (special, help, occur, hexl, process / buffer menus, markdown).
                            A feature's own buffer types (git, dired, packages, bshell,
                            term, *Diagnostics*) register in that feature's module —
                            a read-only report through `register-special-type` (its
                            layers over special-mode over text-mode), its M-x names
                            derived from its keymap by `layer-commands`, its line
                            colouring through `fontify-lines` (spans per line)
src/brood-mode.blsp         brood-mode: the `.blsp` keymap (paredit, electric pairs) and
                            its services — eldoc, doc-at, completion against the live
                            image, the CST indenter, the checker as `:diagnostics`
src/lisp-modes.blsp         the other Lisps: `deflisp` (a special-form set + a file
                            pattern over Brood's own reader) for elisp, Common Lisp,
                            Clojure, Scheme, Fennel; `lisp-indent-with` (Emacs's rule);
                            wos kernel source
src/languages.blsp          `deflanguage` declares a tree-sitter language from ONE spec
                            (faces, indent, heredocs, injections, formatter) and generates its
                            whole service set — show-paren (`tsbrackets`) included — checked against
                            editor/treesit/language-contract, so an incomplete language
                            fails at load rather than at the keypress that needed it.
                            Ruby / Elixir / Python / Rust / JavaScript / TypeScript / TSX /
                            Go / C / Terraform + HCL (two modes over one `:hcl` grammar,
                            told apart by `:type`; only Terraform's files take `terraform
                            fmt`), shell (bash), JSON, TOML, YAML and Dockerfile, each naming
                            where its grammar lives (`:grammar`, for M-x grammar-install) — a
                            spec may extend another's (TypeScript is JavaScript's, Terraform
                            HCL's). A language that had a line lexer first keeps it as its
                            `:fallback`: a buffer opened while the grammar is missing is typed
                            as the lexer's stand-in (`model/ed-grammar-fallback`) and becomes
                            the parsed mode when the grammar arrives (`ed-grammars-arrived`);
                            JSON stays lexed past a megabyte (`:fallback-above`). `:injections`
                            (brood ADR-489) is the code embedded in a language — a Terraform
                            heredoc named BASH / JSON / PY, a Dockerfile `RUN` line as shell,
                            Elixir's `~H` as HEEx (heex-mode) — coloured with the embedded
                            language's OWN spec's faces, found per frame (`language-faces`), so
                            a missing language or grammar keeps the host's colours. `deflexer`
                            is its sibling for the line-lexer languages (a pattern + a `lex-*`
                            stem): env, JSON5, Makefile / INI / commit. And org-mode (`org`'s
                            spans and outline, folding, TODO cycling, heading motion)
src/tsbrackets.blsp         show-paren over a tree-sitter parse: a bracket is a delimiter
                            TOKEN, its partner the matching token under the same parent (so a
                            `(` in a string matches nothing), read off the held tree when the
                            buffer keeps one — every `deflanguage`'s `:bracket-match` /
                            `:bracket-match-tree`. A pair in the middle of its parent (an HCL
                            block's braces) is found among the parent's children, anonymous
                            tokens included (`node-children` all?), with no length cap
src/org.blsp                Org text: `org-spans` (the colouring), heading levels, where a
                            subtree ends, the TODO cycle. Pure; languages.blsp's org-mode
                            is the mode over it (moved from brood's std by ADR-417)
src/mail.blsp               mail: mbox-mode (C-c C-n / C-c C-p between messages, on rope
                            searches that cost the distance, not the offset), eml-mode, and
                            C-c C-v — the message at point DECODED in *Message* (Gnus's
                            article buffer) over `mail-message`: the headers that matter, the
                            text part, the attachments, RET saves one
src/mail-message.blsp       Internet mail messages: RFC 5322 headers, the MIME part tree,
                            encoded words, quoted-printable / base64, legacy charsets — what
                            mail.blsp decodes with (std's `mime` until brood ADR-417)
src/lex-gitignore.blsp       .gitignore-style ignore files and .gitattributes (Emacs git-modes)
src/lex-*.blsp              the lexical highlighters, each a pure `[start end face]` span fn
                            for a `:fontify` service: `lex-configs` (JSON / YAML / TOML /
                            Makefile / INI / commit, as `editor/lexer` tables), `lex-shell`,
                            `lex-dotenv`, `lex-dockerfile`, `lex-markdown` (spans, a fence
                            coloured as its info string's language over the whole fence —
                            `markdown-fence-pass`, kept by body text — and the rendering
                            mdpreview paints). std's `editor/*` until brood ADR-417
src/gutter.blsp             the line-number gutter text-mode names as its `:gutter-*`
                            services: the number column, the diff-hl bar, and the margin
                            marks (● ✓ ✗ ⚠) read through one precedence table that both
                            paints and resolves a click
src/grammars.blsp           tree-sitter grammars the runtime was not built with: where they
                            live (~/.config/bedit/grammars), declaring them at startup, and
                            M-x grammar-list / grammar-reload / grammar-install: what is
                            installed (ABI, path), fetching and building a declared one off
                            the loop, and a live swap — drop a new .so in and reload, no
                            restart. An install or reload retypes every open line-lexer
                            stand-in as its parsed mode (`model/ed-grammars-arrived`)
src/formatter.blsp          M-x format-buffer + format-on-save: the language's own
                            formatter (mix format, black, rubocop), declared per language
                            and run over the FILE, so a failing formatter costs nothing
                            (named to dodge std's `format`: a release resolves a std name
                            first, so a project module called `format` never ran)
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
                            *Messages*, because it answers nothing until its engine is up.
                            THE SERVER TABLE (`*lsp-server-specs*`): per server its file types,
                            command alternatives (the first installed runs), root markers
                            (`Cargo.lock` before `Cargo.toml`) and whether it is an ADD-ON or
                            SHARED. A buffer reaches every server its extension names (pyright
                            and ruff for .py), each rooted where its markers say, or none — so
                            wos source beside a running brood-lsp is never checked as Brood.
                            Lookups go to the first server offering the feature; diagnostics
                            and completions merge. A shared server (rust-analyzer, gopls,
                            pyright, TypeScript) takes a further project as a workspace folder
                            when it says it can and both pin the same toolchain
                            (`ed-lsp-identity`). `:lsp-servers` files them; M-x lsp-servers
                            lists them
src/lsp-requests.blsp       the LSP request-kind records + `LspRequest` ability — the shape/fold vocabulary
                            shared by lsp (connection side) and lsp-commands (model side); eager-loaded so
                            lsp-commands can register fold impls while lsp stays deferred
src/mincomplete.blsp        minibuffer prompt completion (path / name)
src/filename.blsp           a typed path read the Emacs way (`substitute-in-file-name`, which is
                            std's `path/substitute` — this is the prompt's layer over it): the prompt
                            shows the home as `~`, `//` or `/~/` restarts the path (the overridden
                            part painted dim — file-name-shadow), `$VAR`s expand, a name from the
                            disk goes on the line escaped (`$$`), a relative name is read under the
                            prompt's directory. Both path prompts — `pool/ed-path-prompt` (the disk)
                            and `pool/ed-path-list-prompt` (recent files, projects, git init/clone)
                            — hand their consumer the ABSOLUTE path (`filename/expand`)
src/completion.blsp         shared fuzzy ranking + vertical-menu card (complete + plume)
src/fileperm.blsp           the `ls -l` permission string (`rwx`, `perms-string`) — dired + plume marginalia
src/plume.blsp              the minibuffer completion UI — vertical list + marginalia + N/M counter (our Vertico/Marginalia)
src/debugger.blsp           the editor as the debugger (ADR-174/184): C-c d session, *Spy* trace
                            stream, *Debug* paused-process queue with resume/eval-in-scope,
                            trace-fn/break-fn by name — the collector process speaks std/debug's
                            wire protocol and forwards UiEvent records to the loop
src/testrun.blsp            native test runs (C-c t): a dedicated nest subprocess streams per-test
                            JSON (std's test/*report-sink*) into the *Tests* buffer — never
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
                            session already knows, and now says. A live-evaluating client's
                            ready/down bookkeeping too (`client-ready` / `client-down`)
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
src/wrap.blsp              where a line falls on screen rows: the pure break rule (a line →
                            `[from to]` row segments, word-wrapped at the pane width) and the
                            ONE row of a truncated line (`one-row`: cut before the cells its
                            ellipsis takes, never halving a wide glyph; a clip `[cut ellipsis]`
                            rides the row) — per line, by `line-policy`. The row↔line owner
                            (panes), the view and the scroll clamp all read it; point past a
                            cut scrolls that one line sideways (`follow-point`, Emacs's
                            current-line auto-hscroll), a click on `…` goes to the line's end
src/folds.blsp              outline FOLDING in an editable buffer (org's TAB): a fold is a
                            marker on its heading, the mode's `:fold-extent` says what it
                            covers, and the row table gives the hidden lines no rows — so the
                            view, cursor, scroll and mouse never see them; point landing
                            inside one opens it
src/isearch.blsp            incremental search + query-replace (C-s/C-r/M-%) modal mini-loops
src/eval-command.blsp       eval Brood source from a buffer (the C-x C-e core)
src/eval-commands.blsp      the C-x C-e family as commands (eval-last-sexp / -region / -buffer):
                            off the loop as a std/task, C-g cancels; loaded with the image (main)
src/shell-command.blsp      M-! / M-| (Emacs shell-command): one `sh -c` in the buffer's dir, off
                            the loop, output to the echo area or a side pane; C-u M-| replaces
                            the region. Loaded with the image (main)
src/sandbox.blsp            the Brood eval session's BACKEND over std's `editor/evalsession`:
                            find a runtime, start it on a generated eval-server script
                            (ADR-198), the pr-str-line codec, and session events -> UiEvent
                            records. The supervision (queue-until-ready, id-matched replies,
                            the watchdog, strikes, respawn) is std's and shared with Elixir
src/liveeval.blsp           the live-evaluating buffer as a VOCABULARY, shared by tutor +
                            playground: parse-state, result/type/timing notes, spy cascade,
                            and `form-step` — ONE form's turn in either's launch (carry, note,
                            hold, send, or answer in-image), each client a map of callbacks
src/sandbox-events.blsp     routes the shared sandbox's UiEvents to every client that wants
                            them (an `impl` is per record type, so one client can't own them)
src/playground-core.blsp    the live-evaluating buffer as a MECHANISM, parameterised by a
                            language spec: form diffing, the marker-anchored notes, the
                            launch plan, the reply fold, the pane following the cursor, the
                            QUIET WINDOW (a new error for the form you are typing, and the
                            checker's findings on its lines, wait until you pause or move off) —
                            everything about a playground that is not about a language.
                            Three clients: the two playgrounds and the tutorial (a box is
                            its form, lesson data rides `:form-data`)
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
                            eval-on-type in the sandbox — ✓/✗ gutter, ghost results, prose guard;
                            the third client of playground-core
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
                            test, run and REPL here (mix / nest / cargo / npm / go /
                            terraform / make),
                            and which tasks it can list. projects.blsp derives its root
                            markers from this table, so a language is ONE edit
src/results.blsp            the results-buffer abstraction behind *Tests* / *Run* / *compilation* /
                            *Occur* / *git-status*: the `file:line[:col]` location vocabulary, the
                            `location-jump-layer` that makes every such row navigable, and
                            `ed-append-follow` — the streaming append that follows the tail
                            only in a pane already at the bottom
src/testadapter.blsp        one result vocabulary, two runners: Brood's structured
                            test/*report-sink* lines and ExUnit's `mix test --trace` text
                            both decode into the same {:group :name :passed :where …}, so
                            C-c t means the same thing in every project
src/compile.blsp            M-x compile: run a build in the project root, C-x ` next-error,
                            M-x project-task (mix tasks / npm scripts). The error locations
                            are an Emacs-style regexp TABLE (`*error-patterns*`), which
                            needed brood's regex captures to be expressible at all
src/projects.blsp           project root + file walk (find-file-in-project); a VCS checkout (git,
                            mur — std's `vcs`) is a root and lists its own files
src/formbuf.blsp            FORM BUFFERS: generated text with editable regions (a shell's
                            input, a tutorial's boxes) — the region algebra, `splice`, and the
                            `:veto` / `:clamp` guards. Pure; moved from brood's std by ADR-417
src/bshell.blsp             per-project shell + Brood REPL buffer (C-x p e): a line
                            typed at bedit's own prompt runs as `sh -c` (pipes, output
                            stripped) or, starting with `(`, evaluates as Brood in the
                            worker; owns the input-region vocabulary (`:input-start`, the
                            boundary guard, ↑/↓/C-r history) that a line-mode terminal
                            reuses
src/terminal.blsp           a TERMINAL buffer (C-x p t, C-x p r, M-x claude, C-u M-x term):
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
                            (named to dodge std's `term`, as formatter dodges `format`)
src/section.blsp            SECTION TREES (magit-section) as data: a tree rendered to lines
                            plus parallel rows, walked and folded by index. Pure; moved from
                            brood's std by ADR-417
src/sectionbuf.blsp         the SECTION BUFFER: a read-only buffer whose text is a
                            `section` tree (brood ADR-388) — tree, rows and
                            visibility live ON THE BUFFER, faces come from the mode's
                            `:section-faces` service as data (`:face-spans`), a right margin
                            (a log's author and age, Magit's) from `:section-margin` as
                            `:right-margin` — the view narrows the text for it — line backgrounds
                            (a diff's tinted lines) from `:section-bands` as `:line-bands`, and TAB · n/p ·
                            ^ · M-n/M-p · 1-4 · M-w are shared by every such buffer. A lazy
                            section (a status file whose diff was never fetched) asks the
                            mode's `:section-reload`. Each line's KIND (`:line-kinds`: a heading,
                            a body) is how a long one shows — a commit or stash row ends in `…`,
                            a hunk's code wraps (`scroll/ed-long-lines`)
src/vcscore.blsp            the VCS layer, whichever system the project uses (Emacs's VC). The
                            checkout a buffer is in comes from std's `vcs` (`.git`, `.mur`);
                            what the editor does with it goes through that system's ROW
                            (`register-vcs-backend`): C-x g its status, C-x M-g its menus, C-c g
                            its file menu, C-x v = / l / b the file's diff, log and blame, and
                            the mode line's chip — a backend's `:chip` is FACTS (glyph, label,
                            dot, counts), drawn by one renderer (`vcs-chip-segments`) so every
                            backend's reads alike — summarised OFF the loop and only when the
                            disk may have moved (`:vcs-summary` / `:vcs-segments`; `:label`,
                            git's branch or mur's change, is the window title's too). Names no
                            backend: a row's hooks are symbols called late
src/vcsproc.blsp            what every VCS's command line shares: the PROCESS LOG (`$`,
                            *vcs-process*, magit's `magit-process-buffer`) — git and mur
                            commands in the order they ran, exit code, duration, output,
                            credentials redacted, `\r` progress applied — `vcs-run` (journalled)
                            and `vcs-launch` (OFF the loop, for the network), `vcs-report-cmd`,
                            `vcs-confirm`, a unified diff's faces, and a file's hunks as
                            sections (`vcs-hunk-sections`, std's `diff`) with the file line a
                            diff line is (`vcs-hunk-line`) — git's and mur's diffs are one tree,
                            painted alike (`vcs-hunk-spans`, `vcs-hunk-band`: tinted lines, a
                            hunk heading bar, the changed words)
src/diffpaint.blsp          a diff hunk painted as Magit and delta paint one, as data: its code in
                            its language's colours (each side of the hunk fontified as one snippet
                            by the file's own mode) and the WORDS a changed line changed (a block
                            of `-` lines diffed against the `+` lines after it, by token, std's
                            `diff/seq`). vcsproc's hunk sections carry it; the faces services
                            turn it into spans. Capped, since it is paid when the buffer opens
src/mur.blsp                the TOP of the mur porcelain (git.blsp's counterpart): `:use`s every
                            mur module, and holds its menus — C-x M-g (and ? in *mur-status*)
                            every mur verb, C-c g mur about this file — both reached through
                            `vcscore` rows (`:dispatch`, `:file-menu`), as git's are. main loads it
src/murcore.blsp            the ground the mur porcelain stands on: `mur-mur` (the client, as
                            the editor's own seat, MUR_RUNNER=bedit), `mur-json` over its
                            `--json`, the working copy a buffer is about, `mur-do` /
                            `mur-launch` through vcsproc's log — and mur's ROW in std's `vcs`
                            (files, changed, base text, id): bedit is the package that knows mur. mur is Murmuration's VCS (mur.fly.dev): a CHANGE,
                            its saved VERSIONS, a land puts it on TRUNK
src/murbar.blsp             mur's row in vc and its mode line: ◆ what the change is for, a
                            state dot, ~changed !clashes ↑unsent ?unclaimed — one
                            `mur status --json`
src/murstatus.blsp          C-x g in a mur working copy: *mur-status*, a section tree — the
                            change and where it stands, clashes, files changed since the last
                            save (TAB: the diff), unclaimed edits, the other changes here,
                            trunk. c change · r rename · s save · l land · u update · y sync ·
                            S settle · k restore · a claim · x drop · d diff · L log · V
                            versions · ! any; C-x v = / l for a mur file
src/murforge.blsp           the forge's side (mur-forge, mur.fly.dev) through the client: o the
                            change's page in the browser, O *mur-changes* (the forge's open
                            changes; RET brings one here), C checks, D discussion, R reviews
src/murhistory.blsp         mur's side of the time machine (C-x v t): a file's history is this
                            change's saved versions (`mur versions --json PATH` — the BRANCH
                            scope, against trunk, each reading `v2` beside its hash) then
                            trunk's (`mur log --json PATH`; the forge away, the versions alone,
                            said in the info pane); a version's text `mur cat PATH --at
                            SNAPSHOT`, its diff `mur show SNAPSHOT PATH`; D shows the snapshot.
                            No blame: mur has none
src/git.blsp                the TOP of the git porcelain (Magit's): `:use`s every git* module
                            below, so loading git loads all of it and every command a menu
                            or keymap names by symbol is there. Holds what has no better
                            home: the l log / d diff menus, `!` any git command, the file
                            menu (C-c g), % worktrees, W/w patches, o submodules, T notes,
                            i ignore, K untrack, R rename, j jump, M-x git-init / git-clone,
                            and ? — every menu from one key
src/gitcore.blsp            the ground under it: `git-git` (never prompting), the repo a
                            buffer is about, `git status --porcelain -z`, upstream and
                            ahead/behind, refs / remotes / stashes, which operation is
                            half-done in .git (the SEQUENCER). One logged seam: `git-run` /
                            `git-run-hunk`, `git-do` to refresh after, `git-launch-op` for
                            network commands OFF the loop — git's side of vcsproc's log
                            and runner.
                            Knows nothing of the status buffer: it refreshes it by name
                            (`git-refresh-status`), because gitstatus stands on this
src/gitbar.blsp             git's row in vc and its mode line: ⎇ branch, state dot, ↓/↑ vs
                            upstream, +staged ~unstaged ?untracked
src/gitsection.blsp         what every git SECTION buffer shares (status and gitview's views):
                            file / hunk / commit section builders, `git-section-faces` (a
                            line coloured by what it IS), `git log` parsing, what is at point,
                            and `git-common-keymap` (Magit's `magit-mode-map`)
src/gitpick.blsp            asking for ONE thing — a remote, ref, commit, name, start point —
                            in a completing prompt, the one at point first (`git-prompt`)
src/gitstatus.blsp          C-x g *git-status*, a section tree: in-progress line,
                            Head:/Merge:/Push:/Tag:, Unmerged / Untracked / Unstaged / Staged
                            files (TAB fetches a file's hunks), unpushed, unpulled, stashes,
                            recent commits — collected in a task. s/u/k act on what is at
                            point: a REGION of a hunk's lines (std/diff `hunk-select`), a
                            hunk, a file, several files, a whole list, a stash; k on a
                            conflict offers ours/theirs, e opens it at its first marker
                            (smerge). RET goes to the line a diff line became. The background
                            fetch that says when the upstream moved
src/gitremote.blsp          P push (where it pushes / upstream / elsewhere / another branch /
                            tags; a branch with nowhere to go is asked and remembers) · F
                            pull · f fetch · M remotes — each a transient, all off the loop
src/gitrefs.blsp            b branch (a remote branch checks out as a tracking local one;
                            create from a start point, spin off, upstream, reset, delete
                            asking before -D) · t tags · z stash (at point) · X reset
                            (mixed/soft/hard/keep, index, worktree, file)
src/gitcommit.blsp          c commit (extend · reword · amend · fixup · squash · instant
                            fixup/squash; off the loop, the staged diff beside the message,
                            M-p/M-n message history, a failed commit keeps its draft)
src/gitsequence.blsp        m merge (+preview) · r rebase (interactive from the commit at
                            point, and reword / modify / remove ONE commit, autosquash — a
                            plan handed to git as `sequence.editor=cp <file>`, so no editor
                            ever opens) · A cherry-pick · V revert · B bisect. The SEQUENCER
                            is one idea not five: one continue/skip/abort dispatches on
                            whichever operation git says is half-done
src/gitview.blsp            the git VIEWS, section buffers acted on in place: *git-revision*
                            (a commit's message then files and hunks — RET to a line, a applies
                            a hunk, v reverses it), *git-diff* (s/u/k as in the status, + / -
                            context), *git-log* (graph, refs, author/age margin; RET shows,
                            SPC peeks, + doubles; A/V/X/r i act on the commit at point), the
                            reflog, *git-blame* (chunks per commit; b blames the version
                            before), *git-refs* (y), a file at a revision (C-c g f), and git's
                            side of the time machine (`git-file-history` / `git-file-revision`).
                            Every view runs git, parses and paints OFF
                            the loop (a slot each): its buffer opens at once — `Loading…`, or what
                            it held on a refresh — and the tree lands when git answers; a reply
                            for a killed or re-asked buffer is dropped, C-g cancels
src/timemachine.blsp        the TIME MACHINE (C-x v t, C-c g t / p / n; Emacs's git-timemachine):
                            ONE buffer per file stepping its revisions IN PLACE, in the file's own
                            mode — p / n, < / >, g pick, q back to the file — point kept on its
                            logical line through the line diff, the changed lines tinted (h). B:
                            the whole history or WHAT THIS BRANCH CHANGED since its base (the
                            upstream when it tracks another branch, else origin/HEAD / main /
                            master), the default when the branch touched the file. Beside it an
                            `aside` (d) follows the revision: message, author, date, its diff of
                            the file painted as every diff (RET goes to the line); D the whole
                            commit, b blame, w / W the hash. VCS-neutral: the history and a
                            revision come from the row's `:file-history` / `:file-at` in a
                            task — the history once, a revision when first stepped to, cached;
                            a step supersedes the fetch in flight. git and mur both provide
                            the rows (gitview, murhistory); mur has no blame
src/smerge.blsp             conflicts resolved IN the file, Emacs's smerge: C-c ^ n/p between
                            conflicts, u/l/a/b keep upper / lower / both / base
src/diffhl.blsp             diff-hl change gutter: per-line added/modified/deleted against the
                            file's base text (std's `vcs/base-text`: git's HEAD, mur's last
                            save), recomputed off the loop on the idle beat;
                            C-x v ] / [ walk its changes, whichever VCS drew them
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
src/remote.blsp             --serve / --attach / --listen: the daemon/emacsclient model over node links.
                            A TCP session hands out GUEST cookies (brood ADR-415; one per
                            `--invite NAME`, the name bound), never the machine cookie, and a
                            guest's session runs an allowlist (`model/ed-guest-allows?`)
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
