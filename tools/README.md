# tools — driving the real editor

`nest test` covers the model: pure `(model key) -> model` folds and `model -> frame` views,
~1200 of them, no window. What it cannot see is the wiring *around* the model — that a key
reaches the command it is bound to, that an async sandbox reply arrives, that a buffer is
really gone from the screen.

These drivers run the actual editor on a pty and assert on what it paints.

```bash
make drive                 # all of them
python3 tools/drive_mspc.py # or one at a time (from anywhere)
```

| Driver | What only a live run can show |
|---|---|
| `drive_mspc.py` | `M-SPC` cycles one space → none → what was there. The keymap binds the key *name* `(keyword "alt- ")`; only a frontend proves ESC+SPC arrives as that. |
| `drive_workings.py` | The whole tutorial chain: box source → derived trace names → a real sandbox child → spy entries → cache → the *Workings* pane, following the cursor. Plus that killing the tutorial takes the pane with it. |
| `drive_progress.py` | Progress survives a session — two editor processes, one throwaway `XDG_CONFIG_HOME`, a solve in the first and the count still there in the second. |
| `drive_tailcalls.py` | A million TRACED tail calls answer `=> :liftoff`. The lesson teaching O(1) stack is boundary-traced, and a trace wrapper used to cost a frame per level (Brood ADR-207). Model tests can't see it: the headless evaluator instruments nothing, which is exactly the instrumentation that broke. |

**Three bugs these caught that 1200 model tests could not.** A new tutorial key was added to the
help-text vocabulary but never `keymap-bind`-ed, so it rendered as a blank hole in the prose
*and* could not be typed — the vocabulary and the keymap are two different tables, and only
pressing the key crosses them. The window's Wayland `app_id`, which lives in a protocol
message the model never touches. And a traced million-deep tail loop exhausting the VM's frame
limit — visible only with real instrumentation, which only the live sandbox installs.

**Assert on what only the feature can paint.** `drive_workings.py` spent a while green over a
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
a new `drive_*.py`, not a second copy of the harness.

## Writing another one

`drive.py` is the harness: a `Session` (pty + child + accumulated output) and a `Report`
(check/tally/exit code).

```python
from drive import Report, Session
r = Report()
ed = Session("term-plain.blsp").start()
r.check(ed.wait_for("Type to edit", 20), "editor is up")
ed.mark()                       # cut the stream before the action you are about to assert on
ed.send("\x1bx")                # keys are raw bytes: \x1b = ESC/Meta, \x03 = C-c
r.check(ed.wait_for("M-x", 5), "M-x prompt")
raise SystemExit(r.done())
```

Three things that make a driver lie to you, all handled here but easy to reintroduce:

1. **Face escapes split phrases.** `"Brood Tutorial"` arrives as `Brood\x1b[38;5;…mTutorial`,
   so a raw-byte search reports "never appeared" for text plainly on screen. `screen()`
   strips escapes first; always search through it.
2. **The stream is history, not the screen.** `wait_for` can be satisfied by a paint from
   thirty seconds ago. `mark()` before the step you are asserting on, and use `repaint()`
   (a resize forces a full redraw) when you need to assert something is *gone*.
3. **First paint is slow.** Module load plus a sandbox child is seconds, not milliseconds;
   the timeouts here are generous on purpose.

## Why Python

Driving a terminal needs a pty — `openpty`, `TIOCSWINSZ`, and the pty as the child's
controlling terminal so raw mode works. Brood has `proc-spawn` (piped stdio) but no pty
primitive, so this cannot be written in Brood today; the gap is recorded in
`../brood/docs/deferred.md`. When Brood grows one, these belong in Brood like everything
else here.
