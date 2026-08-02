#!/usr/bin/env python3
"""The tutorial's *Workings* pane, end to end: a real sandbox child, replies arriving as
records, the pane rendered by the actual view.

The model tests drive the pane from synthetic replies on purpose (the headless evaluator
instruments nothing — see `src/tutor.blsp`), so this is the only place the whole chain runs:
box source → derived trace names → sandbox → spy entries → cache → pane.

`term-tutor.blsp` opens straight at the lesson that teaches the pane; walking the contents
page by keystroke is not what this checks.

**Assert on what only a real reply can paint.** This driver used to search for
"sum-doubles" and "*Workings*" — both of which are on the page anyway, as box source and as
the lesson's own prose. It therefore passed green for as long as the harness forgot to start
the sandbox at all (`sandbox-eval` is a documented no-op with no worker), reporting a chain
that never ran. The checks below are the pane's own vocabulary: a `= <value>` return line and
the verdict note on the box, neither of which exists without a reply.
"""
from drive import Report, Session

r = Report()
ed = Session("term-tutor.blsp", rows=44, cols=150).start()

r.check(ed.wait_for("Watching it run", 40), "opened at the lesson that teaches the pane")
r.check(ed.wait_for("=> 12", 60), "the box evaluated in the sandbox (the verdict note)")
r.check(ed.wait_for("The workings — every traced call", 40), "the pane opened on its own")
r.check(ed.wait_for("sum-doubles [1 2 3]", 20), "…showing the traced call with its args")
r.check(ed.wait_for("double- 1", 20), "…including the inner call, nested under it")
r.check(ed.wait_for("= 12", 20), "…and its RETURN — a line only a real cascade produces")

# it FOLLOWS the cursor: M-n to the exercise box, which traces its own `twice-it`
ed.mark()
ed.send("\x1bn", pause=1.5)
r.check(ed.wait_for("twice-it 20", 25), "moving box re-rendered the pane for the box at point")

# closing it is respected; C-c C-w brings it back
ed.mark()
ed.send("\x18o", pause=0.5)                 # C-x o → into the *Workings* pane
ed.send("\x180", pause=0.8)                 # C-x 0 → close it
r.check(ed.wait_for("Watching it run", 15), "the pane closed; the tutorial has the frame")
ed.mark()
ed.send("\x03\x17", pause=1.5)              # C-c C-w
r.check(ed.wait_for("The workings", 20), "C-c C-w restored the pane")

# killing the TUTORIAL takes the pane with it (layers' close-request seam, ADR-202)
ed.send("\x18k", pause=1.5)                 # C-x k
r.check(ed.wait_for("killed *Tutorial*", 10), "the tutorial was killed")
after = ed.repaint()                        # a fresh full paint: what is on screen NOW
r.check(b"The workings" not in after, "*Workings* is gone from the screen")
r.check(b"Brood Tutorial" not in after, "*Tutorial* is gone from the screen")

ed.quit()
raise SystemExit(r.done("workings-pane checks"))
