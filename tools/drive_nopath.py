#!/usr/bin/env python3
"""The desktop-launch condition: NO PATH at all.

A GNOME launch does not inherit a login shell's environment, and a session's PATH routinely
lacks `~/.local/bin`. The editor is started by absolute path (what the `.desktop` `Exec=`
line does) — and its eval sandbox then has to find a Brood runtime with no PATH to search,
which it does by looking beside its own executable (`exe-path`).

Without that fallback a dash-launched editor silently loses eval-on-type: the tutorial's
playgrounds and `C-x C-e` stop answering, with nothing on screen to say why.
"""
import os
import shutil

from drive import Report, Session

r = Report()
nest = shutil.which("nest")
r.check(bool(nest), f"found nest to launch by absolute path ({nest})")

ed = Session("term-tutor.blsp", rows=40, cols=140, env={"PATH": ""}, prog=nest).start(settle=3.0)
r.check(ed.wait_for("Watching it run", 45), "the editor started with an EMPTY PATH")
# The sandbox child is the part that needs a runtime; its cascade only appears once the
# child has booted, evaluated the box and answered.
r.check(ed.wait_for("sum-doubles", 60), "the sandbox found a runtime beside the binary")

ed.quit()
raise SystemExit(r.done("no-PATH checks"))
