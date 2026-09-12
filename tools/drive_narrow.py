"""Per-pane narrowing paints only the focused region, and says ⊸ Narrowed — a live check.

The model tests prove `:restrict` confines point; only a real frame shows that the pane
DRAWS just the slice and the mode line carries the indicator, and that widening brings the
rest back. A temp file of distinctly-named lines makes "gone" and "back" assertable.
"""
import os
import tempfile

from drive import Report, Session

r = Report()
ed = Session("term-plain.blsp", rows=24, cols=100).start()
r.check(ed.wait_for("*scratch*", 20), "editor is up")

with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, "lines.txt")
    with open(path, "w") as f:
        f.write("".join(f"ROW{i:02d}\n" for i in range(30)))

    ed.mark()
    ed.send("\x18\x06", pause=0.5)                        # C-x C-f
    r.check(ed.wait_for("Find file", 8), "find-file prompt")
    ed.send("\x01\x0b" + path + "\r", pause=1.0)          # C-a C-k, path, RET
    r.check(ed.wait_for("ROW05", 8), "the file is open, all rows visible")

    # point is at the top (ROW00). Set the mark, move down 4 lines → region ROW00..ROW04
    ed.send("\x00", pause=0.3)                            # C-SPC (set mark)
    ed.send("\x0e\x0e\x0e\x0e", pause=0.4)                # C-n x4
    ed.mark()
    ed.send("\x18nn", pause=0.8)                          # C-x n n (narrow to region)
    screen = ed.repaint()
    r.check(b"ROW00" in screen and b"ROW04" in screen, "the focused region is shown")
    r.check(b"ROW09" not in screen and b"ROW20" not in screen, "the rest of the file is not")
    r.check("⊸ Narrowed".encode() in screen, "the mode line says ⊸ Narrowed")

    ed.mark()
    ed.send("\x18nw", pause=0.8)                          # C-x n w (widen)
    screen = ed.repaint()
    r.check(b"ROW09" in screen, "widen brings the rest of the file back")
    r.check("⊸ Narrowed".encode() not in screen, "and the indicator is gone")

ed.quit()
raise SystemExit(r.done("narrowing checks"))
