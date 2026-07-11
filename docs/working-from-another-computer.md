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

# host: SHARED — everyone edits the SAME document, each with their OWN cursor
bedit --name ed --serve --shared --as wilhelm notes.txt

# host: headless — no local window, a pure background daemon (displayless server, or a
#       daemon that should outlive your window). Ctrl-C to stop.
bedit --name ed --serve --headless notes.txt

# another terminal on the SAME machine: open a window attached to the daemon
bedit --attach ed --as alice
```

- `--serve` alone → each client gets its **own** buffer (independent sessions).
- `--serve --shared` (alias `--collab`) → THE collaborative mode: shared *content* (one
  buffer process serializes all edits) while each client keeps its own cursor, panes, and
  minibuffer. A late joiner syncs to the live document, not the file on disk. **Presence**:
  everyone else's caret renders live as a coloured bar with a name tag; joins/leaves are
  echoed; a detached/crashed participant's caret is cleaned up, never a ghost. Fast typing
  never flickers under its own round-trip (origin-tagged echo suppression).
- **Every file is shared.** Any file buffer any participant visits is auto-backed by one
  shared process (the daemon's file registry) — so you can roam a whole project together,
  not just the launch file.
- **`share-follow` (`C-x f`)** — ride a participant's caret: your point AND buffer track
  theirs (switching files with them). With one other person it follows immediately; with
  more it prompts by name. Any move of your own takes the wheel back; `C-x f` again stops.
- **`share-mirror` (`C-x F`)** — like share-follow, but your window also reproduces their
  viewport (scroll), so you see exactly what they see — the classic one-view pairing.
- **`M-x share-session` / `M-x share-session-stop`** — start/stop hosting from a NORMAL
  running editor (no --serve needed): it becomes the daemon `bedit --attach myedit` reaches.
- **Names**: `--as NAME` → `:share-name "you"` in `~/.config/brood-edit/init.blsp` → your
  OS username; `share-session` prompts if none is set. Name tags show quietly — only for a
  few seconds after that caret moves; the coloured bar stays.
- `M-x collab-status` echoes who's here and what you're following.
- Close the host window to stop serving (use `--headless` for a daemon that persists).

## Over the network — `--listen`

Every attach is a Brood **node link**, and node links run over TCP. `--listen
[HOST:]PORT` makes the daemon bind TCP instead of the per-user Unix socket:

```bash
# host machine (copy ~/.config/brood/cookie to the other machine first — it authenticates)
bedit --name ed --serve --shared --listen 7457 --as wilhelm notes.txt

# any machine that can reach it:
bedit --attach ed@HOST:7457 --as alice
```

- A bare port binds `0.0.0.0` (every interface); give `HOST:PORT` to bind one.
- The **cookie** (`~/.config/brood/cookie`) must match on both ends — that's the auth.
- Dual-listen: the per-user Unix socket stays bound alongside TCP, so local attaches
  keep the bare-NAME form while remote machines use `@HOST:PORT`.
- Verified over a real TCP link (loopback: two runtimes, full presence + edit fan-out);
  cross-machine is the same code path — try it from the second machine.

## Collaboration status (what's built vs runnable)

| Capability | State |
|---|---|
| Remote attach + host window (`--serve`, private session per client) | ✅ |
| Shared editing, own cursor each (`--serve --shared`, alias `--collab`) | ✅ |
| Presence: named, coloured remote carets + join/leave echoes (`--as`) | ✅ |
| `follow` (C-x f): ride a participant's caret — the pairing view | ✅ |
| Echo suppression (own round-trip never flickers fast typing) | ✅ |
| Cross-machine over TCP (`--listen`, cookie-authenticated) | ✅ (loopback-verified; try your second machine) |
| Delta pushes (splices/marker moves on the wire — the document never ships) | ✅ |
| Concurrent typing merges exactly (OT for disjoint edits; same-span resyncs) | ✅ |
| Shared selections (everyone's region, tinted in their colour) | ✅ |
| Modeline presence chip (`shared: alice, bob → alice`) | ✅ |
| Kernel dual-listen (Unix socket *and* TCP at once) | ✅ |
| `share-session-stop` fully tears down (sessions, registry, buffer procs) | ✅ |

The independent-cursor collab layer (a shared buffer process, positional-splice edits,
per-pane cursors — `src/collab.blsp`) is live as `--serve --collab`: each attaching client
gets its own session whose buffer is backed by the daemon's one buffer process, so edits
serialize with no CRDT while every cursor stays independent (see
`docs/remote-multiplayer-plan.md` for the architecture).

## Verify a setup is good

```bash
cd brood       && cargo run -q -p nest -- test tests/buffer_test.blsp   # markers + subscribe/push
cd ../brood-edit && nest test                                            # whole editor (~771 tests)
```

All green ⇒ the language foundation and the editor are in sync on this machine.
