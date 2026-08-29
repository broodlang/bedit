#!/usr/bin/env python3
"""The Brood playground, end to end — and how LONG each step takes.

The model tests open the playground in a millisecond and evaluate in-image, so nothing there
can see the two things a user actually waits for: the buffer appearing after `M-x`, and the
first result coming back from a real sandbox child. This driver times both.

It exists because the playground was reported as taking "VERY long, probably like 20
seconds" to load, while every headless measurement said 1ms — the command, the module load
and the sandbox boot were each timed in isolation and each was fast. A wall-clock number
from the real editor is the only thing that settles where the wait actually is.
"""
import time

from drive import Report, Session

r = Report()
ed = Session("term-plain.blsp", rows=40, cols=140).start()


def timed(label, needle, timeout):
    """Wait for `needle`, reporting how long it took."""
    t0 = time.time()
    ok = ed.wait_for(needle, timeout)
    dt = time.time() - t0
    print(f"    {label}: {dt:.1f}s")
    r.check(ok, f"{label} (in {dt:.1f}s)")
    return dt


ed.mark()
ed.send("\x1bx", pause=0.4)  # M-x
ed.send("brood-playground", pause=0.4)
t0 = time.time()
ed.send("\r", pause=0.2)

# 1. the buffer itself — everything up to here is pure model work
open_s = timed("buffer opened", "type Brood; it runs as you stop typing", 60)

# 2. the pane beside it, which the command opens with `force`
pane_s = timed("spy pane painted", "What ran", 30)

# 3. the first RESULT — the debounce, then a round trip to the sandbox child. `=> 3` is the
#    welcome buffer's own `(+ 1 2)`, and nothing but a real reply can paint it.
first_s = timed("first result", "=> 3", 60)

total = time.time() - t0
print(f"    TOTAL M-x -> first result: {total:.1f}s")

# The numbers that matter. A playground you wait seconds for is not a scratch surface.
r.check(open_s < 3.0, f"the buffer opens promptly ({open_s:.1f}s < 3s)")
r.check(total < 10.0, f"a result is back within 10s ({total:.1f}s)")

ed.quit()
raise SystemExit(r.done("playground checks"))
