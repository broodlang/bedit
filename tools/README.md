# tools — driving the real editor

`nest test` covers the model: pure `(model key) -> model` folds and `model -> frame` views,
~1200 of them, no window. What it cannot see is the wiring *around* the model — that a key
reaches the command it is bound to, that an async sandbox reply arrives, that a buffer is
really gone from the screen.

These drivers run the actual editor and assert on what it paints.

```bash
make drive                        # all of them
nest run tools/drive-mspc.blsp    # or one at a time (from anywhere)
```

All of them are Brood. Two shapes, and the difference is where the editor runs:

- **On a pty** (`drive.blsp` is their harness). The editor is a real child process with a
  real terminal, and the driver reads what it paints through `std/vt` — the terminal
  emulator from bedit's own terminal buffer (brood ADR-384). This is the only way to prove
  a *key* reaches its command: the bytes go in the front, the screen comes out the back,
  and the frontend is in the middle where it belongs.
- **In-process** (`drive-async`, `drive-elixir`, `drive-term`). These run the editor's own
  `ui-run` loop over a scripted frontend — the real command, the real timers, the real
  async events, the real `ed-view` — and assert on the frame. They cannot see the frontend,
  but they can drive a child process and wait on its replies without a terminal in the way,
  and a model is readable directly rather than through a screen.

| Driver | What only a live run can show |
|---|---|
| `drive-mspc` | `M-SPC` cycles one space → none → what was there. The keymap binds the key *name* `(keyword "alt- ")`; only a frontend proves ESC+SPC arrives as that. |
| `drive-workings` | The whole tutorial chain: box source → derived trace names → a real sandbox child → spy entries → cache → the *Workings* pane, following the cursor. Plus that killing the tutorial takes the pane with it. |
| `drive-progress` | Progress survives a session — two editor processes, one throwaway `XDG_CONFIG_HOME`, a solve in the first and the count still there in the second. |
| `drive-tailcalls` | A million TRACED tail calls answer `=> :liftoff`. The lesson teaching O(1) stack is boundary-traced, and a trace wrapper used to cost a frame per level (brood ADR-207). Model tests can't see it: the headless evaluator instruments nothing, which is exactly the instrumentation that broke. |
| `drive-mdpreview` | `C-c C-p` in a `.md` buffer paints the rendered document beside it — the mode keymap's chord reaching a command whose module was not loaded, the split, and the view painting a buffer's faces from `:face-spans` data rather than a lexer. The needles (`━`, `•`) are what only the render produces. |
| `drive-windmove` | `C-S-<right>` moves the window and `M-<left>` selects the one beside it — from a real terminal, where the frontend has to turn `ESC [ 1 ; 6 C` into `:ctrl-shift-right` (ADR-328). Each command's edge message names the direction, a needle the input cannot produce. |
| `drive-contract` | `M-x` shows each command's declared `model -> model` contract in the margin (with its key and doc) — the marginalia the model tests build but cannot paint. |
| `drive-narrow` | `C-x n n` paints ONLY the focused region and the mode line shows `⊸ Narrowed`; `C-x n w` brings the rest back. The model tests confine point; only a frame shows the render slice + indicator. |
| `drive-tutor-readonly` | The REAL editor refuses a backspace at a box's edge and says so, while the box stays writable — the tutorial's prose/borders are read-only at the edit primitive (`:read-only-spans`, ADR-219), not a `:post-key` guard a held key could outrun. |
| `drive-playground` | `M-x brood-playground` end to end, TIMED: how long until the buffer is on screen, and how long until a real sandbox child answers the first form. It exists because the playground was reported as taking "VERY long, probably like 20 seconds" while every headless measurement said 1 ms — a wall-clock number from the real editor is the only thing that settles where a wait actually is. |
| `drive-nopath` | The desktop-launch condition: the editor started by ABSOLUTE PATH with no `PATH` at all, as a GNOME launch does. Its sandbox then has to find a Brood runtime beside its own executable; without that fallback a dash-launched editor silently loses eval-on-type, with nothing on screen to say why. |
| `drive-async` | The four things moved off the loop process (candidate ranking, the project file walk, the status-bar git summary, the diff-hl gutter) really come back and get folded in. Headless is exactly the branch where each falls back to running synchronously, so `nest test` runs the code this is about and never the code that ships. |
| `drive-elixir` | The Elixir playground against a **real BEAM node**: `M-x` opens the buffer and its pane, the welcome expression comes back `=> 2 : Integer`, a `defmodule` typed into the buffer is callable by the form below it, that call's traced cascade reaches the pane, and a half-typed `defmodule` reads as pending rather than as an error. Every one of those crosses a process boundary, and the model tests use synthetic replies — they can prove what a reply BECOMES, never that one arrives. It earned its keep on the first run: the buffer opened, the pane painted, and nothing ever evaluated, because the launch is on an idle timer and the driver was waiting instead of firing one. |
| `drive-term` | A terminal buffer end to end: `M-x term` opens a buffer sized to the pane, a typed line reaches the program through the overlay (echoed by the pty, never inserted), its answer comes back as a SCREEN the frame paints with point on the program's cursor, and `C-x k` takes the worker and the program down. The model tests fold synthetic screens; only a real `sh` under a real pty shows the chain — and it found the pty master leaking into every child (brood `fix(pty)`). |
| `check-modes.sh` | The RELEASED binary, opened from `$HOME` on one file per lexical mode, prints no view error. A mode names its services by symbol, resolved at render time; the model tests load every module, so only the installed editor with no project around it can show a service whose module nothing loads (`editor/lexer/line-restart`, 2026-09-15). `make check-modes`. |

**Three bugs these caught that 1200 model tests could not.** A new tutorial key was added to the
help-text vocabulary but never `keymap-bind`-ed, so it rendered as a blank hole in the prose
*and* could not be typed — the vocabulary and the keymap are two different tables, and only
pressing the key crosses them. The window's Wayland `app_id`, which lives in a protocol
message the model never touches. And a traced million-deep tail loop exhausting the VM's frame
limit — visible only with real instrumentation, which only the live sandbox installs.

**Assert on what only the feature can paint.** `drive-workings` spent a while green over a
chain that never ran: it searched for "sum-doubles" and "*Workings*", both of which are on the
page anyway as box source and prose, while the harness had no `:sandbox` worker at all
(`sandbox-eval` is a no-op without one). A driver's needle must be something the *result*
produces and the *input* cannot — a `= 12` return line, a verdict note, a count.

## The entry points

`term-plain.blsp` and `term-tutor.blsp` are `main`'s wiring minus the GUI-only calls, over
`*term-display*`. They set the live-editor flags `main` sets (`:recent-files`,
`:os-clipboard`) — a harness without them is not the editor a reader runs, which is exactly
how the progress driver would have missed its own bug. They must also do what the *command*
does and the model does not: `term-tutor.blsp` calls `sandbox-start` (`cmd-tutorial`'s job) and
opens straight at one lesson, chosen by title via **`BEDIT_DRIVE_LESSON`** — so a new check is
a new `drive-*.blsp`, not a second copy of the harness.

## Writing another one

`drive.blsp` is the pty harness. A session is a PROCESS that owns the child and the vt, so a
driver reads like the script it is, with no state threaded through it:

```lisp
(reflect/add-load-path (path/join (file/cwd) "tools"))
(require-one 'drive)

(let (s (drive/start "term-plain.blsp"))
  (do
    (drive/check "editor is up" (drive/wait-for s "Type to edit" 20000))
    (drive/send-keys s "\x1bx")          ; raw bytes: \x1b = ESC/Meta, \x03 = C-c
    (drive/check "M-x prompt" (drive/wait-for s "M-x" 5000))
    (drive/quit s)
    (drive/done "M-x checks")))
```

`start` · `send-keys` · `screen` · `wait-for` · `wait-gone` · `gone?` · `resize` · `quit`,
and `check` / `done` tally the run (`done` raises when anything failed, so `nest run` exits
non-zero and `make drive` stops). Every call is a round trip, which is also the ordering
barrier: when `send-keys` returns, the editor has been given the keys and everything they
painted is already in the vt.

Three things that make a driver lie to you, all handled here but worth knowing:

1. **Face escapes split phrases.** `"Brood Tutorial"` arrives as `Brood\x1b[38;5;…mTutorial`.
   A raw-byte search reports "never appeared" for text plainly on screen — which is why the
   harness feeds an emulator rather than searching the stream.
2. **The editor echoes your keys until it takes over the terminal.** Before it switches to
   the alternate screen it is a COOKED terminal, and keys typed at it come back as literal
   `^B^[ ` text that lands on the screen and satisfies the driver's own assertions. `start`
   waits for `vt/mode :alt-screen` before it returns, so no driver can make that mistake.
3. **First paint is slow.** Module load plus a sandbox child is seconds, not milliseconds;
   the timeouts here are generous on purpose.

## These were Python until 2026-09-22

The pty drivers were Python, for the reason their own docstring gave: driving a terminal
needs `openpty`, `TIOCSWINSZ` and the pty as the child's controlling terminal, and Brood had
no pty primitive. Brood grew one (`os/spawn-pty`), and then grew the other half too —
`std/vt`, the emulator.

The emulator is what made the Brood version SHORTER than the Python, not merely a translation
of it. That harness accumulated every byte the editor ever wrote, stripped the escapes with a
regex and searched the lot, so "is X on screen NOW" was unanswerable — history is not the
screen — and two devices existed to work around it: `mark()`, to cut the stream so an old
paint could not satisfy a new assertion, and `repaint()`, which resized the terminal to
provoke a full redraw so that a thing's ABSENCE could be asserted. Feed the same bytes to a
vt and the screen simply IS the screen: `screen` is current, `gone?` is
`(not (includes? …))`, and both devices disappear.

It also fixed a whole class of green lies. Every check in the Python `drive_mspc` was passing
on the pty's own echo rather than on anything the editor painted, because nothing knew when
the editor had taken the terminal over. The emulator knows.
