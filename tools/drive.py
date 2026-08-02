#!/usr/bin/env python3
"""Drive the real editor over a pty, and assert on what it paints.

The point of these drivers is the gap the model tests structurally cannot cover: that a
KEY reaches the command it is bound to, that an async sandbox reply lands, that a buffer is
actually gone from the screen. Two bugs found this way were invisible to 1200 passing model
tests — a keybinding added to the tutorial's help vocabulary but never `keymap-bind`-ed (so
it rendered as a blank hole and could not be typed), and the window's Wayland `app_id`.

Why Python: driving a terminal needs a pty (openpty + TIOCSWINSZ + a controlling tty for
raw mode), and Brood has `proc-spawn` (piped stdio) but no pty primitive — recorded in
`../brood/docs/deferred.md`. When Brood grows one, these belong in Brood.

Usage — see `tools/README.md`; each `drive_*.py` is a script over this harness:

    from drive import Session, Report
    r = Report()
    ed = Session("term-plain.blsp")           # the editor, over *term-display*
    ed.start()
    r.check(ed.wait_for("Type to edit", 20), "editor is up")
    ed.send("\\x1bx"); ed.send("tutorial"); ed.send("\\r")
    ...
    raise SystemExit(r.done())
"""
import errno
import fcntl
import os
import pty
import re
import signal
import struct
import subprocess
import sys
import termios
import time

TOOLS = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(TOOLS)

# A face change splits any phrase mid-word ("Brood\x1b[38;5;…mTutorial"), so every search
# runs against the escape-stripped stream. Searching raw bytes silently reports "never
# appeared" for text that is plainly on screen.
ANSI = re.compile(rb"\x1b\[[0-9;?]*[a-zA-Z]|\x1b[()][A-B0-9]|\x1b[=>]")


class Report:
    """Collects check results; `done()` prints nothing extra and returns an exit code."""

    def __init__(self):
        self.failures = 0

    def check(self, ok, label):
        print(("ok: " if ok else "FAIL: ") + label, file=sys.stdout if ok else sys.stderr)
        if not ok:
            self.failures += 1
        return ok

    def done(self, what="checks"):
        print(f"\n{'FAILURES: ' + str(self.failures) if self.failures else 'all live ' + what + ' passed'}")
        return 1 if self.failures else 0


class Session:
    """One editor process on a pty, with its output accumulated for searching."""

    def __init__(self, script, rows=40, cols=140, env=None, cwd=PROJECT, prog="nest"):
        self.script = script if os.path.isabs(script) else os.path.join(TOOLS, script)
        # `prog` is absolute when a driver is testing a stripped environment: launching the
        # editor by path is what a .desktop `Exec=` line does, and it lets the CHILD's PATH
        # be empty while the harness can still start.
        self.prog = prog
        self.rows, self.cols = rows, cols
        self.env = env or {}
        self.cwd = cwd
        self.stream = bytearray()
        self.proc = None

    def start(self, settle=2.5):
        self.master, slave = pty.openpty()
        self._winsize(slave, self.rows, self.cols)
        self.proc = subprocess.Popen(
            [self.prog, "run", self.script],
            stdin=slave, stdout=slave, stderr=subprocess.DEVNULL, cwd=self.cwd,
            env={**os.environ, "TERM": "xterm-256color", **self.env},
            # the child needs the pty as its CONTROLLING terminal, or raw mode fails
            preexec_fn=lambda: (os.setsid(), fcntl.ioctl(0, termios.TIOCSCTTY, 0)))
        os.close(slave)
        self.pump(settle)
        return self

    @staticmethod
    def _winsize(fd, rows, cols):
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    def pump(self, seconds):
        """Read for `seconds`, accumulating output. False if the child closed the pty."""
        end = time.time() + seconds
        while time.time() < end:
            try:
                chunk = os.read(self.master, 65536)
            except OSError as e:
                if e.errno == errno.EIO:      # child exited
                    return False
                raise
            if not chunk:
                return False
            self.stream.extend(chunk)
        return True

    def screen(self):
        """Everything painted since the last `mark()`, escapes stripped."""
        return ANSI.sub(b"", self.stream)

    def mark(self):
        """Cut the stream. A later `wait_for` then cannot be satisfied by an earlier paint —
        which is the single easiest way to write a driver that lies to you."""
        self.stream.clear()

    def repaint(self, settle=2.0):
        """Force a full redraw and return it. A terminal stream is incremental, so "what is
        on screen NOW" is not readable from history: resizing makes the loop re-render
        everything, which is how you assert that something is GONE."""
        self.mark()
        self.rows = self.rows + (1 if self.rows % 2 == 0 else -1)   # nudge, alternating
        self._winsize(self.master, self.rows, self.cols)
        os.kill(self.proc.pid, signal.SIGWINCH)
        self.pump(settle)
        return self.screen()

    def wait_for(self, needle, timeout, poll=0.25):
        deadline = time.time() + timeout
        n = needle.encode() if isinstance(needle, str) else needle
        while time.time() < deadline:
            if n in self.screen():
                return True
            if not self.pump(poll):
                break
        return False

    def send(self, keys, pause=0.25):
        os.write(self.master, keys.encode() if isinstance(keys, str) else keys)
        self.pump(pause)

    def quit(self, pause=0.8):
        self.send("\x18\x03", pause=pause)     # C-x C-c
        self.pump(0.5)
        if self.proc:
            self.proc.terminate()
