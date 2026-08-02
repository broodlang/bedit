#!/usr/bin/env python3
"""The lesson that teaches proper tail calls must not be broken by being watched.

Its first box is a MILLION-deep tail loop, and the tutorial boundary-traces every box so
the *Workings* pane can follow the cursor into it. A trace wrapper emits its `:return`
AFTER the call, so a traced self-call is no longer a tail call: this box used to cost a VM
frame per level, run 11× slower, and die at ~1 048 576 frames with `recursion too deep` —
the page teaching "constant stack, forever if it likes" was the page that overflowed.

Brood's fix is the bounded-sink contract: at its budget the sink answers `:spy-stop`,
`debug/trace-fn` puts the original back, and the rest of the loop is a real tail loop
(`std/tool/debug.blsp`, `std/tool/eval-server.blsp`). Only a live run proves the whole
chain — derived trace names → a real sandbox child → the reply → the note on the box.

No model test can see this: the headless evaluator installs no traces at all (that is
deliberate — see `src/tutor.blsp`), which is precisely the instrumentation that broke it.
"""
from drive import Report, Session

r = Report()
ed = Session("term-tutor.blsp", rows=48, cols=170,
             env={"BEDIT_DRIVE_LESSON": "Recursion is the loop"}).start()

r.check(ed.wait_for("Recursion is the loop", 40), "opened at the recursion lesson")

# the verdict note is the whole point: a value, not an error and not a timeout
r.check(ed.wait_for("=> :liftoff", 60), "a million TRACED tail calls answered => :liftoff")
r.check(not ed.wait_for("recursion too deep", 1), "…without exhausting the frame limit")
r.check(not ed.wait_for("timed out", 1), "…and inside the box's 2s budget")

# the pane says what it actually has: the first N calls, not "every call"
r.check(ed.wait_for("the first 200 traced calls", 20), "*Workings* header states the trace budget")
r.check(ed.wait_for("countdown 1000000", 20), "…and shows the traced call it started from")

# the exercise below it still behaves: it ships unsolved, and says so against its expectation
r.check(ed.wait_for("expected 120, got 5", 30), "the factorial exercise still ships unsolved")

ed.quit()
raise SystemExit(r.done("tail-call lesson checks"))
