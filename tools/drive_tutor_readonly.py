#!/usr/bin/env python3
"""The tutorial's prose and box borders are READ-ONLY at the edit primitive (ADR-219):
every render stamps the box regions' complement as the buffer's `:read-only-spans`, so
`insert`/`delete` themselves refuse a keystroke that would damage the generated text — on
every path, not a `:post-key` comparison a dispatch path can bypass (which is how a HELD
backspace once ate the box border and the prose).

A pty can't drive the GUI's held-key repeat timer (our repeat is GUI-gated; the model test
fires `[:timer :key-repeat]` for that path). What only a live run shows is that the REAL
editor — real keymap, real dispatch, real `ed-edit` — refuses the deletion at the box edge
and SAYS so, and that the box itself stays writable. The echo-area hint is the reliable
signal: it repaints on the keystroke that was refused, so there is no terminal-diff
guessing about what is still on screen.
"""
from drive import Report, Session

r = Report()
ed = Session("term-tutor.blsp", rows=40, cols=90,
             env={"BEDIT_DRIVE_LESSON": "Watching it run"}).start()

r.check(ed.wait_for("Brood Tutorial", 15), "the tutorial is up (heading painted)")
r.check(ed.wait_for("watch one function call another", 10), "box 1's border/title is painted")
r.check(ed.wait_for("look inside instead of guessing", 10), "the prose above box 1 is painted")

# point parks in box 1 past its margin; C-a lands on the box's first char — the char BEFORE
# it is the ╭ border line's newline, generated text. A backspace there must be refused.
ed.send("\x01", pause=0.3)          # C-a — beginning of the box's first line = box start
ed.mark()
ed.send("\x7f", pause=0.5)          # one backspace, straight at the top border
r.check(ed.wait_for("read-only", 8), "backspace at the box edge is refused, with a hint")

# hold it down: many more backspaces, all at the same edge — still refused, never eats in.
# (Every one is refused at the mutator, so the border/prose never change — which is also why
#  we don't wait_for them after a mark: unchanged text isn't repainted. The refusal IS the
#  proof nothing was eaten; the model tests assert the text byte-for-byte.)
ed.mark()
ed.send("\x7f" * 30, pause=1.0)
r.check(ed.wait_for("read-only", 8), "a storm of backspaces at the edge stays refused")

# protection is PARTIAL: inside the box still edits. Move off the edge and type a sentinel.
ed.send("\x05", pause=0.3)          # C-e — end of the box's first line (inside the box)
ed.mark()
ed.send("ZQX", pause=0.6)
r.check(ed.wait_for("ZQX", 8), "the box itself still accepts an edit (partial, not total)")

ed.quit()
raise SystemExit(r.done("tutorial read-only prose checks"))
