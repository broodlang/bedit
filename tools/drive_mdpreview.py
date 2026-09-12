#!/usr/bin/env python3
"""C-c C-p in a .md buffer paints the RENDERED document beside it, and again takes it down.

Driven because the chain is wiring the model tests cannot see: the mode keymap's chord
reaching a command whose module is not loaded, the split, and the view painting a buffer's
faces from `:face-spans` DATA rather than a lexer. The needle is what only the render can
produce — the `━` underline and the `•` bullet, neither of which is in the source.
"""
import os
import tempfile

from drive import Report, Session

r = Report()
ed = Session("term-plain.blsp", rows=30, cols=120).start()
r.check(ed.wait_for("*scratch*", 20), "editor is up")

with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, "notes.md")
    with open(path, "w") as f:
        f.write("# Title\n\nSome **bold** words here.\n\n- one\n- two\n")

    ed.mark()
    ed.send("\x18\x06", pause=0.5)                      # C-x C-f
    r.check(ed.wait_for("Find file", 10), "find-file prompt")
    ed.send("\x01\x0b" + path + "\r", pause=1.0)                 # C-a C-k clears the prefilled dir
    r.check(ed.wait_for("**bold**", 10), "the markdown source is on screen")

    ed.mark()
    ed.send("\x03\x10", pause=1.5)                      # C-c C-p
    r.check(ed.wait_for("━━━━━", 10), "the heading is underlined in the preview")
    r.check(ed.wait_for("• one", 10), "the list is bulleted in the preview")
    r.check(ed.wait_for("markdown preview", 10), "the echo says what opened")

    ed.send("\x03\x10", pause=1.0)                      # C-c C-p again
    screen = ed.repaint()
    r.check(b"\xe2\x94\x81\xe2\x94\x81" not in screen, "the preview is gone from the screen")
    r.check(b"**bold**" in screen, "the source is still there")

ed.quit()
raise SystemExit(r.done("markdown preview checks"))
