# bedit

An Emacs clone, written in [Brood](../brood). Brood is a small, immutable Lisp
built to be the language a modern, self-editing, remotely-hostable editor is
written in — and this repo is that editor.

## Install

One file with its own Brood runtime inside: you do not need Brood. Linux (x86_64 and arm64)
and macOS (Apple Silicon):

```sh
curl -fsSL https://raw.githubusercontent.com/broodlang/bedit/main/scripts/install.sh | sh
```

That puts `bedit` in `~/.local/bin` (and, on Linux, adds it to the app menu). Then:

```sh
bedit              # a scratch buffer
bedit notes.txt    # that file (C-x C-s saves)
```

Run the same line again to update. `BEDIT_VERSION=v0.11.0` before `sh` installs a given
release, and `BEDIT_INSTALL_DIR` puts it elsewhere. Or download the archive for your
machine from the [latest release](https://github.com/broodlang/bedit/releases/latest),
unpack it and put the one file on your `PATH` as `bedit`; on macOS, a browser download
needs `xattr -d com.apple.quarantine bedit` before it opens. There is no Windows or Intel
Mac build yet.

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

## Running it from source

bedit consumes the **installed** `nest` (`~/.local/bin/nest`), which must be
built with the GUI backend. Building that lives in the Brood repo:

```bash
# in ../brood — install a GUI-enabled nest (heavy deps, one-time):
./configure --with-gui && make install

# here:
nest run                 # open the editor on a scratch buffer (native window)
nest run -- notes.txt    # open that file (C-x C-s saves it)
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
and query-replace, `M-x`, registers, bookmarks, keyboard macros, occur (`e`
edits the matches in place), dired (`C-x C-q` is wdired: the file names edited
as text, `C-c C-c` renames — swaps, moves into directories, an erased name
flagged for deletion, a symlink re-pointed by editing its target, the permissions
when `:wdired-allow-to-change-permissions` says so),
project-aware find-file, a per-project shell, `M-x compile` with next-error,
and `C-x C-e` eval-in-buffer (run off the loop so a looping form can't freeze
the editor). brood-mode adds live syntax highlighting, bracket matching, eldoc,
sexp-aware indentation, paredit-style structural editing, and advisory
type-check diagnostics. Some 45 other kinds of file have a mode of their own:
29 tree-sitter grammars (Rust, Go, Python, TypeScript, C and C++, Java, Ruby,
Elixir, …) give fontification, indentation, folds and structural motion, and
line lexers cover the other Lisps and the config formats (Makefile, INI,
.gitignore, .env, …). An LSP client wires completion, goto-definition,
references, hover, rename, and format into any server-backed buffer, colours
names by the server's semantic tokens over the mode's own highlighting, and
shows code lenses (opt-in, `:lsp-code-lens`) as a row above their line. Git is
integrated as a diff-hl change gutter plus a Magit-style status / diff / log /
commit porcelain (`C-x g`).

It runs in a terminal too: `bedit -nw` (or `--no-window`), and by itself when
there is no display to open a window on — over ssh, on a console — with the
mouse, bracketed paste, and kills reaching your clipboard through the terminal
(OSC 52). A root-owned file opens as root with `C-x C-f /sudo::/etc/hosts` or
`M-x sudo-edit`; the password is asked for, masked, and never kept. A file on a
machine that has no bedit opens with `C-x C-f /ssh:host:/etc/nginx.conf` (TRAMP's
syntax, `/ssh:user@host#port:path`) and saves back over ssh — see
[`docs/working-from-another-computer.md`](docs/working-from-another-computer.md#editing-a-file-on-a-machine-that-has-no-bedit-ssh).
`bedit -Q` starts clean, as Emacs's: no init file and no installed packages (`-q`
skips only the init file, `--no-packages` only the packages) — how a bug is told
from a setting or a package. `M-x report-bug` lists the packages that were loaded.

The editor is also remotely hostable: `--serve` / `--attach` give the Emacs
daemon/emacsclient model, and `--serve --shared` turns it into real multiplayer
editing — one document, everyone their own caret, live named presence,
follow/mirror — over a Unix socket or authenticated TCP (`--listen`). See
[`docs/working-from-another-computer.md`](docs/working-from-another-computer.md)
for the runbook, and [`ROADMAP.md`](ROADMAP.md) for the full status and what's
next.

## Configuring

`~/.config/bedit/init.blsp` is one `(config …)` form, written with every key documented
(and commented out) on first launch. It is **data**, read and never evaluated — so it holds
settings and key bindings, not code; `M-x reload-config` applies an edit without a restart:

```text
(config
  :font "JetBrains Mono"                       ; one not installed is said, not silently replaced
  :keys {"C-c f" project-find-file "C-z" nil}  ; global-set-key: a key, an M-x name (nil unbinds)
  :mode-keys {markdown {"C-c C-c" markdown-preview}})  ; define-key in one mode's map
```

A command of your own lives in a package under `~/.config/bedit/packages` (see
[`packages.md`](docs/packages.md)); [`configurability.md`](docs/configurability.md) has what
the init file can and cannot say.

### Trusting a project

Some language servers run the project's own code as they start (rust-analyzer runs
`build.rs` and proc macros, R runs `.Rprofile`, Gradle `build.gradle`), and so does
`mix format`. So bedit asks before running a project's code by itself, as VS Code's workspace
trust does. The first time a file of an untrusted project would start one, and once you have
paused, the echo area asks:

```text
Trust ~/src/foo? Its language server (rust-analyzer) can run the project's code.  y yes · n no · ! always
```

`y` trusts it for the session, `!` for good (kept in `~/.config/bedit/state/trusted-projects.blsp`),
and `n` (or C-g) leaves it untrusted for the session without asking again. Until you answer, nothing
of it runs: no server autostart, no format on save, no Brood checker loading its modules, no background
`git fetch` (which would run the repo's `core.sshCommand` or `credential.helper`). The git summary on
the mode line still works, read with the repo's own `core.fsmonitor`, external diff and textconv
programs switched off, since an unpacked archive can ship a `.git/config` naming them. Any other
key is not taken as an answer: the question steps aside and the key works as usual. Starting a
server yourself (`M-x lsp-connect`, or a lookup such as `M-.`) asks at once. A project is its
repository's top (else its project root), so trusting a repository covers the projects inside it.
`M-x project-trust`, `M-x project-untrust` and `M-x list-trusted-projects` manage the list.
`:project-trust :always` in init.blsp turns the questions off (the old behaviour), and `:never`
runs only projects you trusted with `M-x project-trust`. A project's `.bedit-locals.blsp` cannot
change this setting. Commands you run yourself (`M-x compile`, the test runner, `M-x format-buffer`)
are never asked about.

## Contributing

The prime directive: when the editor needs a core abstraction Brood doesn't yet
have, **add it to the Brood language** (in `../brood`) and build the feature on
that clean primitive — don't hack the missing capability into bedit as a
one-off. A self-editing Emacs clone is only possible if its abstractions live in
a language expressive enough to host them. See [`CLAUDE.md`](CLAUDE.md) for the
full working guide (conventions, how to write a plan, the prime directive in
detail), and [`docs/layout.md`](docs/layout.md) for a map of every module. Design notes
for where the editor is headed live in [`docs/`](docs/):
[`configurability.md`](docs/configurability.md) (a settings registry + the
customization surface), [`packages.md`](docs/packages.md) (an extension ecosystem
— packages as Brood nests), and
[`actor-architecture.md`](docs/actor-architecture.md) (buffers as processes).

## License

Licensed under the GNU Affero General Public License v3.0 (`AGPL-3.0-only`); see
[`LICENSE`](LICENSE). Copyright © 2026 Wilhelm Kirschbaum.
