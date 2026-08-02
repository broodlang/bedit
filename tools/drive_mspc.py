#!/usr/bin/env python3
"""M-SPC is `cycle-spacing` (Emacs 29 took the key from `just-one-space`).

Driven rather than unit-tested because the keymap binds the key NAME `(keyword "alt- ")`,
and only a real frontend proves that ESC+SPC arrives as that.
"""
from drive import Report, Session

r = Report()
ed = Session("term-plain.blsp", rows=30, cols=110).start()

# a wide gap with a sentinel either side, so no assertion can match the editor's own chrome
ed.send("xx(   )yy", pause=0.4)
r.check(ed.wait_for("xx(   )yy", 15), "editor is up and typed the gap")

ed.send("\x02\x02\x02\x02", pause=0.3)      # C-b x4 → point inside the gap

for keys, want, label in (
        ("\x1b ", "xx( )yy", "M-SPC reached cycle-spacing: one space"),
        ("\x1b ", "xx()yy", "second press: gap deleted"),
        ("\x1b ", "xx(   )yy", "third press: the original run restored"),
        ("\x1b ", "xx( )yy", "fourth press: the cycle starts over")):
    ed.mark()
    ed.send(keys, pause=0.6)
    r.check(ed.wait_for(want, 10), label)

# an intervening command must break the cycle: C-f then M-SPC is a FIRST press again
ed.mark()
ed.send("\x06", pause=0.3)                  # C-f
ed.send("\x1b ", pause=0.6)
r.check(ed.wait_for("xx( )yy", 10), "after another command it collapses, never restores")

ed.quit()
raise SystemExit(r.done("M-SPC checks"))
