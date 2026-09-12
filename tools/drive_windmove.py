#!/usr/bin/env python3
"""A modified arrow reaches the window commands bound to it — in a real terminal.

`C-S-<right>` moves the window and `M-<right>` selects the one beside it. Driven because
the key's NAME is the whole point (ADR-328): the terminal frontend has to turn the xterm
sequence `ESC [ 1 ; 6 C` into `:ctrl-shift-right` and `ESC [ 1 ; 3 C` into `:alt-right`,
and only a frontend proves it. On a lone pane each command answers with its edge
message, which names the direction — a needle the input cannot produce.
"""
from drive import Report, Session

r = Report()
ed = Session("term-plain.blsp", rows=30, cols=110).start()
r.check(ed.wait_for("*scratch*", 20), "editor is up")

ed.mark()
ed.send("\x1b[1;6C", pause=0.6)                     # Ctrl+Shift+Right
r.check(ed.wait_for("no window right to swap with", 10), "C-S-<right> reached swap-pane-right")

ed.mark()
ed.send("\x1b[1;3D", pause=0.6)                     # Alt+Left
r.check(ed.wait_for("no window left", 10), "M-<left> reached windmove-left")

# and with a split, the swap really moves: C-x 3, type a marker in the (left, selected)
# pane, C-S-<right> — the marker's pane is now on the right, and selection went with it
ed.send("\x18" + "3", pause=0.5)                    # C-x 3
ed.send("LEFTMARK", pause=0.5)
ed.mark()
ed.send("\x1b[1;6C", pause=0.8)
screen = ed.repaint()
r.check(b"LEFTMARK" in screen, "the marked buffer is still on screen after the swap")
# the swap followed the buffer: another C-S-<right> is now at the right edge
ed.mark()
ed.send("\x1b[1;6C", pause=0.8)
r.check(ed.wait_for("no window right to swap with", 10), "selection followed the buffer to the right pane")

ed.quit()
raise SystemExit(r.done("windmove checks"))
