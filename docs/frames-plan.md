# Frames — a second window on the same buffers

**Status:** plan (2026-09-13), implemented in the same session; see the devlog.

In Emacs a *frame* is a separate OS window over the same buffers: `C-x 5 2` opens one,
`C-x 5 o` switches, `C-x 5 0` closes it. Two monitors, `*Tests*` on one screen and the
code on the other. bedit is one window per process; the runtime mandates it (a window
delivers its input to the process that opened it, and the messages carry no window id —
ADR-058/059).

## The decision: a frame is a process that attaches to the buffer processes

Not a second window driven by the editor's process (which would need a window id on
every input message and a per-window mailbox to be sound — a tag alone is not: the
loop's poll must keep a catch-all arm for async replies, and that arm would swallow the
other window's tagged keys). Instead the on-thesis shape: **a frame is another `ui-run`
process with its own window, whose pool slots are linked to the same buffer processes**
— the hosted-buffer flip (`src/hosted.blsp`, "every pool buffer is backed by its own
process") already makes a buffer a subscribable actor, and `src/collab.blsp` already
proves two sessions editing one buffer through it. A frame is a collab session with no
network and every buffer shared, not just files. A remote `--attach` window and a local
frame become the same thing at different distances.

## Part 1 — what we do in Brood

**The gap: a named directory of buffer processes.** `collab.blsp` keeps one (`{path →
proc}`, share-on-first-ask, respawn on death) as a private loop keyed by file path. Any
editor with more than one frontend on one buffer set needs the same thing keyed by
buffer *name* (Emacs buffers are global by name: `*scratch*`, `*Messages*`, a dired
listing), with the two things collab's lacks: **enumeration** (a joining frame asks
"what buffers exist?") and **membership notifications** (a buffer created or killed in
one frame appears or vanishes in the others).

`std/editor/buffer-registry.blsp`:

- `(registry-start)` → pid. One per runtime (or per node — it is just a process).
- `(registry-share reg name text meta)` → the ONE buffer process for `name`: spawned
  from `text`/`meta` (`{:file :type :dir}`) on the first ask, the existing pid after.
  Serialised inside the registry, so two frames asking at once cannot both spawn.
- `(registry-entries reg)` → `[{:name :proc :meta} …]`.
- `(registry-remove reg name)` → stops the process (a kill-buffer is global).
- `(registry-watch reg pid)` / `(registry-unwatch reg pid)`: a watcher is sent
  `[:registry-added name proc meta]` and `[:registry-removed name reason]` (`:killed`,
  or `:died` when the process crashed — the registry drops the entry; a holder that
  rehosts from its cache re-shares, and everyone else relinks on the `:added`).
- `(registry-stop reg)`: end every process and the loop.

Tests in `tests/buffer_registry_test.blsp`: share-once, enumeration, watch
notifications, a crashed process's `:removed :died` then a re-share, remove.

**Not done, and why:** the window id on input. With one process per window the runtime
already routes input correctly; the sound version of "two windows, one process" is a
per-window mailbox, a different design. Recorded as the remaining half of ADR-059.

**Follow-up (separate):** `collab.blsp`'s registry becomes a client of this one (keyed by
path, plus its text mirror) — not in this change, so collab's respawn semantics and tests
stay untouched.

## Part 2 — what we do in bedit

`src/frames.blsp`, on `hosted.blsp` + the registry:

1. **The registry rides the live model** as `:buffer-reg`, started in `main` beside the
   hosted flip. `hosted-reconcile` hosts a new slot *through* the registry
   (`registry-share` with the slot's text + `{:file :type :dir}`), so every live buffer
   is registered the moment it exists, in the single-frame case too. `hosted-drop-slot`
   (kill-buffer) removes it from the registry. `hosted-rehost` re-shares after a crash.
2. **Two registry events** in `input/ed-event-handlers`: `:registry-added` → a frame
   without that buffer adds a pool slot (`make-buffer "" name file`, typed from `meta`,
   dir set) and links it to the process — the seed push fills the text; a frame that has
   it but whose link is dead (the crash case) relinks. `:registry-removed` → the slot is
   dropped (`hosted-drop-slot`'s pane re-pointing, without a second registry remove).
3. **`C-x 5 2` make-frame**: `frame-spawn` — a new process that opens its own
   `gui-display` (the process that opens the window polls it, ADR-058), builds a model
   from the registry's entries (every buffer a linked slot, the current buffer shown,
   `:frame? true`, the same `:buffer-reg`, `:host-buffers? true`), watches the registry,
   and runs `ui-run` with `ed-view`/`ed-update` unchanged. Frames are tracked in the
   primary's model as `:frames` (`{pid window}`) via a monitor.
4. **`C-x 5 0` delete-frame** (and the frame's ✕): a secondary frame just quits its loop
   — its slots' links are unsubscribed, the buffer processes live on; `cmd-quit` in a
   frame is delete-frame (Emacs asks nothing when other frames remain). The **primary's**
   quit keeps `save-buffers-kill-terminal`, then kills the frame processes (their
   windows close with them).
5. **`C-x 5 o` other-frame**: raise the next frame's window (`gui/focus`) — the primary
   keeps the frame list, so a secondary frame asks the primary (`:editor`) to do it.
6. Per frame: layout, minibuffer, undo of a slot's cache, kill ring (the OS clipboard makes
   yank cross frames anyway), mode line. Shared: the buffers, their text and markers, the
   registry. The logger, LSP, sandbox and the async services stay the primary's (`:editor`);
   `*Messages*` is a buffer, so a frame sees it through its process.

Tests: `tests/frames_test.blsp` — two models, one registry, no window: a buffer opened
in A appears in B as a linked slot; an edit in A lands in B (through the buffer process,
`ht-settle`-style barriers, no sleeps); kill in A removes from B; A's crash-rehost
relinks B; a frame model's quit is a frame quit. The live wiring (`C-x 5 2` opening a
real second window) is a `tools/drive_frames.py`-shaped check only if the pty harness can
observe it — it cannot see a second GUI window, so the live proof is a `BROOD_GUI_DUMP`
run of two windows, done by hand once.
