"""A command's declared contract, shown beside it in M-x — the marginalia only a live run paints.

`M-x` lists each command with its `model -> model` contract in the right margin (with the
key bound to it and its docstring). The model tests build the annotation string; only a
frontend proves it reaches the Plume list the reader sees. The C-x C-e verdict on a
redefined defcommand (`✓ … honours (model any -> model)`) is covered by the model suite
(tests/eval_command_test.blsp) — the term harness forwards only record events, so a
task-reply eval cannot complete here.
"""
from drive import Report, Session

r = Report()
ed = Session("term-plain.blsp", rows=34, cols=140).start()
r.check(ed.wait_for("*scratch*", 20), "editor is up")

ed.mark()
ed.send("\x1bx", pause=0.4)                          # M-x
r.check(ed.wait_for("M-x", 5), "M-x prompt")
ed.send("forward-char", pause=0.6)
r.check(ed.wait_for("model any", 8), "the command's declared contract shows in the marginalia")
# the key it is bound to rides the same annotation
r.check(ed.wait_for("C-f", 8), "…alongside the key it is bound to")

ed.quit()
raise SystemExit(r.done("command-contract marginalia checks"))
