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
src/main.blsp               entry point — window / daemon startup (--serve/--attach), runs the ui-run loop;
                            `-nw` / `--no-window` runs it in the TERMINAL over brood's terminal
                            display (brood ADR-586/587), and so does no display at all (no
                            $DISPLAY / $WAYLAND_DISPLAY, an ssh login even with X forwarded), with a one-line note, and so
                            does a window that will not open when a terminal is there to fall back
                            to (`open-frontend`) A hung-up terminal
                            and a window whose compositor or X server died (`[:hangup :display-lost]`,
                            brood ADR-631) end the loop the same way: every unsaved buffer to its
                            sidecar first (`display-hangup`), no restart
src/startup.blsp            the ONE startup path the window and `--serve` share: the runtime's
                            (grammars, slow-turn log, savehist, colours + `:theme`, packages), a
                            model's (init.blsp's model settings, recentf, save-place), a window's
                            (font, inset, text settings, window mode — an attached client's from
                            ITS machine's init file) — and the FRONTEND: `choose-frontend` (a
                            window, or the terminal for `-nw` / no display), and the clipboard a
                            terminal session reaches (the desktop's, else the terminal's, OSC 52).
                            A terminal model has `:terminal` and no `:gui`: the view draws its cell
                            fallbacks, a zoom and a second frame are refused, a bracketed paste
                            arrives whole as `[:paste text]` (input's `ed-paste`, Emacs's xterm-paste). A `:font` that is not installed is SAID
                            (`font-warning`, from `gui/font-info`'s `:not-found`, brood ADR-442):
                            the echo area and *Messages* at startup, M-x reload-config, a served
                            window's console — never a silent DejaVu
src/model.blsp              the ui-run model: buffer pool, panes, *Messages*,
                            the timers — and the REGISTRIES the rest plugs into: idle-beat jobs
                            (`register-idle-job`), off-loop task replies, inbound `[:tag …]`
                            event handlers, feature timers, process deaths
                            (`register-down-handler`), what is still running when
                            C-x C-c asks (`register-exit-query`: a compile, a test run,
                            the app, a terminal, a push), what follows a KILL
                            (`register-slot-keeper`, `{:order :slots :drop}`, run in order
                            by `ed-drop-slot`: everything kept by pool index goes through
                            one `shift-slots` — collab before hosted before the caches) and
                            what a VISIT passes through (`register-visit-step`, Emacs's
                            find-file-hook, `{:order :run :instead :passing}`: save-place,
                            so-long, the recovery note, which is said `:instead` of the open
                            notice) and the files reached ANOTHER WAY (`register-file-handler`,
                            Emacs's file-name-handler-alist: a row claims a typed path by
                            `:prefix` and a buffer by `:mark`, and answers `:find-file`,
                            `:write-file`, `:save`, `:revert`, `:file-of`; a `:later-entry` +
                            `:save-all` for a save that lands after the questions), who SHOWS a
                            directory, a file that is not text and a new frame
                            (`register-presenter`: dired, hexl, frames), what an event marks
                            before the timers (`register-input-step`: the web mirror), what
                            runs at an event's tail (`register-tail-step`: hosted's propagate,
                            then collab; `:recover` rows on a thrown command's recovery too),
                            once a turn COMMITS (`register-commit-step`: syntaxtree's handle
                            release), an input that changes nothing (`register-inert-input`:
                            hosted's own echo), who a client is (`register-identity-step`:
                            collab's name), faces a producer stamped on its text
                            (`register-text-faces`: ansicolor), a paste a program takes whole
                            (`register-paste-taker`) and a key kept out of a macro
                            (`register-macro-guard`: both passwd), what a click on an INLAY
                            row does, by the row's owner (`register-inlay-click`: a code lens
                            runs). A buffer process's
                            `[:buffer-updated …]` is hosted's handler, replaced by collab's
                            when collab loads; a process down goes to every down handler
                            (hosted and collab recover their slots). The core names no feature: a
                            module registers its rows when it loads, each row CLAIMED for the
                            file that registered it (`ownership/claim!`), so a package's rows
                            go back with the package. Also the OUTPUT CAP
                            every streaming sink shares (`ed-cap-output-at`: past
                            `:output-buffer-max-lines` a buffer's oldest lines are cut,
                            point / mark / `:input-start` / `:line-links` and every pane's
                            cursor and scroll moving with the text — Emacs's
                            comint-buffer-maximum-size) on the one CARRY rule every change of
                            text shares (`ed-carry-position` / `ed-carry-panes`: positions move
                            as Emacs markers do — a head cut here, another frame's splice in
                            `hosted`, the layouts a feature keeps via `register-layout-keeper`),
                            and `ed-ding`: a
                            command's FAILURE
                            (a motion at the edge, a failing search, a read-only refusal),
                            which is what stops a keyboard macro. `message` never covers a
                            STANDING QUESTION (a y/n read, a query-replace, a minibuffer prompt):
                            it shows beside it in brackets until the next key, as Emacs's
                            minibuffer message, and lands in *Messages* as always
src/textpos.blsp            pure text geometry under the model: an offset's line, column, ends, and
                            what an edit changed (the splice log)
src/diagstore.blsp          the diagnostics cache the view reads, whoever produced it, a
                            diagnostic's position converted in one place, the quiet window
src/lossage.blsp            the recent keys (C-h l), a bounded ring on the model
src/minibuffer.blsp         the minibuffer: a one-line prompt over std's lineedit with a list under
                            it, modal (`minibuffer-handle`); ranks on the key for a small source,
                            in a session off the loop for a large one. The accessors (`mb-text`,
                            `mb-candidates`) and the echo area's height (`ed-echo-rows`) the layout
                            reads
src/offloop.blsp            a slow call run OFF the loop, its answer folded when it lands
                            (`ed-open-when-ready`): a prompt that opens once its candidates are
                            ready (M-x project-task), C-x p g's search; one slot per caller
src/clipboard.blsp          the kill ring and what it shares text with: kills mirror to the OS
                            CLIPBOARD; a mouse drag sets only PRIMARY (`ed-drag-select`, brood
                            ADR-553 — the clipboard and kill ring stay put unless
                            `:mouse-drag-copy-region`); PRIMARY is read as an ask (`ed-primary-ask`:
                            a task for the local window, the client for a served session); one
                            ring for every frame (a shared agent)
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
src/autosave.blsp           `#file#` auto-save sidecars written (owner-only, on the idle beat, order
                            110, and a timer of their own). Only a MODIFIED buffer is ever written
src/backup.blsp             backup files (Emacs make-backup-files, `:make-backup-files`, on): the first
                            save over a file in a session copies it as it was to state/backups/,
                            owner-only, named by its whole path (`sidecar/path-file-name`, a private
                            sidecar's naming) — in the save's own task
                            (`file-save/ed-save-launch`); local files only
src/sidecar.blsp            where a sidecar lives and the note a visit shows when one is newer than
                            its file. A file edited as root (sudoedit) keeps its sidecar PRIVATE —
                            `state/auto-save/#%2Fsudo::%2Fetc%2Fhosts#`,
                            its TRAMP path (the user in it) percent-encoded, a long one hashed with
                            the path in `NAME.spec` beside it; never beside the file
src/autorevert.blsp         auto-revert of files changed on disk (one undoable edit, std's
                            `revert-buffer`; idle beat, order 120, after the sidecars). A file
                            edited as root is left alone
src/sudoedit.blsp           editing a file as ROOT (Emacs's TRAMP `/sudo::` and `sudo-edit`), the first
                            file handler (`model/register-file-handler`), over brood's
                            `sudo` (ADR-588): `C-x C-f /sudo::/etc/hosts` (or `/sudo:USER@:PATH`, this
                            machine only), `M-x sudo-edit` (the current file, its unsaved text kept),
                            `C-x C-w /sudo::PATH`. The buffer remembers (`:sudo`, `:sudo-user`, carried
                            to other frames and a restarted loop by `hosted-meta`): C-x C-s writes it
                            through sudo in place (`file-save/ed-save-prepare` / `ed-save-landed`), the mode line says
                            `# root`. A password sudo wants is read masked (`passwd/ed-read-passwd`),
                            handed to sudo once and kept nowhere — sudo's own timestamp serves the
                            next save. Every sudo call is a task on `remotejob`'s queue (`:sudo-proc`,
                            one at a time, C-g stops it): an open shows `Loading…` at once, a save stays modified
                            until its write lands (`file-save/ed-save-prepare` / `ed-save-landed`), and
                            C-x C-c / C-x s save root files after their questions and go on when
                            the last lands. A file is read as BYTES (`sudo/read-bytes`) and goes through
                            `charset` as any file does; a binary opens as the read-only hex view; a large one is asked about
                            first (`pool/ed-file-of-spec`); one buffer per file AND user (the
                            registry `:key` names the user); killing `Loading…` cancels the open.
                            Under -nw, C-z suspends (`frames/cmd-suspend-frame`, `term/suspend`)
                            and SIGHUP / SIGTERM auto-save every unsaved buffer before the
                            terminal is restored (`main/terminal-hangup`). Named to dodge std's `sudo`
src/remotejob.blsp          the ONE queue a file reached another way runs on, shared by sudoedit and
                            sshedit (each hands it a spec map: its model keys, its work, its fold):
                            a job (open / save / revert / listing) is a task, one at a time per
                            method, a second waiting its turn and never dropped; `Loading…` killed
                            cancels an open; a password asked for masked only when the prompt is
                            free (`ask`, `run-waiting`); C-g (`quit`), C-x C-c (`live`), the common
                            head of a landed job's fold (`landed`), and a save / save-all that keep
                            the buffer modified until the write lands (`save`, `save-all`)
src/sshpath.blsp            the TRAMP `/ssh:[user@]host[#port]:path` syntax in ONE place, pure: `parse`,
                            `spec`, `canonical` (a buffer's key), `dirname`, `join`, `remote-start` (a
                            `/ssh:` typed over a path), and `remote?` — what every local tool asks
                            before it touches a path. `~` / a relative path is the REMOTE home's,
                            `~other/…` another user's (kept as typed, resolved there); a route
                            through jump hosts is TRAMP's multi-hop (`/ssh:bastion|ssh:host:/x`,
                            `:hops` on the parts, `route-label`, `prefix`; `same-connection?`), and
                            a last ROOT HOP edits as root THERE — `|sudo:`, `|su:` or `|doas:`
                            (`/ssh:host|sudo::/etc/x`, `|su:www@:` another user — `:become
                            {:method :user}` on the parts, `*become-methods*`, `become-user?`, its
                            own connection). filename, sidecar, mincomplete, dired and the handler all
                            read it
src/sshremote.blsp          the transport under `/ssh:`: the system `ssh` (`*program*`, a test's
                            stand-in runs the scripts locally) with one SHARED connection per host
                            (ControlMaster, the socket in `state/ssh/`, owner-only, ControlPersist
                            5 min), BatchMode always — a failure classified (`classify`: host key
                            never accepted, auth, connection dropped). Each operation is a POSIX sh
                            script on ssh's stdin (`/bin/sh -s` is all the login shell parses; args
                            `os/shell-quote`d): a read through base64 (bytes, a size limit asked
                            first), an atomic write (staged beside the file with its mode, size +
                            SHA-256 checked, renamed), `ls -1pa` for the prompt (kept 10 s, a
                            table), `stat` rows for dired (`list-entries`, GNU or BSD, a link's `readlink` target) and its
                            mkdir / mv / cp -pR / rm -rf / ln -sfn / chmod (`make-directory`, `transfer`, `delete-path`, `make-symlink`, `set-mode`,
                            `file-kind`: never over a directory, over another entry only when told
                            — a copy staged beside it and renamed over it). Between two machines,
                            or a host and this one (`run-local`), `cross-transfer`: a tar archive
                            STREAMED through an OS pipe, never held here — staged where it is
                            (`stage-pack-script`, size + SHA-256), a receiver left where it goes
                            (`receiver-script`), one local `sh` running `ssh FROM cat | ssh TO sh
                            RECEIVER` (`os/pipeline`, brood ADR-696; `stream-side`) — any size; a root-hop side
                            is carried through the editor instead (`pack-script` /
                            `unpack-script`, ≤ `*transfer-max-bytes*`, 200 MB). Unpacked in a
                            staging dir, size + SHA-256 + entry count checked, then renamed; a
                            move deletes only after. `~user` resolved by the remote shell, the name
                            checked first. Jump hosts become a nested `ProxyCommand` of `ssh -W`
                            (`proxy-command`; batch mode for every hop, riding the hop's own
                            ControlMaster — ssh's `-J` passes no options on), run by `/bin/sh`
                            (`SHELL`); a route that fails is tried hop by hop (`route-failure`,
                            `blame-route`), naming the hop. A password opens a connection once —
                            the host's or a hop's (`connect-with-password`, `hop-parts`: SSH_ASKPASS
                            helper reading ssh's own stdin, refusing yes/no questions). A root-hop
                            path's scripts run in `sshsudo`'s root shell (`run`, `become-request`,
                            `become-connect`; `-tt` for su / doas: `ssh-options`' `tty`)
src/sshsudo.blsp            the ROOT HOPS' ROOT SHELL (`|sudo:`, `|su:`, `|doas:`), kept open as TRAMP
                            keeps one (no credential cache can serve the next ssh command: a new
                            session each). ONE METHOD TABLE (`*methods*`): each method's command,
                            whether it needs a terminal (su and doas read a password only from
                            one: ssh `-tt`, the shell then `stty raw -echo`, stderr away so never
                            interactive), its prompt regex (`prompts-in`) and whose password
                            (`password-question`, `who`). sudo is told its prompt by
                            `SUDO_PROMPT`, never `-p` (sudo-rs < 0.2.5 refuses `-p`; its own
                            `[sudo: authenticate]` is the fallback). A process per route + method +
                            user over the host's ControlMaster, ended 5 min idle or when the link
                            drops. The password is written once, only at the method's prompt (a
                            NOPASSWD / `nopass` rule never gets it); a second prompt, or the method
                            ending after it, is a wrong one. Each request a script run by its own
                            `sh` from a temp file, output and errors Base64 between per-request
                            markers (`request-text`, `parse-reply`), answered as `os/cmd`'s map.
                            `stop-all` (a test passes its socket dir)
src/sshedit.blsp            editing a file on ANOTHER MACHINE (Emacs's TRAMP `/ssh:`), the second file
                            handler (`model/register-file-handler`, sudoedit's shape): `C-x C-f
                            /ssh:host:/etc/x`. The buffer VISITS the TRAMP path (`buffer-file` is
                            the spec, `:ssh` its mark, carried by `hosted-meta`), so no local tool
                            takes it for a file here. Every ssh call a task on `remotejob`'s queue
                            (`:ssh-proc`, one at a time, C-g stops it): `Loading…` at once, a save
                            stays modified until it lands (`file-save/ed-save-prepare` /
                            `ed-save-landed`), a dropped connection said. A password the host, a
                            jump host or the root hop (`|sudo:`, `|su:`, `|doas:`) wants is read masked
                            (`passwd/ed-read-passwd`; the job's `:password-for`) and used once.
                            charset as any file (binary → hex, large → asked); a directory opens in
                            DIRED (the handler's `:dired`, `ed-ssh-dired`: listed off the loop, then
                            `dired/ed-dired-show-entries`), whose `+` `R` `C` `D` `x` go through the
                            handler's file operations (`:make-directory`, `:rename-file`,
                            `:copy-file` — within a host, between hosts or to and from this machine,
                            replacing an entry only when asked — `:file-kind`, `:delete-file`, wdired's
                            `:make-symbolic-link` / `:set-file-modes`,
                            `:expand-file-name`, `:parent-directory`, Emacs's
                            file-name-handler-alist — dired names no handler). CI's `ssh-real` job
                            drives all of it against a real sshd (tools/ci/ssh-real.sh). Its sidecar
                            is private (`sidecar/private-spec`); auto-revert, diff-hl, LSP, the
                            formatter, editorconfig, dir-locals, compile, M-! and the project walk
                            skip it (`sshpath/remote?`). The mode line says `@host` (`@host # root`)
src/bugreport.blsp          M-x report-bug (Emacs's report-emacs-bug): every error the editor CATCHES
                            (a command, a render error frame, a fontify, a loop the supervisor
                            restarted) reaches its error sink (`model/register-error-sink`),
                            described as data by brood's `crash-report/describe-error` (redacted,
                            no buffer text) and kept in state/errors.blsp once per kind a session; a bedit that DIED on a signal
                            left a brood record (ADR-635), taken in at the next start (`adopt-crashes!`);
                            the first time, the echo area points at M-x report-bug. *Bug Report*
                            shows exactly what would be sent, editable, under your note; C-c C-c
                            sends it off the loop to `:bug-report-url` (the hive), C-c C-k drops
                            it. Nothing is sent otherwise; `*post*` is bound in tests
src/recover.blsp            M-x recover-this-file / recover-session: a sidecar's text put back as one
                            undoable edit (Emacs's), from the open and recent files
src/lifeline.blsp           the editor loop under a SUPERVISOR (`main` runs `supervise`): a loop that
                            dies abnormally has every file buffer whose text its file lacks
                            auto-saved from the buffer PROCESSES (they outlive it), its window
                            closed, and a fresh loop started over the registry's buffers — given up
                            after `*restart-max*` restarts a minute, so a fault on every start
                            cannot spin — and never once a -nw loop's terminal hung up
                            (`no-restart!`): a loop restarted on a dead terminal only dies again.
                            The supervisor also holds SIGTERM, SIGHUP and SIGINT: told to end, it writes
                            those sidecars, ends the loop whatever it is doing and exits 128+n. A daemon
                            has one KEEPER doing that across every session (`start-keeper`), a terminal
                            display taking `:term` and `:hup` while entered (ADR-586).
                            Its `emergency-save!` is a served session's crash hook too (remote)
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
src/config-paths.blsp       where the editor's files live and who it is: `*app-id*`, `config-dir`, the
                            init file's path, the test-run guard. No setting is read here, so
                            the state files and the package store stand below the settings table
src/display-rules.blsp      `:display-buffer` rules as data: `*display-actions*`, the defaults, what
                            makes a rule valid, an action read. Matching a buffer and acting
                            on the panes are `pool`'s
src/config.blsp             ~/.config/bedit/init.blsp — the declarative user config (data, not eval'd).
                            Every key is ONE `settings/define` (std `settings`, brood ADR-428):
                            its default, type and doc give the check, the fallback
                            (`config/setting`) and the generated default file. A package
                            declares its own under `:bedit/settings`. `:undo-limit` /
                            `:undo-strong-limit` are std/editor/buffer's undo cap (brood
                            ADR-550), `def`'d image-wide so buffer processes trim by them too
src/userkeys.blsp           init.blsp's `:keys` (global-set-key) and `:mode-keys` (define-key in a
                            mode's map): each key read by std's `key-parse` (brood ADR-535), each
                            command by its M-x name, compiled onto the model as `:user-keys` by
                            `config/apply-to-model` (startup, frames, M-x reload-config) and bound
                            INTO the layers dispatch resolves (`ed-user-scope`, which
                            `userkeys/ed-scope` returns) — so C-h k / where-is report them too. A
                            mode's bindings go into the layer of that name, even one whose module
                            loads later; the global ones into the profile's base layer.
                            M-x global-set-key / local-set-key (help's, over C-h k's key read)
                            bind live into the same `:user-keys`, kept as `:session-keys`
                            across a reload unless init.blsp binds that key (`ed-merge-session-keys`)
src/about.blsp              M-x version · --version · C-h C-a *About bedit* — bedit's version,
                            the brood under it and the build date, all from project-release/build-info
                            (named to dodge std's `version`, whose `version/newer?` packages uses)
src/slowlog.blsp            the SLOW-TURN LOG: every turn of the loop the watchdog reports slow (brood
                            ADR-490) kept across sessions in state/slow-turns.blsp (rotated at 256 KB),
                            and M-x slow-turns ranking them by what they were folding; on only once
                            `main` activates it, so a test never writes the user's file. The loop runs
                            `(proc/flag :responsive true)` (brood ADR-517), so every `os/cmd` it makes
                            arrives as `[:blocking-call …]` and is logged here too, phase `blocking`.
                            And KEY-TO-PAINT latency as a distribution (brood ADR-612): the idle
                            beat records the window's key histogram (`gui/latency-histogram`) every
                            few hundred keys, quitting records the rest, and M-x slow-turns heads
                            with p50 / p99 / p99.9 over every session (M-x latency: this one).
                            Measuring is for CI or the other machine: tests feed made-up histograms
src/theme.blsp              every colour the editor paints (Catppuccin Mocha), referenced by role;
                            the TEXT-EMPHASIS TIERS chrome names (`*fg-code*` · `*fg-chrome*` ·
                            `*fg-chrome-dim*` · `*fg-tertiary*` · `*fg-decor*`, APCA Lc 75 / 60 / 45 /
                            30 / 15), so quieter chrome is one edit; `apca-lc` / `wcag-ratio`, with
                            which tests/theme_test.blsp holds every registered theme to them. The
                            mode line is recessed (the mantle, secondary text; colour only for a
                            state: modified `●`, `Def`, a failing check); the gutter is the base, its
                            current number lavender
src/systemtheme.blsp        with no `:theme` named, the window follows the desktop's light or dark setting
                            (brood's `gui/color-scheme`): `:theme-light` / `:theme-dark` at startup, and a
                            change re-themes live (asked again every 30 s, off the loop)
src/themes.blsp             the theme registry (M-x theme-select): a live picker that swaps the
                            whole palette AND the window font — a theme is a plain map, so
                            adding one is data (theme.blsp is the palette; this is the registry).
                            Each names the whole ladder (subtext1, overlay2, lavender); `Catppuccin
                            Mocha Calm` is the restrained-syntax option (Tonsky's Alabaster rules:
                            definitions coloured, calls plain, punctuation dimmed — the
                            `:syntax/definition` and `:syntax/punctuation` faces, brood ADR-614)
src/ownership.blsp          WHO registered each registry row: every `register-*` (model's idle jobs,
                            task replies, event / down / timer handlers, exit queries, post-steps,
                            layout keepers, slot keepers, visit steps; statusbar chips; M-x commands; keymap profiles;
                            modes, file patterns and interpreters; themes; chrome faces; vcs
                            backends; grammars; language specs) writes through `claim!`, which
                            records the file being loaded (`reflect/current-file`, or the bound
                            `*claimant*` outside a load) as a STACK over the row that was there
                            before. `release-under! dir` takes back every row a file under `dir`
                            claimed in one call, giving a replaced core row back. A registry kept
                            outside `std/registry` (the theme list, editor/layers' tables)
                            declares how to read / write / remove a row (`define-kind`); std's
                            `settings/define` is `adopt!`ed after a package's load. At RUN TIME
                            a package's command (key dispatch, M-x) and hook (`ed-call-deferred`)
                            run under the claimant of their symbol's namespace
                            (`with-symbol-claimant`, `own-namespace!`), so a row its code
                            registers as it runs is the package's too
src/package-store.blsp      what is on disk under ~/.config/bedit/packages: installed packages, their
                            manifests, source files, modules and declared settings. Files only
src/package-ledger.blsp     what a loaded package did to the image, so it can be taken back:
                            `note-loaded` records a load, `retire-package` undoes one (below).
                            No network, no buffers, no model
src/package-review.blsp     what an update would change, read from the disk in the update's task:
                            the installed copy against the staged one as unified-diff files
                            (`tree-diff`), the CHANGELOG entries between the versions, and the
                            *Package Diff: NAME* section tree, painted as every diff
                            (vcsproc's hunk sections) — and update-all's one *Package Diff*, a
                            folded section per package (`review-all-tree`). Applying / dropping is packages'
src/packages.blsp           bedit's package manager (M-x package-list): install / update / remove
                            hive packages that `:enhances bedit` at RUNTIME, into
                            ~/.config/bedit/packages (the elpa model) — never the build's _deps.
                            The list fetch, an install and an update run OFF the loop (a task in
                            `:package-job`: one at a time, C-g stops it, C-x C-c asks), each a
                            failure CARRYING ITS REASON (brood ADR-559) said in the echo area
                            and on *Packages*' status line. An install lands in a staging dir
                            and moves into place only when it verified and enhances this bedit,
                            so a failed or cancelled one keeps the copy there; an update RETIRES
                            the old version first (`retire-package`, ONE call): every bedit
                            registry row it made taken back (`ownership/release-under!` — idle
                            jobs, task replies, handlers, exit queries, chips, commands, modes,
                            file types, settings, themes; a core row it replaced comes back);
                            every std registry entry its loads wrote DIRECTLY (brood's
                            `registry/written-by` over its modules and, for a file with no
                            `defmodule`, the file's path — editor/layers' tables, faces, a
                            `registry/put!` of its own) taken back, a map entry it replaced given
                            to the layer below it through a per-entry STACK (two packages writing
                            one entry come off in either order), conditional on the entry still
                            being the package's (brood ADR-582); any row
                            still NAMING the package (a hook symbol in its namespace, a function
                            defined there) dropped as a backstop; every core global it REDEFINED
                            restored through a per-global STACK (two packages patching one
                            function come off in either order, the live patch always the top
                            one's); and every global it FIRST defined removed (`plugin-definitions`:
                            noted at load — sited under its dir and unbound before, a file with no
                            `defmodule` included — brood's `reflect/undef`; a core name is never
                            undefined). Open buffers in a mode it took away are seeded again —
                            the new version's mode, the core one it replaced, else fundamental,
                            said in *Messages* (`ed-settle-package-buffers`, Emacs's
                            `unload-feature`) — then it reloads the sources in load order (brood's
                            `reflect/source-load-order`); a remove retires the same way. Both are
                            model-level (`update-plugin!` / `remove!` take and answer the model),
                            so every caller puts the buffers right; docs/packages.md has the one
                            limit (KI-356). What
                            became of each installed package
                            is kept (`package-status`: loaded / broken / incompatible, with the
                            reason): startup says every one it did not load in *Messages*
                            (`load-problems` — a bedit upgrade past a package's range is said,
                            not dropped), *Packages* and C-h P mark it. A package prompt (M-x
                            package-install, C-h P) fetches the list itself when it has none,
                            saying so (`package-prompt`); `package-info` is what C-h P shows.
                            An update is SHOWN first (`:package-review-updates`, default on):
                            staged off the loop, *Package Diff: NAME* (package-review), C-c C-c
                            moves the staged copy in and applies it, C-c C-k / q deletes it;
                            an open review's staging dir is kept in `:packages/reviews`.
                            M-x package-update-all (U in *Packages*): ONE job stages every
                            outdated package side by side (`.staging-<id>-<name>`), ONE
                            *Package Diff* (a folded section each, `review-all-tree`), C-c C-c
                            applies all, C-c C-k drops all; a failed one is named, the rest go
                            on; without review each is applied as it lands.
                            The registry calls are `*registry*` (tests stub it)
src/help.blsp               the C-h map: C-h b / m / w / a / l / k, C-h f (a function's *Help*
                            page: the whole docstring, keys in force, arguments, signature,
                            module and source line — brood's reflect, seeing through contract
                            shims, ADR-560) and C-h v (an init.blsp setting's page: doc, type,
                            default, the value in effect and whether init.blsp or the default
                            gave it, per-mode values, a session change, an unloaded edit) and
                            C-h P (a package's page over `packages/package-info`: installed or
                            not, version against the hive's, enhances, themes, settings)
src/panes.blsp              pane-layout geometry: the body rect, a pane's cell, the gutter's width, and
                            the row table every row↔line question reads (`ed-pane-rows`), from
                            the pane's start row
src/spancache.blsp          what a pane is coloured with, kept across frames: fontified a window at a
                            time, a band from a held tree or a line cache, a long line clipped to
                            what is shown; the gutter's cells likewise; `ed-refresh-spans` once per
                            event. `ed-visible-windows`, the char ranges a per-window highlight reads
src/scrollbar.blsp          the overlay scrollbar: the thumb as render ops, the pointer's grab and drag,
                            its fade; `model/ed-scrollbar-wake` stays below it, as every scroll calls it
src/mouse.blsp              `[:mouse …]` folded into the model: a click, a drag selection, the
                            scrollbar's thumb, a divider's resize, the wheel on the pane under the
                            pointer. A middle click places point (`ed-mouse-set-point`) and commands
                            yanks PRIMARY there, read off the loop (Emacs `mouse-yank-primary`).
                            A C-M-drag selects a rectangle (`:rectangle?` on the `:text-drag`).
                            A press on an INLAY row (`panes/ed-pane-inlay-row`) goes to its
                            owner's `model/register-inlay-click` (a code lens runs), else to its line
src/view.blsp               pure view: model -> render frame (editor/display ops). Names no
                            feature: a pane body's layers share ONE geometry map, the mode
                            line's feature chips come from the statusbar registry, and what
                            else paints is a row in `model`: `register-highlight-source`
                            (`{:rank :run :deps}`, a pane's ranges: rainbow, glyphless,
                            whitespace, spell, isearch, other participants' selections; `:deps` is
                            every input off the buffer, in the pane's memo key, or paint goes
                            stale — tests/view_memo_test), `register-pane-layer` (`{:rank :slot
                            :run :deps}`: the pulse, the header line, and in the `:with-text`
                            slot — memoised with the text, scrolling with it — other
                            participants' carets) and `register-frame-overlay`
                            (`{:rank :run}`: the minibuffer list, avy, which-key, the popup, the
                            transient, the menu, the tooltips). A row's module is `:use`d from
                            `main`: an unloaded row paints nothing (tests/registries_test
                            pins the lists). A `:line-services-off` buffer (so-long) gets no
                            bracket match. The frame names the bottom mode line as its SEAM (`ed-seam-op`, brood
                            ADR-610): the window anchors it and the echo area to its bottom edge
                            and puts the leftover pixels above it; row 0 is a band (no top
                            margin) only under a header line
src/panegeometry.blsp       a pane body's geometry map and the named column spans every layer
                            measures with (the view's lowest layer)
src/spanpaint.blsp          what colours a line: the span band sliced per line, the layers under
                            the mode's colours, bracket overrides, the highlight ranges
src/panebody.blsp           one pane's body: visible rows (folds, wraps), each row's text and the
                            gutter beside it
src/linkview.blsp           the pointer and hover band over a clickable location
src/eolview.blsp            end-of-line notes and the inline completion preview, as painted
                            (`view` is now the pane, its chrome and the frame over these)
src/hittest.blsp            the mouse side of the view: every hit-test / hover fold that takes
                            a model and returns one (:hover, :diag-hover, :link-hover, a chip
                            click, the context menu's hit) — recomputed from the same widget /
                            segments / layout the view drew, so input never imports the renderer
src/echoarea.blsp           the echo area under the bottom mode line as render ops: the message or eldoc
                            line, the minibuffer's prompt and candidate list (Plume), the which-key grid
                            — paged when it does not fit (`ed-which-key-pages`, the last cell
                            `page 1/3 · C-h n/p`, the page `whichkey/page`)
src/whichkey.blsp           C-h after a prefix (Emacs which-key's `which-key-C-h-dispatch`): the
                            paging menu — n / p turn the panel's page, u takes the chord's last
                            key back, h lists every binding under the prefix in *Help* (Emacs's
                            describe-prefix-bindings), a / C-g abort; any other key goes to the
                            prefix, so the chord still completes. A prefix that binds C-h keeps
                            it. `input/ed-dispatch` asks it before the keymap
src/modeline.blsp           a pane's mode line: its segments (`ed-statusbar-segments`, the registered
                            chips included), the bar painted from them, the pointer's layout and the
                            hover tooltips. What `hittest` asks again, so `input` never imports the view
src/overlayview.blsp        the cards over the panes as ui-kit widgets: the context menu and the
                            transient menu, paint and zones in one pass
src/codecrumbs.blsp         the header line's crumbs for code: the definitions around point by name, off the
                            held parse (each `deflanguage` names a `:breadcrumbs` that calls it); a Lisp's
                            top-level form
src/headerline.blsp         the HEADER LINE above each pane (Emacs breadcrumb-mode, on with `:header-line`):
                            the file by its project and path, then the mode's `:breadcrumbs` at point
                            (an Org heading's path); the layout takes the pane's top row for it
                            (`panes/ed-header-layout`), so nothing below knows it is there; a mode whose
                            first line already says where it is declares `:header-line false` (dired)
src/pulse.blsp              a flash on the line after a JUMP (Emacs pulsar, `:pulse`): a post-step row tells a
                            key command's jump (another window or buffer, 5+ lines) from typing and
                            the mouse by `:command-count`, a timer fades the band the view lays over it
                            (280 ms). A held key (an OS repeat, `:key-repeat` from brood's
                            `gui/key-repeat?`) starts none; under `:reduce-motion` the band is still
                            and the next command clears it. `:reduce-motion` (`:auto` follows the
                            desktop, brood's `gui/reduce-motion?`) also snaps the scroll settle, hides
                            the scrollbar without a fade and stills the spinner
                            (`model/ed-reduce-motion?`); a key settles a scroll ease at once
src/winner.blsp             C-c ← / C-c → window-layout undo and redo (Emacs winner-mode, `:winner`): a
                            post-step row keeps the layouts the window SHAPE changed from, carried
                            with their buffers' text (`model/register-layout-keeper`)
src/tabbar.blsp             TABS (Emacs tab-bar-mode, C-x t …): each tab a window LAYOUT and its own
                            winner history (`:tabs`, `:tab-index`; the live tab's layout is `:layout`).
                            The row shows with `:tab-bar` or 2+ tabs and takes row 0 from the layout
                            (`panes/ed-tab-bar-rows`, `ed-body-rect`); a kept tab follows a kill (a
                            slot keeper) and its text (a layout keeper); a click is
                            `hittest/ed-tab-bar-click`; lastsession saves the tabs. Per frame
src/whitespace.blsp         trailing whitespace and tabs as highlight ranges (Emacs whitespace-mode,
                            `:show-whitespace`, per mode through `scroll/ed-mode-setting`)
src/fillindicator.blsp      the fill-column rule (Emacs display-fill-column-indicator-mode,
                            `:fill-column-indicator` per mode, M-x display-fill-column-indicator-mode
                            per buffer): `│` at `conventions/fill-column` on each row that leaves
                            it empty, a `:with-text` pane layer; hscroll moves it, a wrapped row is
                            measured from its start, a clipped (truncated) row gets none
src/glyphless.blsp          the invisible format characters SHOWN (Emacs glyphless-char-display):
                            brood lays a zero width space, a BOM mid-text, a tag character out as
                            its `<200b>` escape (ADR-556, bound by `conventions/with-cell-layout`
                            from `:glyphless-chars`); this module gives the escape its face, and a
                            bidi control (Trojan Source) a hazard face. The minibuffer shows them too.
                            A no-break space (U+00A0, U+202F) is underlined in the escape colour
                            (Emacs nobreak-char-display, `:nobreak-char-display`, on by default)
src/rainbow.blsp             a tree-sitter buffer's brackets coloured by depth (Emacs rainbow-delimiters,
                            `:rainbow-delimiters`): delimiter tokens of the held parse, the window's top
                            depth from the tree; the Lisp modes colour theirs in their own lexer
src/avy.blsp                jump to a visible position by label (Emacs avy): C-' char-timer, M-g w / e
                            word starts — targets from each pane's row table, over the read-char overlay
src/embark.blsp             C-. act on the thing at point or the selected candidate (Emacs embark): the
                            target (region > URL > file > symbol), a transient of actions that NAME
                            existing commands, C-; its default, C-h B every binding as a prompt
src/spell.blsp              spell checking (Emacs jinx, `:spell-check`): the visible prose, and the
                            comments and strings of code, checked off the loop by a long-lived
                            `enchant-2 -a` (else aspell); M-$ correct, C-M-$ the dictionary. The
                            word being typed (point at its end) is not underlined until point
                            leaves it, as flyspell judges a word
src/cape.blsp               completion sources beside the mode's (Emacs cape): file paths, and words
                            from other open buffers, ranked after this buffer's
src/savehist.blsp           minibuffer answers kept per prompt across sessions (Emacs savehist,
                            `:savehist`): seeds the prompt's ↑ / M-p history; off until `main` turns it on
src/passwd.blsp             a password a program asks for (Emacs read-passwd + comint's
                            password watch): `ed-read-passwd`, a MASKED minibuffer read (`*`s
                            via `minibuffer/mb-shown-text`, no history, no savehist, no embark, no
                            macro recording; slow-turn tags of typed keys are `:text`), and
                            `password-prompt?`, comint's prompt regexp (case-folded `(?i)` and
                            `[[:alpha:]]`, brood ADR-573) — the fallback for the
                            shell's pipes and for a raw-mode program the pty cannot read.
                            What the terminal and the shell share: `take-since-prompt` (text
                            typed after the prompt APPEARED — from the `mark-prompt` marker
                            the watch drops, which edits shift — moved into the read by
                            `redact-region`, brood ADR-581: out of the buffer, its undo
                            history and every hosted copy; type-ahead from before the prompt
                            stays as the next input, as comint leaves it) and
                            `secret-key?`, the typing key that opens a read asked for while
                            you were elsewhere (`secret-overlay`, here, over each mode's `:secret-pending?` / `:secret-key` facets)
src/lastsession.blsp        the last session in a project reopened (Emacs desktop-save-mode, `:restore-session`):
                            quitting keeps the files and the pane layout (each pane's file, scroll,
                            point) under the project the editor STARTED in (`:session-root`); a start
                            there with no file named opens them again; a file gone since is skipped
src/saveplace.blsp          a file reopens where it was left (Emacs save-place, `:save-place`): its
                            point kept when its buffer is killed or the editor quits
src/reopen.blsp             a killed FILE buffer opened again (C-x x U, M-x reopen-killed-buffer;
                            bug#51883, a browser's reopen-closed-tab): a slot keeper (order 12)
                            keeps each killed file's path, point and window start on `:killed-files`,
                            newest first, capped; a file gone since is skipped and said
src/solong.blsp             so-long (Emacs so-long-mode, `:so-long-threshold`): a file opened with a line
                            longer than the threshold truncates (`:long-lines :truncate` on the buffer)
                            and the per-line services (show-paren, rainbow, whitespace, spell, eldoc)
                            skip it; the long line is found by sampling every threshold-th char.
                            M-x so-long-mode toggles it
src/statusbar.blsp          the mode line as extensible segments (render ops + click/hover zones in one pass),
                            and the chip REGISTRY (`register-modeline-segment`): a feature puts
                            its chip on the bar when its module loads — presence (collab), the
                            running app (apprun), the findings count (results), the attached
                            node (attach) — ordered by rank
src/ui-kit.blsp             the widget kit over editor/display: a widget is `(area ctx) ->
                            {:ops :zones}` — paint and hit-test in ONE pass, styled by semantic
                            role. The shared shape behind the context menu, popup, plume, which-key.
                            And the ONE SPACING TABLE (`ui-spacing`: rows vertically, cells
                            horizontally, half the only fraction, a card 1 row : 2 cells): a
                            style's `:pad` / `:inset` / `:gap` names a token, `ui-space` raises on
                            a raw number, tests/spacing_ratchet_test fails on one in src/.
                            And the ONE PLACEMENT RULE for a floating card (`ui-place`): the
                            transient, context menu, completion + info card and tooltips keep
                            `:card-gap` off the mode line / echo area / header line and the
                            window's edges, over the stage `panes/ed-card-stage` names
src/events.blsp             what reaches the loop besides keys, one `[:tag …]` handler each by symbol:
                            resize, mouse, a task's reply, a process down, redirected output, a
                            client's identity. A feature's own tags register in `model`
src/input.blsp              dispatch: fold a key or tick into the next model, first through the
                            key overlays (`model/register-overlay`, `rank` order, listed here
                            with why, pinned by tests/registries_test; each feature's in its
                            own module), the post-event step
                            (`ed-post-step`); and the
                            keyboard-macro REPLAY (`ed-run-macro`): N passes (C-u N C-x e), or
                            until one fails (C-u 0), each stopping at the first key whose
                            command fails (`model/ed-ding` or a throw), as Emacs's does — in
                            SLICES of `*macro-slice-ms*` resumed by the `:macro-continue`
                            ticker, so C-g between them quits the run (its work kept) and other
                            input waits for it (`:macro-typeahead`)
src/commands.blsp           the commands left once each family had a module: buffers and their
                            prompts, M-x, the prefix argument, keyboard-quit, profiles and the
                            everyday tail (buffer list, dabbrev, line utilities), and what a
                            guest may run. Each command is a (model key) -> model, bound by
                            qualified symbol; a family's commands live in its own module:
src/motion.blsp             moving point (chars, words, screen rows with a goal column, paragraphs,
                            C-v / M-v, C-l / M-r, shift-select, M-g g / M-g c)
src/structural.blsp         C-M-* motion and paredit edits over the held tree or std's `sexp`, and
                            the held-tree helpers structural queries share
src/indent.blsp             TAB, RET (a line opened between a pair), region indent / dedent, C-M-q,
                            and electric indent (a closer or a mode's block word reindents its line)
src/typing.blsp             self-insert, newline, the delete keys, delete-selection, the electric
                            bracket keys
src/killing.blsp            the kills and yanks (coalescing, M-y, C-u N C-y), zap, rectangles, the
                            middle click's PRIMARY yank
src/editing.blsp            open-line, transposes (negative arguments drag backward), duplicate /
                            join, case, undo / redo, and C-x C-q (`cmd-toggle-read-only`), which
                            asks the MODE (`modes/writable-policy`): the flag, the mode's edit
                            variant (entered or left), or a refusal — never the flag under a mode
                            whose letters are commands; a guest enters no variant it may not run
src/region.blsp             the mark commands, narrowing, `ed-active-region`, rectangle-mark-mode (C-x SPC:
                            `:rectangle-mark` on the buffer, painted as a block, C-w / M-w / C-y act
                            on it through `killing`; dropped by a post-step once the mark goes)
src/search-commands.blsp    the entry points of isearch, occur, the fuzzy line search and the
                            query-replace prompts (the loops are isearch's and query-replace's)
                            Other features' commands live with them (dired, help, vim, registers,
                            hexl, eval-commands, shell-command). Split with brood's `nest move`,
                            which moves a definition and points every reference at it
src/comment.blsp            M-; comment-dwim (Emacs newcomment): the mode's `:comment-syntax` token,
                            or a block-only language's `:comment-block` pair round each line
src/kmacro.blsp             C-x ( · C-x ) · C-x e, the keyboard-macro commands (Emacs kmacro);
                            the recording and the replay are `input`'s
src/yankmedia.blsp          M-x yank-media (Emacs 29's): the clipboard's IMAGE (`os/clipboard-image`,
                            read off the loop on `:yank-media-proc`, C-g cancels) handed to the mode's
                            `:yank-media` facet; Markdown and Org save the PNG beside the file (name
                            asked, `image-<timestamp>.png` by default) and insert `![](name)` /
                            `[[file:name]]`. No handler, no image, a served session: said
src/browse-kill-ring.blsp   M-x browse-kill-ring: *Kill Ring*, newest first, RET inserts the
                            entry where it was opened from (the ring is `clipboard`'s)
src/window-commands.blsp    the window commands: tiled splits, windmove and Emacs's
                            windmove-swap-states-* (C-S-arrows and s-S-arrows), window-swap-states,
                            the C-x 4 prefix; a side window's `:side` mark stays with its PLACE
                            (`ed-keep-sides`)
src/textops.blsp            the commands that rewrite text in bulk: case, whitespace, the replace
                            family, tabify, reversing and deduplicating lines, align-regexp
src/bufferops.blsp          pure buffer -> buffer text operations under the commands: paragraph and
                            sentence motion, whitespace around point, join-line, rectangles (moved
                            from std's `editor/buffer`, brood ADR-417, ADR-630)
src/lifecycle.blsp          the file and session commands: write and revert a file, reload the config,
                            quit with its questions (`ed-map-y-or-n`, what is still running)
src/project-commands.blsp   C-x p f over a file list cached per root, refreshed off the loop; C-x p p
                            picks a project and what to do in it; C-x p k closes one
src/electric.blsp           electric pairs (Emacs electric-pair-mode) as POLICY: the pairs are the
                            MODE's — a layer's `:electric-pairs` (a `deflanguage`'s `:pairs`: `'`
                            where it opens a string, a backtick in Markdown / JS / Go / shell,
                            Python's triple quotes), else `()` `[]` `{}` `""`; `<>` nowhere — the
                            user's `:electric-pair` per mode (a bool or the mode's pairs), Emacs's
                            inhibit rules (not before a word or the same character; a Lisp's
                            `:electric-pair-inhibit :never` always pairs, as paredit),
                            electric-pair-preserve-balance (an opener a waiting closer balances is
                            typed alone; a closer is stepped over — past spaces, tabs and newlines —
                            only while the brackets stay balanced; `:electric-pair-preserve-balance`
                            per mode), a quote's open / close / skip
                            read from the STRING STATE at point (`stringstate`), and M-x
                            electric-pair-mode / electric-pair-local-mode. The bracket keys stay in
                            `commands`, and any character a mode pairs is electric through
                            `cmd-self-insert`; an opener or closer over a region wraps it, mode on
                            or off
src/stringstate.blsp        where a buffer's strings and comments are (Emacs's syntax-ppss, for
                            strings), from the mode's `:string-syntax` as DATA (a `deflanguage`'s
                            `:strings`: delimiters, which span lines, which are raw, line and block
                            comments, the shell's word-start `#`, Rust's char literals; else its
                            quote pairs as one-line strings). INCREMENTAL, as syntax-ppss's cache:
                            what each line starts inside lives in the model's `:string-caches` (std's
                            line cache, `line-cache-state`, brood ADR-591) and edits move it by the
                            splice log, so a key lexes its own line (~5 ms at the end of a 1 MB
                            file). A key never walks a cold region: it lexes at most `*key-lines*`
                            (`line-cache-state-within`) and past that guesses from the nearest
                            top-level form; a large buffer's cache is built off the loop (stringwarm).
                            The held tree-sitter parse answers first when it is current and whole.
                            Brackets are counted from point's top-level form forward until they
                            close; electric pairs ask it to open, close or skip, M-q for the string
src/stringlex.blsp          the line lexer a string syntax becomes: what a line leaves the next one
                            inside, its fast path. Pure, so the warm task shares it
src/stringwarm.blsp         stringstate's cache built off the loop: at once on a large visit or a
                            guess (a post-step, order 60), and on the idle beat (order 95)
src/fill.blsp               M-q and auto-fill over std's `string/fill` / `string/fill-prefixes`
                            (brood ADR-589, Emacs's adaptive fill): the first line keeps its
                            prefix, the rest the paragraph's continuation — a list item HANGS under
                            its text, a comment / quote keeps its marker — the MODE's markers
                            (`stringstate/fill-markers`, which the `:adaptive` wrap prefix shares: its comment tokens, a C block comment's ` * `; so
                            `#include` is code). The paragraph is
                            narrowed to point's comment, list item, or (in code) a string that
                            can span lines — its text only, the code around it untouched
                            (`stringstate/ed-string-extent`, no grammar needed); a mode's `:fill-separate`
                            lines (an Org heading, a Markdown fence) stand alone and its
                            `:fill-prefixes` answers for it (a Lisp docstring continues at column
                            0). M-x auto-fill-mode per buffer, `:auto-fill` per mode — in code only
                            comments break
src/registers.blsp          registers (C-x r SPC / j / s / i) behind a `Register` ability, and
                            bookmarks (C-x r m / b)
src/charset.blsp            the encodings a file may be in besides UTF-8 (Emacs's coding systems):
                            the single-byte ones as DATA (`charset-tables`, one row each, generated
                            from iconv by tools/gen-charset-tables.sh) and UTF-16. `detect` says what a
                            file's bytes are: the charset its `.editorconfig` declares, a UTF-16 mark,
                            UTF-8, a binary (a NUL or a control byte: the hex view), a SCRIPT (Cyrillic,
                            Greek, Hebrew, Arabic: high bytes running together, mostly the row's
                            `:common` letters; KOI8-R told from windows-1251 that way), else init.blsp's
                            `:file-coding`, which is what tells Polish from French. Every byte comes
                            back on a save. No multi-byte legacy coding (Shift-JIS, GBK, Big5). A buffer in one
                            remembers `:coding` beside `:eol` and `:bom` (the registry `:meta` carries
                            it, the mode line shows it); `charset/save` writes it and refuses a
                            character it has no form for, leaving the file (`file-content`, which a
                            root file's save shares). `tool-view` is the text as a program's captured
                            output shows the file, which is what the diff gutter compares with
src/filecoding.blsp         C-x RET f (the next save's coding) and C-x RET r (read the file again as
                            another coding or the hex view): how a file reads is a guess, and this
                            overrules it either way. A file edited as root reads through sudo
                            (`sudoedit/ed-sudo-revert`, M-x revert-buffer too)
                            A file MIXING line endings (read as LF, its CRs kept) is said on visit
                            (a visit step) and M-x convert-line-endings makes it all LF or CRLF,
                            one undoable edit
src/imageview.blsp          an image (PNG, JPEG, GIF, WebP, BMP) opens as a picture: ONE brood `[:image …]`
                            op (brood ADR-686) over the pane's text area — a window paints it at full
                            pixel resolution, a terminal in half-block cells; never enlarged, top-left
                            (a buffer's `:image-placement` overrides: doc-view fits and centres a page);
                            one that does not decode is hex
src/docview.blsp            a PDF opens as its pages (Emacs doc-view, the `:document` presenter): each page
                            drawn OFF the loop (`:docview-proc`) by `pdftoppm`, else `mutool draw`, into
                            a PNG cached under state/cache/docview/, and painted by imageview's layer
                            (`:image-bytes`, refitted on a resize or zoom). n / SPC / PageDown, p / DEL /
                            PageUp, M-< / M->, g a page; the mode line `Page 3/12` (`pdfinfo`). No
                            rasteriser: the hex view, said. `:no-write`. Tests bind `*which*` / `*run*`
src/hexl.blsp               hexl-mode: a binary file opened as a read-only hex view (pool's
                            find-file reaches it late-bound); the mode's `:no-write` facet is
                            what makes C-x C-s / C-x C-w refuse it
src/pool.blsp               the buffer pool and where its buffers are shown — open / select / C-x k /
                            kill, `ed-display-buffer` (Emacs display-buffer: init.blsp's
                            `:display-buffer` RULES first — `{:match name-regex | type-or-mode
                            :request :action :same-window | :other-window | :reuse | {:side
                            :size} | :new-frame}` — then the defaults, rules too,
                            `display-rules/*display-buffer-defaults*`; a side window is `editor/pane`'s
                            `pane-split-edge`, brood ADR-590, its pane marked `:side`; a new frame
                            is `frames/frames-spawn-showing`), `ed-pop-to-file`
                            (next-error), find-file + its path prompt, the default dir and
                            project root. A person's visit of a file over `*read-off-loop-bytes*`
                            (2 MB; `ed-find-file-soon`, `ed-visit-file`'s opener) is read OFF the
                            loop: a read-only `Loading…` buffer at once (`file-loading-buffer`, a root
                            read's too), the file in its place in every pane showing it when the
                            task lands (`:read-proc`, one at a time); killing it or C-g cancels.
                            `ed-find-file` stays on the loop for callers acting on the buffer
                            at once; a JUMP waits instead — `ed-pop-to-file` (next-error, the
                            results buffers), `ed-find-file-then` (an LSP location, a compile
                            error), lastsession's restore and the file named at startup
                            (`reading-off-loop`) — and goes to its line when the file lands.
                            What most modules `:use` instead of
                            `commands`: showing a report buffer needs none of the commands
src/file-save.blsp          writing a pool buffer to its file: `ed-save-buf-at` (a buffer a file
                            handler owns is the handler's), `.editorconfig`'s fix-ups first,
                            the sidecar removed, a hosted slot's process told. Every plain save is
                            two halves (`ed-save-prepare` / `ed-save-landed`, sudoedit's too): the
                            write runs OFF the loop (`:save-proc`, `Saving …` said at once), the
                            buffer marked saved only when it lands and as of the text written (an
                            edit meanwhile stays modified; a failure stays modified, said). One
                            write at a time, the rest on `:save-waiting` by FILE, taking the text
                            when their turn comes; `ed-when-saves-land` is what C-x C-c and C-x s
                            wait on. C-x C-w rides the same queue (`ed-write-buf-as`): the buffer
                            visits the new path only once the write lands, and keeps its old one
                            when it fails. Headless, inline; tests bind `*write-off-loop*` / `*write-file*`
src/menu.blsp               the right-click context menu's model ops (open / move / run /
                            close); an item names its command by SYMBOL, resolved when it
                            runs, so a redefined command reaches the menu too
src/keymaps.blsp            keybinding profiles (emacs / modal vim) as model-scope layers
src/interactive.blsp        the `defcommand` macro + the M-x command registry, command traits, and REPEAT MAPS
                            (`declare-repeat-map`, Emacs repeat-map: after C-x C-M-+ the keys + / - / 0 repeat)
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
                            colouring through `fontify-lines` (spans per line).
                            Those registrations — and `register-type`, `register-file-pattern`,
                            `register-interpreter` — are CLAIMED (`ownership`), so a package's
                            mode goes with it: editor/layers cannot remove a file rule, so each
                            type gets ONE std rule reading its pattern from the claimed
                            `:modes/file-patterns` when it runs
                            And EDITABILITY: a mode's `:writable` facet (`writable-policy`, the
                            decision table per type) — `:toggle`, `{:enter cmd}` (an edit
                            variant), `{:commit :abort}` (the variant), `{:never why}`; a layer
                            binding a printable key to a command must declare it
                            (tests/writable_test.blsp walks every type and presses C-x C-q in each)
src/brood-mode.blsp         brood-mode: the `.blsp` keymap (paredit, electric pairs) and
                            its services — eldoc, doc-at, completion against the live
                            image, the CST indenter, the checker as `:diagnostics`
src/lisp-modes.blsp         the other Lisps: `deflisp` (a special-form set + a file
                            pattern over Brood's own reader) for elisp, Common Lisp,
                            Clojure, Scheme, Fennel; `lisp-indent-with` (Emacs's rule);
                            wos kernel source
src/lang-scripts.blsp       Ruby, Elixir, HEEx, Python
src/lang-systems.blsp       Rust, Go, go.mod, C, C#
src/lang-web.blsp           JavaScript, TypeScript, TSX (each extending the last), CSS, HTML
src/lang-config.blsp        HCL + Terraform, shell, JSON, TOML, YAML, Dockerfile, and the line-lexed
                            formats. All four are `language-core` specs, one file a family
src/language-core.blsp      `deflanguage` declares a tree-sitter language from ONE spec
                            (faces, indent, heredocs, injections, formatter) and generates its
                            whole service set — show-paren (`tsbrackets`) included — checked against
                            editor/treesit/language-contract, so an incomplete language
                            fails at load rather than at the keypress that needed it.
                            Ruby / Elixir / Python / Rust / JavaScript / TypeScript / TSX /
                            Go / C / Terraform + HCL (two modes over one `:hcl` grammar,
                            told apart by `:type`; only Terraform's files take `terraform
                            fmt`), shell (bash), JSON, TOML, YAML and Dockerfile, each naming
                            where its grammar lives AND the commit its tables were written
                            against (`:grammar {:url :revision}`, for M-x grammar-install —
                            each pin the commit the installed library was rebuilt
                            byte-identical from), its names registered for `grammarcheck` — a
                            spec may extend another's (TypeScript is JavaScript's, Terraform
                            HCL's). A language that had a line lexer first keeps it as its
                            `:fallback`: a buffer opened while the grammar is missing is typed
                            as the lexer's stand-in (`model/ed-grammar-fallback`) and becomes
                            the parsed mode when the grammar arrives (`ed-grammars-arrived`);
                            JSON stays lexed past a megabyte (`:fallback-above`). A language with
                            no stand-in (Rust, Go, C) stays its parsed mode without its grammar,
                            and its services answer without one (`spec-grammar?`): no colours, RET
                            keeps the line's indentation, nothing folds — never a parse that
                            raises into the view's `render error`. `:injections`
                            (brood ADR-489) is the code embedded in a language — a Terraform
                            heredoc named BASH / JSON / PY, a Dockerfile `RUN` line as shell,
                            Elixir's `~H` as HEEx (heex-mode) — coloured with the embedded
                            language's OWN spec's faces, found per frame (`modes/language-faces`), so
                            a missing language or grammar keeps the host's colours. `deflexer`
                            is its sibling for the line-lexer languages (a pattern + a `lex-*`
                            stem): env, JSON5, Makefile / INI / commit
src/tsbrackets.blsp         show-paren over a tree-sitter parse: a bracket is a delimiter
                            TOKEN, its partner the matching token under the same parent (so a
                            `(` in a string matches nothing), read off the held tree when the
                            buffer keeps one — every `deflanguage`'s `:bracket-match` /
                            `:bracket-match-tree`. A pair in the middle of its parent (an HCL
                            block's braces) is found among the parent's children, anonymous
                            tokens included (`node-children` all?), with no length cap
src/org.blsp                Org text: `org-spans` (the colouring), and the OUTLINE as facts over
                            lines read one at a time: a heading's parts (level, keyword,
                            priority, title), where a subtree or a list item ends, siblings and
                            parents, the TODO and priority steps, an ordered list renumbered,
                            what a `[2/3]` cookie counts. Pure; org-mode is the mode over it
                            (moved from brood's std by ADR-417)
src/org-mode.blsp           org-mode: the mode over `org` — folding (TAB, S-TAB) and Org's
                            STRUCTURE EDITING: M-RET (a heading or item where point is, splitting
                            at point, before it from its start), C-RET (after the subtree),
                            M-S-RET / C-S-RET (TODO, a checkbox item); M-arrows promote / demote
                            / move a heading or item, M-S- with what is under it (folds carried);
                            S-arrows the keyword and priority (shift-select off a heading);
                            C-c C-c a checkbox and every `[2/3]` cookie above it; C-c C-t,
                            C-c C-n / p / f / b / u; breadcrumbs. Each change is one rewrite of
                            a run of lines (`org-rewrite`), so one undo step
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
                            M-x grammar-list / grammar-reload / grammar-install / grammar-update:
                            what is installed (ABI, path, its revision against the PIN, and the
                            names bedit's tables use that it lacks), fetching and building a
                            declared one off the loop at exactly its pinned revision (std's
                            `grammar-install`, which writes a manifest beside the .so: revision,
                            commit, hash — brood ADR-583; a library with no manifest is
                            compared by its SHAPE, `grammar-fingerprint`, with the pin's
                            recorded `:fingerprint`), moving one back to its pin, and a
                            live swap — drop a new .so in and reload, no restart. An install or
                            reload retypes every open line-lexer stand-in as its parsed mode
                            (`model/ed-grammars-arrived`). A grammar is native code, so brood
                            VETS a library in a child before its first load and refuses one that
                            crashed or hung there, or that crashed bedit (brood ADR-660): an
                            install vets with the grammar's own test corpus off the loop
                            (`*grammar-vetter*`) and says a quarantine, and so does M-x
                            grammar-reload (`:grammar-reload-proc`, C-g cancels, a library loaded
                            only once its verdict lands); the list shows one
                            (QUARANTINED, why) without loading it; its language stands in with
                            its line lexer, as a missing grammar's does (`model/grammar-loadable?`,
                            `missing-note`)
src/grammarcheck.blsp       does the installed grammar still have every node kind and field a
                            mode names? Each `deflanguage` registers the names its face table,
                            indent spec, injections and definitions use (std's
                            `editor/treesit/language-names`); the first use of a grammar checks
                            them against what it contains (`grammar-problems`), kept per language
                            until an install / reload. A failing grammar is reported once in
                            *Messages* (M-x grammar-update) and is not `model/grammar-ready?`, so
                            a language with a line lexer stands in with it rather than
                            mis-colouring. Below `model`, which asks it
src/conventions.blsp        a buffer's INDENT WIDTH, TAB WIDTH, tabs-or-spaces and FILL COLUMN,
                            resolved per buffer: its own (M-x set-fill-column) > its
                            .editorconfig > the user's init.blsp entry for its mode > the mode's
                            convention (a `deflanguage`'s indent `:width`, `:indent-tabs`,
                            `:fill-column`: Python 4 / 79, Go a tab) > the user's `:default` >
                            Emacs's. TAB / RET's indenter, Shift-TAB, M-q, tabify read it; brood's
                            `*tab-width*` (ADR-537) is bound to it once per turn
                            (`input/ed-update`), per pane in the view, and by every `wrap`
                            function handed a buffer (`with-cell-layout`), so a tab SHOWS, moves
                            and scrolls at the buffer's width — and brood's `*glyphless-display*`
                            (ADR-556) beside it, from init.blsp's `:glyphless-chars`, so a zero
                            width space or a bidi control shows, moves and wraps as its `<200b>`
                            escape (src/glyphless.blsp gives it a face) — and an indent target is a COLUMN
                            at it (a Makefile's tab stays a tab); a save trims
                            and adds the final newline when .editorconfig asks (a new file takes
                            its end_of_line, and with charset = utf-8-bom a byte-order mark —
                            brood's `:bom`, a file's mark kept off its text and written back
                            (ADR-563); an existing one's mismatch is said, not converted).
                            M-x describe-indentation says where each value came from
src/editorconfig.blsp       `.editorconfig` (editorconfig.org): the parser, the section globs
                            (`*` `**` `?` `[…]` `{a,b}` `{1..9}`), the walk up to `root = true`, and
                            the result in the editor's terms — read once when a file buffer is
                            made (`model/ed-stamp`). bedit's, not std's: nothing else wants it yet
src/dirlocals.blsp          a project's `.bedit-locals.blsp` (Emacs's .dir-locals.el): `(dir-locals :key
                            value …)`, DATA, the nearest above a visited file (a visit step,
                            `:passing`) stamped on the buffer as `:dir-locals`. Only a setting
                            declared `:safe true` (Emacs's safe-local-variable: the layout
                            conventions, the display switches) is taken; the rest is refused and
                            said in the visit's note. Resolved after .editorconfig and before
                            init.blsp (`conventions/dir-local`, `scroll/ed-local-setting`); C-h v
                            and M-x describe-indentation name it as the source
src/hooks.blsp              init.blsp's `:hooks` (Emacs's after-save-hook / <mode>-hook) as DATA:
                            `{:after-save [cmd …] :mode {rust [cmd …]}}`, each a command by its M-x
                            name, run in order, one that fails said and the rest run.
                            `:after-save` from `file-save/ed-save-landed`, the saved buffer made
                            current; `:mode` a post-step, the first time a buffer is current in a
                            mode (`:hooked-mode`), the most general mode first
src/formatter.blsp          M-x format-buffer + format-on-save: the language's own
                            formatter (mix format, black, rubocop), declared per language
                            and run over the FILE, so a failing formatter costs nothing
                            (named to dodge std's `format`: a release resolves a std name
                            first, so a project module called `format` never ran)
src/complete-words.blsp     what completion knows of a buffer's words: the word boundary, the rope
                            scan, the `:word-index` built off the loop, the always-on source
src/complete-card.blsp      the popup as drawn: the menu card, anchored where the completion STARTS
                            (Corfu's), so it does not slide as letters are typed into it, and the
                            info card beside it
src/complete-at-point.blsp  completion-at-point (the in-buffer Tab popup) — multi-source merge
                            (named to dodge std's `tool/complete`, which shadows a bare `complete`).
                            The auto popup is per
                            mode (`completion-auto-for?`): the user's `:completion-auto` entry
                            for the mode, else the mode's `:completion-auto` facet — off in
                            text-mode (prose completes on demand, C-M-i), on in prog-mode and the
                            line-lexed config formats. A source's `:snippets` (`{candidate
                            template}`) makes taking that candidate expand it (`snippet`)
src/snippet.blsp            SNIPPETS (Emacs's yasnippet / tempel): templates in the LSP snippet
                            syntax (`$1`, `${2:default}`, `$0`, a number twice is a mirror,
                            `${1|a,b|}`, `$TM_FILENAME_BASE`), parsed here (no second caller for a
                            std parser: std's `template` is `{{var}}` rendering). Per mode: a small
                            built-in set (Brood, Elixir, Ruby, JS/TS, Rust, Python) under init.blsp's
                            `:snippets`. C-c & (M-x snippet-expand) expands the key before point or
                            asks; the keys are completion candidates (`:rank :after`); an LSP item
                            with `insertTextFormat` 2 expands too (`snippetSupport true`, the cut
                            at the first stop kept where it cannot). While one is active (`:snippet`
                            on the model; overlay rank 105) TAB / S-TAB move between fields, the
                            field selected with point at its start and its default replaced by
                            the first thing typed; C-g or point leaving it ends it. Fields are
                            positions carried through the buffer's splice log
                            (`buffer-splices-since`) by a post-step — the field being typed in
                            grows at both edges, which std's left-gravity markers cannot say —
                            and mirrors are rewritten in the typing's own undo group; the
                            expansion is one undo step
src/lsp-protocol.blsp       the protocol, pure: what each answer means, positions in UTF-16 units, the
                            document sync, what each request puts on the wire, and the connection
                            as a state machine (`lsp-ingest`, `lsp-issue`). No process, no server. A server's
                            REFRESH request (`workspace/semanticTokens|inlayHint|codeLens/refresh`,
                            `*lsp-refresh-requests*`) is answered null and queued on `:refreshes`,
                            which the connection sends the editor as `[:lsp-refresh-… conn]`
                            A ContentModified / ServerCancelled answer to what the idle beat asks by
                            itself (semantic tokens, lenses, inlay hints) comes back `:lsp-retry`
                            (`lsp-retry?`), and the fold makes it due again rather than empty
src/lsp.blsp                LSP client (proc-spawn + JSON-RPC) — completion, goto-def/references,
                            hover, rename, format, imenu, INLAY HINTS (the lines on screen on the idle beat, as
                            `inlinetext` annotations owned by `:lsp-inlay`; opt-in per mode by
                            `:lsp-inlay-hints`, M-x lsp-inlay-hints-mode per buffer; the range cut to the text, `inlay-range`,
                            since rust-analyzer answers a position past it with no hints), and `publishDiagnostics` folded into
                            the model's diagnostics, so every language gets the underline / ⚠ note
                            / gutter mark the Brood checker used to have to itself. Answers
                            server->client requests too (`client/registerCapability` — a server
                            BLOCKS on that reply), advertises `refreshSupport` for semantic tokens,
                            inlay hints and lenses and the client commands it runs
                            (`experimental.commands`, `lsp-lens/*client-commands*` — rust-analyzer
                            sends no lens without them), and starts the server IN the project root, which
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
src/lsp-servers.blsp        the servers as the model holds them: where each starts, which projects
                            share one, filing them under `:lsp-servers`, a server dying or merged,
                            the document push, what they published, asking one — about any pool
                            buffer (`ed-lsp-ask-server-at`, `ed-lsp-push-text-at`), and which of a
                            server's buffers are on screen (`ed-lsp-shown`, what a refresh re-asks). lsp-commands is the
                            commands and the folds of their answers
src/lsp-requests.blsp       the LSP request-kind records + `LspRequest` ability — the shape/fold vocabulary
                            shared by lsp (connection side) and lsp-commands (model side); eager-loaded so
                            lsp-commands can register fold impls while lsp stays deferred
src/lsp-semantic.blsp       LSP SEMANTIC TOKENS (`semanticTokens/full`, `/full/delta`): the integer
                            array decoded against the server's legend, a delta applied, each token
                            type + modifiers a `:syntax/*` face (`:syntax/variable` is its own; a
                            definition `:syntax/definition`; strings / comments / numbers left to
                            the mode), stamped on the pool buffer as `:semantic-spans`, which
                            `spanpaint/ed-buffer-spans` lays OVER the mode's colouring. Asked on the
                            idle beat when the text moved (order 55); carried through the splice
                            log by a post-step (order 45) until the next answer, never dropped on a
                            keystroke. `:lsp-semantic-tokens` (default on where offered), M-x
                            lsp-semantic-tokens-mode. A server's refresh asks each of its buffers on
                            screen again (a delta against the last answer, as VS Code asks). Its request kinds and their `LspRequest` impls
                            (all four halves) live here, not in lsp-requests / lsp-protocol
src/lsp-lens.blsp           LSP CODE LENS (`codeLens`, `codeLens/resolve`): each lens a dim INLAY
                            row above its line (`wrap/inlay-lines`, owner `:lsp-code-lens`), titles
                            joined ` | `, indented as the line; anchored by a char offset carried
                            through the splice log (post-step order 46), asked on the idle beat
                            (order 60), unresolved ones resolved, asked again on the server's refresh.
                            A CLICK on a lens row (`model/register-inlay-click`) or M-x
                            lsp-code-lens-run runs the lens: a SERVER command (one it lists in
                            `executeCommandProvider`) through `workspace/executeCommand` (a code
                            action's path: its edits come back as `workspace/applyEdit`), a CLIENT
                            command through `*client-commands*` — rust-analyzer's `runSingle` as
                            its cargo command in *compilation* (`runnable-command`,
                            `compile/compile-run`), `showReferences` / `gotoLocation` a jump or a
                            picker, `debugSingle` said — and any other said, never sent.
                            `:lsp-code-lens` (default off), M-x lsp-code-lens-mode
src/mincomplete.blsp        minibuffer prompt completion (path / name); a directory's sorted listing
                            is a `defmemo` on its path and mtime, asked only once the directory
                            has been quiet a second (a listing in the same clock tick as an entry
                            added could miss it)
src/filename.blsp           a typed path read the Emacs way (`substitute-in-file-name`, which is
                            std's `path/substitute` — this is the prompt's layer over it): the prompt
                            shows the home as `~`, `//` or `/~/` restarts the path (the overridden
                            part painted dim — file-name-shadow), `$VAR`s expand, a name from the
                            disk goes on the line escaped (`$$`), a relative name is read under the
                            prompt's directory. Both path prompts — `pool/ed-path-prompt` (the disk)
                            and `pool/ed-path-list-prompt` (recent files, projects, recover)
                            — hand their consumer the ABSOLUTE path (`filename/expand`). EVERY prompt
                            for a file or folder is one of these two, never a bare line. A prompt for
                            a path that need not exist — C-x C-w, rename-visited-file, dired + R C,
                            git init / clone, a saved attachment or image — is `ed-path-prompt`'s
                            `{:new-name true}`: Enter takes the line as typed, never the first entry
                            listed under it, a blank one is said; a directory answered takes the
                            name (`pool/ed-into-dir`) and a file already there is asked about
                            (`pool/ed-confirm-overwrite`). A prompt opens in a directory spelled
                            as one (`filename/as-dir`, `pool/ed-default-dir-input`)
src/completion.blsp         shared fuzzy ranking + vertical-menu card (complete + plume)
src/dired.blsp              Dired (C-x d, C-x C-j): an `ls -l` listing, its state ON the buffer
                            (`:dired-dir`, `:dired-names` — a line's entry by index — marks, flags,
                            `:dired-links`: a symlink's row ends `name -> target`, `file/read-link`),
                            single keys to open, sort, mark, flag, R / C / D / x (off the loop, one
                            at a time; another machine's directory through its file handler's ops).
                            `ed-dired-rename-entries`: entries renamed to names given, all at once —
                            swaps and cycles through temporary names, `/` moves (parents made),
                            an existing target asked about — and `ed-dired-set-attributes`: links
                            re-pointed (`file/symlink` `{:replace true}`) and modes set (`file/chmod`,
                            brood ADR-697; a handler's `:make-symbolic-link` / `:set-file-modes`) —
                            what wdired applies
src/wdired.blsp             wdired-mode: C-x C-q in Dired makes the file NAMES editable over
                            `editspans` (the columns, header, `.` / `..` read-only; no Dired keymap,
                            so `m` types an m) — and a symlink's TARGET after ` -> `
                            (`:wdired-allow-to-redirect-links`, on, as Emacs) and the PERMISSIONS
                            (`:wdired-allow-to-change-permissions`: off; true — each character a
                            toggle, SPC flips, r w x s t S T - set, through `cmd-wdired-set-bit`, a
                            `:typing` command, so the writable guard holds; `:advanced` — free text,
                            read by `fileperm/perms->mode`). C-c C-c / C-x C-s re-point the links and
                            set the modes first (`dired/ed-dired-set-attributes`), then rename through
                            dired's `ed-dired-rename-entries`, an erased name flags its entry `D`; each
                            change stands alone, a failure said. C-c C-k / C-c ESC put everything
                            back; C-x C-q leaves, asking when changed (`editspans/leave`,
                            dired's `:writable {:enter …}` entering it — dired binds no C-x C-q); C-n / C-p
                            / C-a keep to the name column, RET refused
src/fileops.blsp            what dired's deletes need past brood's `file/`: a path removed for good and
                            what that takes counted. Copy, move and the TRASH are brood's
                            (`file/copy-tree`, `file/move`, `file/trash`; a test binds
                            `file/*trash-home*`, a test run otherwise gets its scratch home's)
src/fileperm.blsp           the `ls -l` permission string (`rwx`, `perms-string`, setuid / setgid /
                            sticky as `s` / `t`) and back (`perms->mode`, wdired) — dired + plume marginalia
src/plume.blsp              the minibuffer completion UI — vertical list + marginalia + N/M counter (our Vertico/Marginalia)
src/debugger.blsp           the editor as the debugger (ADR-174/184): C-c d session, *Spy* trace
                            stream, *Debug* paused-process queue with resume/eval-in-scope,
                            trace-fn/break-fn by name — the collector process speaks std/debug's
                            wire protocol and forwards UiEvent records to the loop
src/testrun.blsp            native test runs (C-c t): the commands and the *Tests* mode; a run goes to
                            a warm session when one is ready, else the cold runner
src/testrun-cold.blsp       a dedicated nest subprocess streams per-test JSON (std's
                            test/*report-sink*) into the *Tests* buffer — never in-image (%isolate
                            would revert the editor's globals + kill its pids). The folds every
                            runner fills *Tests* with
src/testrun-warm.blsp       a project with a WARM test session uses it instead (`*warm-backends*`,
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
src/hosted.blsp             THE FLIP: every pool buffer backed by its own process (hosted-reconcile);
                            the seed and resync carry the text properties (std's `content-view`)
src/frames.blsp             frames (C-x 5 2 / o / 0): a second OS window is a PROCESS with its own
                            ui-run whose pool slots link to the same buffer processes, named by
                            std/editor/buffer-registry — a buffer opened, edited or killed in one
                            frame is in every frame (docs/frames-plan.md); a change another frame
                            made carries this frame's windows, points and `:input-start` with the
                            text (`hosted/hosted-carried`), and its text properties (a log's
                            colours) ride the splice, so every frame shows them; a foreign splice
                            lands on a read-only copy too (std's `buffer-apply-action`), and a
                            redaction (brood ADR-581) redacts every copy, history and all
src/procstream.blsp         the shared streaming-subprocess worker (testrun's :testrun and
                            apprun's :apprun ride it): line-buffered stdout -> handler fns,
                            each line ANSI-decoded (a decoder per stream) with its colour spans
                            and its carriage returns done (the partial line too, so a counter
                            that never ends its line keeps one count);
                            a partial line past `*procstream-line-max*` is delivered as it
                            stands, so the worker's buffer is bounded (an escape cut there
                            waits in the decoder)
src/ansicolor.blsp          a program's ANSI colours on the buffer its output streams into (Emacs
                            ansi-color), over std's streaming decoder (`ansi/feed`, brood ADR-567):
                            a decoder per stream, so an escape split across two reads never leaks
                            (`1mERROR`, issue #24); the SGR attributes laid on the text in the
                            same edit as its `:ansi` TEXT PROPERTY (`faces`, brood ADR-579) and
                            resolved through `theme/ansi-palette` as the view paints them, UNDER the
                            mode's colouring (`view/ed-span-layers`) — so a theme switch recolours
                            them. *compilation*, the shell buffer, *Run* and M-!'s output colour;
                            *Tests* keeps the text; the vcs log is `ansi/render`ed. The colours
                            belong to the characters: the user's edits, undo, the output cap's head
                            cut and another frame's copy (the splice carries them, the seed of a
                            frame opened later too) keep them on the text — nothing carries them here.
                            A lone `\r` rewrites its output line (`carriage` / `insert-output`,
                            Emacs's comint-carriage-motion): a progress counter shows one count
src/wrap.blsp              where a line falls on screen rows: the pure break rule (a line →
                            `[from to]` row segments, wrapped at the pane width where Unicode lets a line break —
                            UAX #14, brood's `string/break-opportunities`: CJK between characters)
                            and the
                            ONE row of a truncated line (`one-row`: cut before the cells its
                            ellipsis takes, never halving a wide glyph; a clip `[cut ellipsis]`
                            rides the row) — per line, by `line-policy`. The row↔line owner
                            (panes), the view and the scroll clamp all read it; point past a
                            cut scrolls that one line sideways (`follow-point`, Emacs's
                            current-line auto-hscroll), a click on `…` goes to the line's end.
                            THE ROW GEOMETRY HELPER: `row-cell` (a char column of a row's line →
                            the cell it is painted at) and `row-column` (a cell → the char under
                            it; `clicked` makes a cut row's ellipsis the line's end), over a ROW
                            ENTRY — the table's `[line from to inlay clip display]`, or an
                            unwrapped pane's `[line hscroll nil nil]`. The caret, a click / drag /
                            hover, C-n's goal column, C-v, the wheel, avy, the region's end band,
                            the notes and a remote caret all convert through these two and nothing
                            else; `line-row-entries` is a line's rows off the visible table. A
                            row's `display` is `{:prefix :inline}`: the WRAP PREFIX (Emacs
                            `wrap-prefix` / adaptive-wrap — a continuation row starts under its
                            line's indent, `:indent`, or fill prefix under the mode's markers, `:adaptive`; the init file's
                            `:wrap-prefix` per mode, `scroll/ed-wrap-prefix-style`; dropped past
                            half the row) and the row's INLINE annotations (`inlinetext`), both of
                            which the breaks leave room for
src/inlinetext.blsp         INLINE ANNOTATIONS (Emacs's `before-string` overlay, what an LSP
                            inlay hint is): `{:at :text :face}` virtual text shown AT a position
                            inside a line, owner-keyed (`set-annotations buf owner [...]`,
                            `clear`), each anchor a buffer MARKER so edits carry it (left gravity:
                            text typed at it lands after it, where the caret is painted). Never
                            buffer text: it takes cells in the row table (`scroll/ed-row-extras`
                            `:inline`, so the buffer lays out row-wise), point cannot be inside
                            it, a click on it is its anchor, a copy never includes it; painted as
                            VIRTUAL chunks (`spanpaint/ed-splice-inline`) in the hint voice
src/folds.blsp              outline FOLDING in an editable buffer (org's TAB): a fold is a
                            marker on its heading, the mode's `:fold-extent` says what it
                            covers, and the row table gives the hidden lines no rows — so the
                            view, cursor, scroll and mouse never see them; point landing
                            inside one opens it. The hidden set is a `defmemo` (per process,
                            brood ADR-670); a miss carries an older answer across an edit the
                            splice log places outside every fold
src/codefold.blsp           code folding, Emacs's hideshow (C-c @): every `deflanguage` gets a `:fold-extent`
                            from its indent spec (a `:blocks` node folds from its parent's line, a
                            `:brackets` node from its own; the closing line stays), a Lisp folds the
                            form opening on a line; over `folds`, Org's mechanism
src/foldview.blsp           a folded line ends in ` …` (a `:with-text` pane layer)
src/xrefgrep.blsp           M-. and M-? with no language server for the file (none configured or not
                            installed): the project searched for a line defining the word (jumped to
                            when it is the only one) or for every use — dumb-jump
src/projectdiag.blsp        C-x p !: every warning and error in the project — open buffers' findings and
                            what the language servers published for files not open — errors first;
                            RET visits, `a` asks the server for the fixes there (code actions)
src/editspans.blsp          the EDITABLE-SPANS mechanism under wgrep, occur-edit and wdired: a
                            generated read-only buffer narrowed to chosen spans (`narrow-to`, so no
                            edit path reaches the rest), the spans as they were kept on it
                            (`:span-edit`, with the type to go back to), switched to an edit type
                            whose layers name NO command keymap — every letter types. `changes`,
                            `restore` (C-c C-k), `finish`, `replace-lines` (a row written over a
                            source line that still reads what it did, else skipped). Every
                            variant's layer is `edit-layer` (C-c C-c / C-x C-s apply, C-c C-k / C-c
                            ESC put back, its `:writable`), and C-x C-q in one is `leave`: back at
                            once, or asking y / n when changed
src/searchedit.blsp         editable search results over `editspans`: wgrep — C-c C-p in *Project
                            Search* opens each row's text (the `file:line:` stays read-only), C-c C-c
                            writes the changed rows to their files' buffers (a line changed since
                            is skipped), C-c C-k puts them back; C-x p % is a project replace over
                            them (query-replace passes over what it may not edit) — and Emacs's
                            occur-edit-mode: `e` in *Occur* opens its rows the same way, C-c C-c /
                            C-x C-s write them to the buffer searched (Emacs writes as you type)
src/isearch.blsp            incremental search (C-s / C-r), a modal mini-loop: regexp
                            (C-M-s / C-M-r, M-r) and word (M-s w) search, M-c case toggle; the `3/17`
                            match count (a timer of its own, a slice of the rope per turn, never on
                            a key) and every visible match lit (`lazy-ranges`), over std regex's rope
                            search (brood ADR-540)
src/query-replace.blsp      query-replace (M-%, C-M-%), a modal mini-loop on isearch's case rule and
                            lazy highlight: C-M-% has `\1` groups. With the region active, M-% /
                            C-M-% stay inside it (`Query replace in region:`): its end moves with
                            each replacement, and a regexp is searched with it as the bound (brood ADR-554). M-x replace-string /
                            replace-regexp are `!` at the first match (`replace-all`): the same
                            search, `\&` / `\1` and case rule, one undo group
src/eval-command.blsp       eval Brood source from a buffer (the C-x C-e core)
src/eval-commands.blsp      the C-x C-e family as commands (eval-last-sexp / -region / -buffer):
                            off the loop as a std/task, C-g cancels; loaded with the image (main)
src/shell-command.blsp      M-! / M-| (Emacs shell-command): one `sh -c` in the buffer's dir, off
                            the loop, output to the echo area or a side pane; C-u M-| replaces
                            the region; C-g stops the command itself (brood ADR-514). Loaded
                            with the image (main)
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
src/tutor.blsp              the interactive Brood tutorial (C-h t): the *Tutorial* buffer, its pages,
                            commands and mode; the prose guard
src/tutor-course.blsp       the course as text: the keys asked of the live keymaps, the sections, a
                            lesson rendered, the contents page, the box syntax (`tutor-regions`)
src/tutor-live.blsp         the boxes as they run: eval-on-type in the sandbox, ✓/✗ gutter, ghost
                            results, progress on disk, the checker's warnings; the third client of
                            playground-core
src/aside.blsp              the PREVIEW PANE mechanism every side pane is a small spec over
                            (`{:key :buffer :type}`): shown beside the page, refreshed in place,
                            latched closed once the reader closes it, its key a `toggle`, a
                            follower on a clock re-showing it only when a staleness key moved
                            (`sync`), data riding onto its buffer (`:fields`), taken with its
                            source (`close-with`), scrolled to a line or level with the source
                            (`scroll-to-line`, `scroll-top-to`). Clients: mdpreview, diagnostics,
                            the time machine's commit pane, and workings'. Where and how wide:
                            the `:display-buffer` rules
src/workings.blsp           the "show me how it actually ran" pane over `aside`: the per-region
                            report cache and the rule for what earns a split — the tutorial's
                            *Workings* (`tutor-live/*workings-spec*`) and the two playgrounds' spy
                            panes are its clients
src/mdpreview.blsp          C-c C-p in a .md buffer: the document rendered beside it
                            (std's `markdown-render`, faces as data on the buffer), following
                            the cursor per key, level with the source's scroll (a post-step),
                            re-rendering on the idle beat off the loop (`:on-idle`), and opening
                            on its own with init.blsp's `:markdown-preview`
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
                            only in a pane already at the bottom, then caps the buffer
                            (`model/ed-cap-output-at`)
src/eolnotes.blsp           END-OF-LINE NOTES: derived text shown at a line, never inserted —
                            a playground's results, a verdict, a type hint — as one owner-keyed
                            buffer annotation the margin, the ghost text and the echo row read
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
src/comint.blsp             the INPUT REGION of a line-oriented program's buffer (Emacs's comint):
                            `:input-start`, the process mark, the boundary guard, the ↑/↓/C-r
                            history over a buffer's submitted lines, and M-x send-invisible, which
                            asks the mode (`:send-invisible`). A shell and a line-mode terminal
                            both stand on it, neither knowing the other
src/bshell.blsp             per-project shell + Brood REPL buffer (C-x p e): a line
                            typed at bedit's own prompt runs as `sh -c` (pipes, its ANSI
                            colours as faces — ansicolor) or, starting with `(`, evaluates
                            as Brood in the worker; a running command's output lands at the
                            PROCESS MARK (`comint`), before input typed ahead, which the next
                            prompt then keeps. A running command whose output
                            ends at a password prompt (`passwd/password-prompt?`: `sudo -S`,
                            `Password:`) gets the answer read masked and written to its stdin,
                            never the buffer, the next command or the history file: one asked
                            while the shell was not shown waits for the first TYPED key there
                            (`passwd/secret-overlay`), and input typed after the prompt
                            appeared moves into the read without a trace
                            (`passwd/take-since-prompt`); type-ahead from before it stays
                            as the next input
src/terminal.blsp           a TERMINAL buffer (C-x p t, C-x p r, M-x claude, C-u M-x term):
                            a program under a pty, its screen emulated by std/vt
                            (brood ADR-384) in the buffer's worker and painted into the
                            buffer's tail. CHAR mode (a full-screen program: claude,
                            htop, vim): every key goes to it (`term-overlay`); C-x
                            stays the editor's, C-y pastes, C-x c is the C-c map, C-x C-x /
                            C-x C-y send the literal. LINE mode (the project REPL: iex -S
                            mix, nest repl): the input after the program's prompt is
                            bedit's, with comint's history and boundary keys, RET sends
                            it — C-c C-j / C-c C-k switch. A PASSWORD the program asks for
                            (the worker asks the pty on each render — echo off in line
                            mode, `os/pty-password?`, brood ADR-570 — else the prompt's
                            text) is read masked and sent, never inserted or remembered;
                            M-x send-invisible reads one by hand. A prompt that arrived while
                            the terminal was not shown waits for the first TYPED key there,
                            which opens the read as its first character (input's
                            `passwd/secret-overlay`), never reaching the buffer or a macro; text
                            typed after the prompt appeared moves into the read, leaving no
                            undo step (`passwd/take-since-prompt`; a redraw puts the marker
                            back), while type-ahead from before it stays. An answered prompt redrawn is not
                            asked again; one re-asked is, told apart by the rows scrolled off
                            (`:term-scrolled`) and the pty's echo coming back on. The mouse reaches a program
                            that asked for it; one that did not gets a middle click as
                            PRIMARY pasted in (Emacs's term-mouse-paste); the program's
                            cursor shape and visibility
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
                            commands in the order they ran, exit code, duration, output
                            (its last 500 lines), credentials redacted, `\r` progress applied — `vcs-launch` (OFF the loop,
                            for the network), the working-tree QUEUE (`vcs-run-queued`, and
                            `vcs-gather` for a read a key waits on: refs, is anything staged —
                            in a task, in order, C-g cancels a read), `vcs-report-cmd`,
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
                            half-done in .git (the SEQUENCER) — the root, the git dir and the
                            sequencer read from the DISK, no process. One logged seam: `git-run` /
                            `git-run-then`, `git-do` to refresh after, `git-gather` for what a key
                            must ask git first (all queued off the loop), `git-launch-op` for
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
                            recent commits — collected in a task. RET goes to the line a diff
                            line became
src/gitstage.blsp           s/u/k in *git-status*, on what is at point: a REGION of a hunk's lines
                            (std/diff `hunk-select`), a hunk, a file, several files, a whole
                            list, a stash; k on a conflict offers ours/theirs, e opens it at
                            its first marker (smerge). Below the status, which it refreshes
                            by name
src/gitfetch.blsp           the background fetch that says when the upstream moved
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
                            guest's session runs an allowlist (`guest/ed-guest-allows?`). A
                            private session whose window drops PARKS for a day (brood ADR-519),
                            its sidecars written at once; attaching again under the same name
                            takes it back as it was. A session starts as the window does
                            (src/startup.blsp) and its kills and yanks go to the CLIENT's
                            clipboard over the link (`:client-clipboard`, brood ADR-539) — never
                            the daemon's; a C-y ASKS (`clipboard/ed-clipboard-ask`) and lands at the
                            spot it marked when the answer comes, the loop never waiting. Its
                            PRIMARY is the client's the same way (brood ADR-562): a drag sets it,
                            a middle click asks for it (`clipboard/ed-primary-ask`). A guest
                            keeps the host's config and loses recentf and save-place; a `--listen`
                            daemon keeps savehist off. A private session's buffers are hosted
                            as the window's are, in a registry the SESSION owns (`ed-served-host`,
                            brood ADR-593 — no runtime-wide name, gone with the session), and
                            std's `serve` supervises its loop: one that dies has its unsaved
                            files' sidecars written from the buffer processes
                            (`lifeline/emergency-save!`) and restarts over the same registry for
                            the same client (`ed-served-restart`, a guest still a guest), within
                            3 a minute, the keys typed through it replayed by std; the shown
                            buffer and every point come back too (a post-step hands the session
                            a snapshot, `ed-served-retain-step`). A shared session saves from its
                            collab registry and restarts with every document it had open linked
                            again (`ed-collab-reopen`)
src/collab.blsp             shared-buffer collaboration: presence carets, delta merges, follow/mirror
src/collabview.blsp         collab presence as the panes paint it: other participants' selections
                            (a highlight source) and carets with their name tags (a `:with-text`
                            pane layer)
tests/*_test.blsp           pure model/view tests, one suite per area (no window needed)
tests/window_paint_test     what the window PAINTS, read from pixels: the real view for a model
                            painted by brood's window painter into memory (`gui/render-frame`,
                            brood ADR-609) at a real size with bedit's font, inset and background —
                            the header line from y = 0, its text centred, the inset a margin
tests/guards_test         what a move must not lose: every keymap and mode symbol still bound, and a
                            guest's session running exactly tests/guest_allowed.txt, by M-x name and
                            by key (a line added there is a security decision)
tests/strict_ratchet_test   the `nest check --strict` ceiling: the count may only shrink —
                            a new function that adds a finding declares its contract instead
tools/drive-*.blsp          live drivers: run the real editor over a pty (std/vt reads what it
                            paints) or its own ui-run loop, and assert — the wiring the model
                            tests can't see (`make drive`, tools/README.md); `term-main.blsp` runs
                            the REAL `main` with $BEDIT_DRIVE_ARGS, which `drive-nw` drives in -nw
tools/screenshot.blsp       a PNG of what the REAL editor paints, no display: `main` in a child
                            runtime with a throwaway home, its window painted offscreen
                            (`BROOD_GUI_HEADLESS=paint`, brood ADR-609) and captured once it
                            settles (`gui/capture`) — so an agent can look at a layout change
tools/ci/platform-smoke.sh  CI's macOS / Windows run (`platform-smoke` in ci.yml): nest check, the
                            boot check and the test files where the OS shows through — what each
                            OS proves is docs/platforms.md
tools/ci/real-window.sh     CI's REAL-window check (macOS, Windows, Linux under Xvfb and a headless
                            Weston): `main` on a file in a window on a real display (no
                            BROOD_GUI_HEADLESS), typed into — through the loop, and the OS's own
                            input (xdotool / SendKeys / System Events) — saved with C-x C-s, the
                            file read back, the window captured and checked not blank; the PNGs
                            are a workflow artifact. The driver is `real-window.blsp`
tools/ci/lsp-rust.sh        CI's REAL language server check (`lsp-rust-analyzer` in ci.yml): the LSP
                            client against rust-analyzer on tools/ci/fixtures/lens-fixture, through
                            the editor's own loop headless (`lsp-rust.blsp`) — inlay hints at their
                            positions, semantic token faces on their ranges and a delta after an
                            edit, lenses above their lines (resolved, moved with the text), the
                            refresh requests heard, and a lens CLICK running `cargo run` and
                            jumping to an impl
tools/ci/ssh-real.sh        CI's REAL-sshd check (`ssh-real` in ci.yml): OpenSSH's server on
                            localhost (a throwaway host key and config, root through sudo so it can
                            check a password, a throwaway password user allowed sudo with its
                            password, a root-only file), host aliases for a key login, a
                            jump-host-only target and an unknown host key; the driver
                            (`ssh-real.blsp`) runs `/ssh:` open / save / revert / hex / large /
                            prompt listing / dired ops (replacing asked) / copies to and from this
                            machine and to another host / a 64 MB copy streamed past a 1 MB carried limit / `~user` / multi-hop / password / a jump
                            host's password / `|sudo:` with and without sudo's password / `|su:`
                            (root given a password for the run) / `|doas:` (a doas.conf of the
                            run's) / a dropped connection through the real ssh; then the root hops
                            again with sudo-rs as the host's sudo (`BEDIT_SSH_SUDO`, installed as
                            /usr/local/bin/sudo for the run; `BEDIT_SSH_ONLY=root`) — Ubuntu's
                            0.2.2 and the latest. `local` mode runs sshd as you (no
                            sudo, no password check) for a quick look on a desktop
tools/ci/drive-all.sh       CI's weekly LIVE DRIVERS run (.github/workflows/drive.yml, cron +
                            workflow_dispatch): every tools/drive-*.blsp, each on its own with a
                            timeout so one red driver hides none of the rest, the built nest (and
                            brood-lsp) first on PATH, a scratch XDG home, Elixir installed for
                            drive-elixir; a log per driver and summary.txt, uploaded on failure
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
