# bedit

An Emacs clone, written in [Brood](../brood). Brood is a small, immutable Lisp
built to be the language a modern, self-editing, remotely-hostable editor is
written in — and this repo is that editor.

bedit is **pure Brood glue over the editor toolkit that ships in Brood's
`std/`** — nothing custom in any kernel. Every layer is a `std/` module:

| Layer | Toolkit module   | Role |
|-------|------------------|------|
| model | `editor/buffer`  | immutable, rope-backed buffer — pure point/movement/editing ops |
| view  | `editor/display` | `clear` / `text` / `cursor` / `frame` render ops (plain data) |
| input | `editor/keymap`  | rebindable `key → command-symbol` dispatch (late-bound, hot-swappable) |
| modes | `editor/layers`  | per-buffer mode stacks: keymaps + language services as data |
| loop  | `editor/ui` `ui-run` | TEA-style render→poll→update loop over `(gui-display)`, a native window |

The editor itself is *policy* — commands, modes, keymaps — folded over that
framework as a single `ui-run` loop. Commands are `(model key) -> model`; keys
dispatch through a keymap to command *symbols* resolved at dispatch time, so a
command redefined live (via `C-x C-e`) hot-swaps on the next keystroke.

## Running it

bedit consumes the **installed** `nest` (`~/.local/bin/nest`), which must be
built with the GUI backend. Building that lives in the Brood repo:

```bash
# in ../brood — install a GUI-enabled nest (heavy deps, one-time):
./configure --with-gui && make install

# here:
nest run                 # open the editor on a scratch buffer (native window)
nest run -- notes.txt    # open (Ctrl-S saves) that file
nest test                # run the test suite
nest check               # advisory type/lint check
```

> A plain `cargo run -p nest -- test` rebuilds `target/debug/nest` *without* the
> GUI feature and clobbers the installed binary — verify the GUI only via the
> installed `nest` (or `cargo build --features brood/gui` in `../brood`).

To install it as a desktop app — a standalone `bedit` binary plus the desktop
entry and icon, so it launches from the GNOME dash with its own name and icon
rather than as an unidentified window:

```bash
make install          # -> ~/.local/bin/bedit + the .desktop entry + the icon
```

See [`assets/README.md`](assets/README.md) for how the three names (the window's
app id, the entry, the icon) hook up.

## What works today

Emacs-style movement and editing, a kill ring, multiple buffers and a
`*Messages*` echo area, a real minibuffer with Vertico-style completion,
completion-at-point, tiled window splits with mouse support, incremental search
and query-replace, `M-x`, registers, bookmarks, keyboard macros, occur, dired,
project-aware find-file, a per-project shell, `M-x compile` with next-error,
and `C-x C-e` eval-in-buffer (run off the loop so a looping form can't freeze
the editor). brood-mode adds live syntax highlighting, bracket matching, eldoc,
sexp-aware indentation, paredit-style structural editing, and advisory
type-check diagnostics; ruby- and elixir-mode get fontification and structural
motion via tree-sitter. An LSP client wires completion, goto-definition,
references, hover, rename, and format into any server-backed buffer. Git is
integrated as a diff-hl change gutter plus a Magit-style status / diff / log /
commit porcelain (`C-x g`).

The editor is also remotely hostable: `--serve` / `--attach` give the Emacs
daemon/emacsclient model, and `--serve --shared` turns it into real multiplayer
editing — one document, everyone their own caret, live named presence,
follow/mirror — over a Unix socket or authenticated TCP (`--listen`). See
[`docs/working-from-another-computer.md`](docs/working-from-another-computer.md)
for the runbook, and [`ROADMAP.md`](ROADMAP.md) for the full status and what's
next.

## Layout

```
src/main.blsp               entry point — window / daemon startup (--serve/--attach), runs the ui-run loop
src/model.blsp              the ui-run model: buffer pool, kill ring, minibuffer, *Messages*, scrolling
src/config.blsp             ~/.config/bedit/init.blsp — the declarative user config (data, not eval'd)
src/theme.blsp              every colour the editor paints (Catppuccin Mocha), referenced by role
src/panes.blsp              pane-layout geometry + mouse-event folding (model -> model)
src/view.blsp               pure view: model -> render frame (editor/display ops)
src/statusbar.blsp          the mode line as extensible segments (render ops + click/hover zones)
src/input.blsp              dispatch: fold a key/mouse/tick event into the next model
src/commands.blsp           the editing commands, each a (model key) -> model
src/keymaps.blsp            keybinding profiles (emacs / modal vim) as model-scope layers
src/interactive.blsp        the `defcommand` macro + the M-x command registry
src/modes.blsp              modes as layers: the keymaps (data) + brood-mode services
src/complete.blsp           completion-at-point (the in-buffer Tab popup)
src/lsp.blsp                LSP client — completion, goto-def/references, hover, rename, format, imenu
src/mincomplete.blsp        minibuffer prompt completion (path / name)
src/completion.blsp         shared fuzzy ranking + vertical-menu renderer (complete + minibuffer)
src/plume.blsp              the minibuffer completion UI — list + marginalia (our Vertico/Marginalia)
src/isearch.blsp            incremental search + query-replace (C-s/C-r/M-%) modal mini-loops
src/eval-command.blsp       eval Brood source from a buffer (the C-x C-e core)
src/compile.blsp            M-x compile: run a build in the project root, C-x ` next-error
src/projects.blsp           project root + file walk (find-file-in-project)
src/bshell.blsp             per-project shell + Brood REPL buffer (C-x p e)
src/git.blsp                git porcelain: C-x g status buffer, diff/log/commit, C-x v = vc-diff
src/gitdiff.blsp            diff-hl change gutter: per-line added/modified/deleted vs HEAD
src/web.blsp                live HTTP mirror of the selected buffer (C-x w)
src/remote.blsp             --serve / --attach / --listen: the daemon/emacsclient model
src/collab.blsp             shared-buffer collaboration: presence carets, delta merges, follow/mirror
tests/*_test.blsp           pure model/view tests, one suite per area (no window needed)
project.blsp                the nest manifest (:name "bedit")
```

## Contributing

The prime directive: when the editor needs a core abstraction Brood doesn't yet
have, **add it to the Brood language** (in `../brood`) and build the feature on
that clean primitive — don't hack the missing capability into bedit as a
one-off. A self-editing Emacs clone is only possible if its abstractions live in
a language expressive enough to host them. See [`CLAUDE.md`](CLAUDE.md) for the
full working guide (conventions, how to write a plan, the prime directive in
detail). Design notes for where the editor is headed live in [`docs/`](docs/):
[`configurability.md`](docs/configurability.md) (a settings registry + the
customization surface), [`packages.md`](docs/packages.md) (an extension ecosystem
— packages as Brood nests), and
[`actor-architecture.md`](docs/actor-architecture.md) (buffers as processes).

## License

Licensed under the GNU Affero General Public License v3.0 (`AGPL-3.0-only`); see
[`LICENSE`](LICENSE). Copyright © 2026 Wilhelm Kirschbaum.
