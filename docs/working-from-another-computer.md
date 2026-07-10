# Working from another computer

A runbook for picking up myedit on a second machine, and for the serve/attach
(daemon/emacsclient) modes. myedit lives in **two** repos and the editor depends on
the language's `std/`, so you set up both.

| Repo | Remote | What it is |
|---|---|---|
| `brood` | `git@github.com:broodlang/brood.git` | the Brood language + `std/` (buffer, serve, ui, …) and the `nest`/`bedit` build |
| `brood-edit` | `git@github.com:broodlang/brood-edit.git` | the editor itself (pure Brood over `std/`) |

Both are pushed to `main`. `brood-edit` builds against the **installed** `nest`, whose
`std/` is baked in at build time — so after pulling `brood` you must reinstall `nest`
for the editor to see std changes (markers, buffer subscribe/push, `attach-display-local`).

## First-time setup on a fresh machine

```bash
# 1. clone both, side by side (brood-edit expects ../brood)
git clone git@github.com:broodlang/brood.git
git clone git@github.com:broodlang/brood-edit.git

# 2. build + install a GUI-enabled nest (heavy deps, one-time)
cd brood
./configure --with-gui && make install      # installs nest / brood / brood-lsp to ~/.local/bin

# 3. build + install the standalone editor binary
cd ../brood-edit
make install                                  # `nest release` → ~/.local/bin/bedit
```

Make sure `~/.local/bin` is on your `PATH`.

## Picking up after work was pushed (already set up)

```bash
cd brood       && git pull && ./configure --with-gui && make install   # if std changed
cd ../brood-edit && git pull && make install                            # rebuild bedit
```

If only `brood-edit` changed (no std change), you can skip the `brood` reinstall.

## Running the editor

```bash
nest run                      # a *scratch* buffer (uses local source + installed std)
nest run -- notes.txt         # open notes.txt (C-x C-s saves / creates it)
bedit notes.txt               # the standalone binary — same thing, no repo needed
nest test                     # the test suite   ·   nest check   # advisory type/lint
```

## Serve / attach — one editor, many windows (same machine today)

The Emacs `--daemon` / `emacsclient` model. The **daemon** runs the editor; **clients**
paint its frames and ship back keys. As of the latest push, `--serve` *also opens the
host's own window* by default, so serving isn't blind.

```bash
# host: serve AND open your own window (others can attach)
bedit --name ed --serve notes.txt

# host: SHARED — every client edits ONE model, sees each other live (one shared cursor)
bedit --name ed --serve --shared notes.txt

# host: headless — no local window, a pure background daemon (displayless server, or a
#       daemon that should outlive your window). Ctrl-C to stop.
bedit --name ed --serve --headless notes.txt

# another terminal on the SAME machine: open a window attached to the daemon
bedit --attach ed
```

- `--serve` alone → each client gets its **own** buffer (independent sessions).
- `--serve --shared` → clients share **one** model and **one** cursor.
- Close the host window to stop serving (use `--headless` for a daemon that persists).

## Over the network (not wired yet — the honest status)

The architecture is fully network-capable: every attach is a Brood **node link**, and
node links run over TCP (`connect "name@host:port"` dials TCP — "the network is just a
longer copy"). **But** the daemon today calls `node-start` with no address, so it binds
only a per-user **Unix-domain socket** → *same machine only*. `bedit --attach ed` works
locally; nothing crosses machines yet.

To reach a daemon from another machine we need **dual-listen** (`node-also-listen`: keep
the local Unix socket *and* add a TCP listener), a chosen port, and a matching node
cookie (`~/.config/brood/cookie`) on both ends. That's a small, planned addition
(`--listen [--host H] [--port N]`, then `bedit --attach ed@host:port`) — deferred until
it can be verified against a real second machine, because "works over the network"
should be a tested claim. See `docs/remote-multiplayer-plan.md`.

**So: to work from another computer today**, pull + build there and run your own editor
(and, on one machine, serve locally to extra terminals). True cross-machine collaboration
is the next serve slice.

## Collaboration status (what's built vs runnable)

| Capability | State |
|---|---|
| Remote attach, host window, shared-cursor `--serve --shared` | ✅ runnable (same machine) |
| Shared edits with **independent** cursors (`src/collab.blsp`) | ✅ built + unit-tested; ⬜ not yet a live serve mode |
| Cross-machine (TCP dual-listen) | ⬜ planned (`--listen`) |

The independent-cursor collab layer (buffers-as-processes: a shared buffer process,
positional-splice edits, per-pane cursors) is complete and headless-tested in
`src/collab.blsp` / `tests/collab_test.blsp`; wiring it into a live `--serve --collab`
mode is the remaining step (see `docs/remote-multiplayer-plan.md`).

## Verify a setup is good

```bash
cd brood       && cargo run -q -p nest -- test tests/buffer_test.blsp   # markers + subscribe/push
cd ../brood-edit && nest test                                            # whole editor (~771 tests)
```

All green ⇒ the language foundation and the editor are in sync on this machine.
