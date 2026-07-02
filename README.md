# myedit

An Emacs clone, written in [Brood](../brood). Brood is a small, immutable Lisp
built to be the language a modern, self-editing, remotely-hostable editor is
written in — and this repo is that editor.

myedit is **pure Brood glue over the editor toolkit that ships in Brood's
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

myedit consumes the **installed** `nest` (`~/.local/bin/nest`), which must be
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

## What works today

Emacs-style movement and editing, a kill ring, multiple buffers and a
`*Messages*` echo area, a real minibuffer, completion-at-point, tiled window
splits with mouse support, incremental search and query-replace, `M-x`,
project-aware find-file, and `C-x C-e` eval-in-buffer (run off the loop so a
looping form can't freeze the editor). brood-mode adds live syntax highlighting,
bracket matching, eldoc, sexp-aware indentation and structural navigation, and
advisory type-check diagnostics. See [`ROADMAP.md`](ROADMAP.md) for the full
status and what's next.

## Layout

```
src/main.blsp               entry point — opens the window, runs the ui-run loop
src/model.blsp              the ui-run model: buffer pool, kill ring, minibuffer, *Messages*, scrolling
src/panes.blsp              pane-layout geometry + mouse-event folding (model -> model)
src/view.blsp               pure view: model -> render frame (editor/display ops)
src/input.blsp              dispatch: fold a key/mouse/tick event into the next model
src/commands.blsp           the editing commands, each a (model key) -> model
src/interactive.blsp        the `defcommand` macro + the M-x command registry
src/modes.blsp              modes as layers: the keymaps (data) + brood-mode services
src/complete.blsp           completion-at-point (the in-buffer Tab popup)
src/mincomplete.blsp        minibuffer prompt completion (path / name)
src/completion.blsp         shared fuzzy ranking + vertical-menu renderer (complete + minibuffer)
src/isearch.blsp            incremental search + query-replace (C-s/C-r/M-%) modal mini-loops
src/eval-command.blsp       eval Brood source from a buffer (the C-x C-e core)
src/projects.blsp           project root + file walk (find-file-in-project)
src/web.blsp                live HTTP mirror of the selected buffer (C-x w)
tests/main_test.blsp        pure update/view tests (no window needed)
tests/eval_command_test.blsp  tests for the eval-command module
project.blsp                the nest manifest (:name "myedit")
```

## Contributing

The prime directive: when the editor needs a core abstraction Brood doesn't yet
have, **add it to the Brood language** (in `../brood`) and build the feature on
that clean primitive — don't hack the missing capability into myedit as a
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
