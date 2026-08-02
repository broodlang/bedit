#!/usr/bin/env python3
"""Tutorial progress survives a session — two real editor runs against a throwaway
XDG_CONFIG_HOME:

  session 1 — open the tutorial, solve the first exercise, watch it count, quit
  session 2 — open it again; the contents page still shows that solve

Only a second process can check this: the save happens on the way out, the load on the way
in, and both are gated on the live editor's model flag (`:recent-files`, the same gate
recentf and bookmarks use — NOT a registered `:editor` process, which a test run also has).
"""
import os
import re
import shutil

from drive import PROJECT, Report, Session, TOOLS

HOME = os.path.join(PROJECT, "target", "drive-progress-home")   # gitignored build dir
PROGRESS = os.path.join(HOME, "brood-edit", "tutor-progress.blsp")

r = Report()
shutil.rmtree(HOME, ignore_errors=True)
os.makedirs(os.path.join(HOME, "brood-edit"), exist_ok=True)
env = {"XDG_CONFIG_HOME": HOME}

# ---- session 1: solve the first exercise -------------------------------------------
s1 = Session("term-plain.blsp", rows=40, cols=130, env=env).start()
s1.send("\x1bx"); s1.send("tutorial"); s1.send("\r", pause=0.8)
r.check(s1.wait_for("Brood Tutorial", 40), "session 1: tutorial opened")
r.check(s1.wait_for("Navigation 1/", 20), "session 1: first lesson, nothing solved yet")
r.check(s1.wait_for("⋯", 40) or s1.wait_for("✗", 40), "session 1: the sandbox is answering")

s1.send("\x1bn", pause=0.4)          # M-n → the exercise box
s1.send("\x0b", pause=0.3)           # C-k → clear the template
s1.send("my keys are emacs", pause=0.8)
r.check(s1.wait_for("✓ 1/1", 25), "session 1: the exercise counts as passed (modeline ✓ 1/1)")
s1.pump(1.5)                          # let the save land
s1.quit()

on_disk = os.path.exists(PROGRESS)
r.check(on_disk, "the pass was written to tutor-progress.blsp")
if on_disk:
    body = open(PROGRESS).read()
    print("   file:", body.strip().splitlines()[-1])
    r.check(":passed" in body, "…and it holds a :passed set")
    r.check(body.lstrip().startswith(";;"), "…with the header a person can read")

# ---- session 2: a FRESH editor must remember it ------------------------------------
s2 = Session("term-plain.blsp", rows=40, cols=130, env=env).start()
s2.send("\x1bx"); s2.send("tutorial"); s2.send("\r", pause=0.8)
r.check(s2.wait_for("Brood Tutorial", 40), "session 2: tutorial opened")
s2.send("\x03\x14", pause=1.0)        # C-c C-t → the contents page
r.check(s2.wait_for("contents", 15), "session 2: contents page")
s2.pump(1.0)
row = re.search(rb"Navigation.{0,40}?lessons\)\s*(\S+)", s2.screen(), re.S)
print("   contents row tick:", row.group(1) if row else b"(row not found)")
r.check(bool(row and (b"/" in row.group(1) or "✓".encode() in row.group(1))),
        "session 2: the Navigation row carries last session's solved count")
s2.quit()

raise SystemExit(r.done("progress checks"))
