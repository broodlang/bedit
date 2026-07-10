# Track 1 — Remote & multiplayer editing (the two-part plan)

**Status:** plan. The flagship track from
[`competitive-tracks.md`](competitive-tracks.md): one editor core you attach to
from anywhere, and multiple people editing the same buffers with live presence.
This is the payoff of the decided-direction actor architecture
([`actor-architecture.md`](actor-architecture.md)) and the M4 daemon model
(`../brood/docs/node-connect.md`) — it names the destination directly: *"one core,
multiple attached frontends … the Emacs `--daemon` / `emacsclient` model."*

Per this repo's rule, the plan is two parts: **(1) what we do in Brood** to make
this expressible cleanly, then **(2) what we build in myedit** on top. Part 1 leads
because most of remote/multiplayer is a *language* capability, not editor glue.

---

## What already exists (don't rebuild)

The substrate is largely shipped — this track cashes in decisions already made:

- **Distribution (ADR-068, done).** `node-start`/`connect` **by name** over a
  per-user Unix socket (no port), remote pids that carry node identity,
  **location-transparent `send`** (a pid addresses a process whether local or
  across a link), `register` / `monitor-node` / `remote-spawn`, a shared cookie
  auto-resolved. `nest run --name foo app.blsp` brings a node up first — the
  `--daemon` model, at the runtime level, today.
- **The web mirror (`src/web.blsp`).** *Already a read-only multi-frontend
  broadcast.* Its publisher/fan-out hub (`web-pub-loop`) holds the latest snapshot
  and a set of subscribers; each edit/cursor move is pushed to every open client.
  It proves the two hard patterns: **a rope is process-local, so the truth crosses
  the boundary as a plain-data snapshot** (never the rope), and **one writer per
  socket, frames as messages**. Remote/multiplayer is this pattern made read-write
  and multi-participant.
- **The event bus (`src/input.blsp`).** The inbound seam already folds
  out-of-band messages into the model (e.g. `[:web-port n]`, `[:task-done …]`).
  Remote input arrives the same way.
- **The design-of-record (`actor-architecture.md`).** The staged
  buffers-as-processes path, with "a buffer on a second node → collaborative
  editing" as its final slice, and the prime-directive split already sketched
  (markers, versioned projections, supervised buffer-workers).

---

## Part 1 — What we do in Brood (the language gaps)

The prime directive: build the missing core abstractions *in Brood/`std`*, then
have the editor use them. Four gaps, roughly in dependency order.

### 1.1 A frontend/session protocol module — `std/editor/frontend`

Today the `ui-run` loop couples the model to the local `gui-display` window: it
polls that window for events and renders frames to it. To attach a *remote*
frontend, the render→transport→input path must become a **protocol over plain
data** that works over the local window and a node link *identically* — Brood's
"the frontend is a protocol; local-native and remote are the same code path"
principle made concrete.

The pieces are almost all data already:

- **Frames out.** The render frame is already plain `editor/display` ops
  (`clear`/`text`/`cursor`/`frame`) — plain data that copies across a link. Needs:
  a stable **version number** per frame (drop stale ones, `actor-architecture.md`
  hard-part #1) and a compact wire shape (ideally viewport diffs, not whole
  frames — the web mirror already sends only the visible window).
- **Events in.** Keystrokes/mouse from `gui-poll` are already plain-data events.
  Needs: the same shape delivered over a link into the event bus.
- **The module.** `std/editor/frontend.blsp`: a `frontend-serve` (core side —
  accept attachers, fan out versioned frames, receive events) and
  `frontend-attach` (client side — open a local `gui-display`, forward its events
  to the core, render the frames it pushes back). The local window becomes "the
  frontend that happens to be in-process." This generalizes `web.blsp`'s hub from
  read-only HTML to a read-write, transport-agnostic frontend channel — a `std`
  concern (any Brood editor frontend wants it), not a myedit one.

### 1.2 Markers — edit-surviving positions in `std/buffer`

**The core multiplayer gap.** A remote participant's cursor and selection must
survive *my* edits: if I insert 10 chars above your cursor, your cursor must move
with the text. That's a **marker** (an overlay position the buffer updates on every
edit) — which `actor-architecture.md` Part 1 already names as the first real
`std/buffer` primitive, wanted by overlays / diagnostics / LSP too. Without
markers, every concurrent edit invalidates everyone else's positions. Add
`buffer-marker` create/read/delete to `std/buffer`, positions adjusted inside the
edit primitives. This one primitive also underwrites Track 3's multi-cursor.

**As built (2026-07-10) — the buffers-as-processes foundation, in `../brood`.**
Shipped as a self-contained, unit-tested `std/editor/buffer` change ahead of any
editor-core work (the deliberate "foundation first" slice):
- **Markers.** `buffer-marker-set` / `buffer-marker` / `buffer-marker-delete` /
  `buffer-markers`, stored under a `:markers` map on the buffer. Positions are
  adjusted *inside* the edit primitives (`insert` / `delete-char` /
  `delete-backward-char` / `delete-region`) via `buffer--adjust-markers`, which is a
  no-op on a marker-less buffer (no `:markers` key added, so existing buffers are
  untouched). Left-gravity at the insertion point; a straddling delete collapses the
  marker to the range start; reads clamp to the current length.
- **The subscribe/push seam.** `buffer--serve` now carries `(subs version)`;
  `subscribe-buffer` / `unsubscribe-buffer` manage a push set, and every `:edit` /
  `:io-write` bumps the version and pushes `[:buffer-updated pid version (proj buf)]`
  to each subscriber (a new subscriber is seeded immediately). The rope never leaves
  the process — pushes carry only a derived projection. This is the collaboration
  seam two sessions/panes subscribe to; it does *not* yet drive the editor.
- **Tests:** `../brood/tests/buffer_test.blsp` — a pure `markers` describe (8) plus an
  `:isolated` `subscribe / push` describe (4). Full green: 79 buffer tests, 2656
  Brood-suite tests, and 756 myedit tests (on the reinstalled std), no regressions.

**As built (2026-07-10) — the model-side collab glue, `src/collab.blsp`.** Backs a pooled
buffer with the shared process, so panes in *different runtimes* share content while each keeps
its own cursor — the "everyone their own caret" mode (vs `serve-shared`, one cursor fanned to
all). It reuses the editor's existing local split: content on the pooled buffer value, point
per-pane (`model/ed-with-window-point`), now lifted across processes.
- `:shared {pool-index {:proc pid :version N}}` on the model links a slot to a buffer process;
  `collab-share-slot` subscribes + records it, `collab-unshare` tears it down.
- `ed-apply-buffer-update` folds a `[:buffer-updated proc version text]` push into the slot's
  content, leaving every pane's window-local point alone (cursors stay independent); stale
  versions are ignored.
- Edits are expressed as a **single positional splice** (`collab-splice` = shared-prefix/suffix
  trim → `[lo hi repl]`, applied with `replace-region`), so they land at the right offset
  regardless of other participants' points, and round-tripped edits both survive with no CRDT
  (v1, §1.4). Two ways to send: `collab-edit` (opt one edit in) or **`collab-propagate`** (a
  command-agnostic loop hook that diffs before/after and pushes any shared slot's change — so
  ordinary commands stay `model -> model`, no per-command changes).
- `collab-splice` is a small generic string utility (a char-level counterpart to std/diff's
  line-level `diff-seq`) — flagged as a candidate to lift into `std/string` if a second consumer
  appears; kept local for now (prime directive: surfaced, not buried).
- **Tests:** `tests/collab_test.blsp` — 7 pure splice tests + an 8-case `:isolated` describe
  (shared-process round-trip, independent cursors preserved, serialized two-participant edits,
  stale-version guard, propagate hook, unshare). Full green: 15 collab tests, 769 myedit tests,
  no regressions.

**As built (2026-07-10) — the live `--serve --collab` wiring.** The three pieces named above
shipped, headless-tested end to end (`tests/remote_test.blsp`, the `:isolated` collab-serve
describe):
- **Brood first (the language gap):** a served session was *deaf to async events* — the
  daemon-side displays' `:poll` (`remote-display`, `shared--display` in `std/editor/serve.blsp`)
  selectively received only `[:key]`/`[:detach]`/`[:down]`, stranding every other mailbox
  message, while the local `gui-display :poll` returns *any* message (the contract the editor's
  whole event bus — task replies, buffer pushes, log lines — is built on). Fixed in std: both
  polls now pass unrecognized messages through as app input; `serve_test` covers the pass-through
  at the unit and end-to-end level for both `serve` and `serve-shared`.
- **Editor:** `:buffer-updated` registered in `input`'s event registry (folds via
  `collab/ed-apply-buffer-update`); `src/remote.blsp` gained `ed-serve-collab` — ONE
  `spawn-buffer` process per daemon, a fresh session per client whose slot 0 is
  `collab-share-slot`-linked (the subscribe runs in the session process, so pushes land on its
  mailbox and arrive through the fixed poll) — and `ed-update-collab`, `ed-update` wrapped with
  `collab-propagate`. The wrapper skips propagation when the folded event *is* a
  `[:buffer-updated …]` push (propagating the process's own truth back would apply the edit
  twice). CLI: `bedit --name ed --serve --collab [file]`; clients `bedit --attach ed`.
- Tests prove: the seed push syncs a session through the real `ed-update`; no echo on a folded
  push; and two live sessions — a typed key reaches the process, a late joiner seeds to the live
  text (not the file on disk), and one participant's edit fans out to the other's frame, each
  keeping its own cursor.

**As built (2026-07-10) — presence: named remote carets (Slice 2b's visible half).**
- **Brood first (two gaps):** (1) the attach protocol carried no identity — `attach` /
  `attach-display` / `attach-display-local` now take an opts map (`{:name "alice"}`), sent as a
  5-element `[:attach client cols rows opts]` (4-element still accepted) and queued to the
  session as a `[:client-opts …]` event before any key; (2) the buffer process never noticed a
  dead subscriber — `buffer--serve` now monitors every subscriber and, on `[:down …]`, prunes
  the subscription **and deletes the marker keyed by the dead pid** (the convention for
  transient per-subscriber state), pushing so survivors see the cursor vanish rather than a
  ghost caret.
- **Editor:** each collab session announces itself on join — a cursor **marker keyed by its
  session pid** (edit-adjusted inside the process, so carets stay honest under others' edits)
  plus its name under `:participants`. The subscription projection (`collab--proj`) pushes
  `[text markers names]`; `ed-apply-buffer-update` stores other participants' cursors/names on
  the slot (own pid excluded), echoes churn (\"mona joined\"/\"left\", seed-suppressed), and
  skips the content rebuild on cursor-only pushes (cheap; local undo survives).
  `collab-sync-point` (in `ed-update-collab`) moves the marker when point moves — a
  version-guarded no-op otherwise. The view draws each remote caret as a coloured sub-cell bar
  + a name tag on the row above (`ed--remote-cursor-ops`, colour stable per name). Identity
  comes from `--as NAME` (default: the OS username) on both `--attach` and the host window.
- Tests: presence announce / sync-point / churn echo / no-rebuild in `tests/collab_test.blsp`;
  the live path (a named attach renders its tag in the other participant's frame) plus a pure
  view render test in `tests/remote_test.blsp`; the std seams (identity handshake,
  dead-subscriber marker cleanup) in `../brood`'s `serve_test` / `buffer_test`.

**As built (2026-07-10, second pass) — the whole slickness ladder.** One collaborative
mode (`--shared`, alias `--collab`; the fan-one-cursor editor mode is gone — `follow`
(C-x f) gives that experience per-person, broken by any move of your own);
origin-tagged edits (echo suppression — your round-trip never flickers fast typing);
`--listen [HOST:]PORT` (TCP, cookie-authenticated, loopback-verified — the runbook has
the cross-machine recipe); structured deltas (`buffer-splice` / `buffer-marker-move`:
O(change) pushes, in-place splice application with a `:pending` divergence guard that
resyncs on the rare in-flight collision); per-participant selections (`[pid :mark]`
markers, rendered as owner-coloured tints) and the modeline presence chip. Also fixed
en route: pid identity across `node-start` (brood kernel — equality/hash normalize the
local-node stamp), without which a served daemon silently dropped every push.

Still open: kernel dual-listen (Unix + TCP at once), CRDT (v2, unchanged).

### 1.3 A participant model — presence as plain data

Real collaboration needs per-participant point + selection + identity (name,
color), not the single shared point the buffer carries today.
`actor-architecture.md` already flags that **point should move off the buffer onto
the view/pane** — this is the same move, one level further: a *participant* is
`{:id :name :color :cursor(marker) :selection}`. Small enough to be editor policy,
but the shape (and the marker-backed cursor) is general; keep the marker in `std`
(1.2) and the participant record in the editor unless a second Brood app wants it.

### 1.4 Concurrent-edit reconciliation — and why v1 needs no CRDT

The scary part, defused by sequencing:

- **v1 — serialized single-core (no CRDT).** With **one** model in **one** core
  process, frontends send edit *intents* and the core applies them **serially** in
  arrival order. The actor model guarantees per-buffer total ordering
  (`actor-architecture.md` hard-part #1), so there is simply no merge conflict to
  resolve — the same reason two panes on one buffer are trivially consistent today.
  Latency is one round-trip per keystroke, fine on LAN / low-latency links. **This
  is the whole multiplayer experience with zero new reconciliation machinery.**
- **v2 — replicated / offline (CRDT), later.** Independent replicas that edit
  offline and merge need a real sequence CRDT (RGA/Yjs-style) as a `std` module
  (`std/text/replica` or similar). Big, and only needed for offline / high-latency
  independent editing. **Defer it** — it's unlocked by the buffers-as-processes
  decomposition, not a prerequisite for shipping multiplayer.

**Auth/identity.** The shared cookie authenticates the *transport* (same-user, or
an explicit cookie across machines). Multi-*user* collaboration wants a participant
name and, eventually, read-only vs read-write attach capability. Lightweight for
v1 (a name + the node cookie); richer authz deferred.

**Part 1 summary:** ship 1.1 (frontend protocol) + 1.2 (markers) as the real
language investment; 1.3 is small; 1.4 is "do nothing clever in v1." No CRDT until
v2.

---

## Part 2 — What we build in myedit (staged, each slice shippable)

Mirrors `actor-architecture.md`'s incremental philosophy: move capability outward
in slices, each independently useful, no big-bang.

### Slice 0 — Read-write web mirror *(days; no Brood change; proves the loop)*

Give `src/web.blsp` an **input channel**: the browser posts keystrokes back (a
`POST /input`, or upgrade to a WebSocket), the server forwards them as events into
the editor's event bus — the exact seam `[:web-port n]` already uses. A browser
becomes a real (single-shared-cursor) remote frontend. **Remote editing from your
phone, today**, entirely on existing primitives. This sharpens the frame/event
shapes before we formalize them in `std` (1.1).
- Touches: `src/web.blsp` (an input route + forward-to-bus), `src/input.blsp` (a
  `[:remote-key …]` event handler).
- Tests (extend `tests/web_*`): a posted key produces the expected model
  transition and the next pushed frame reflects it.

### Slice 1 — Native remote attach *(the `emacsclient` / daemon model)*

`nest run --name myedit-core -- file…` runs the editor as a **headless core**: the
`ui-run` model + event bus, but the frontend (the `gui-display` window) is
*detachable*. A second `nest` process `(connect "myedit-core")`, registers as a
frontend, opens a **local** `gui-display`, ships its keystrokes to the core, and
renders the versioned frames the core pushes back. That's `emacsclient`. One core,
N frontends, location-transparent via Brood distribution — **same code path local
vs remote**, the local window just being an in-process frontend.
- Builds on Part 1 §1.1 (the frontend protocol crossing the node link).
- New: `src/frontend.blsp` (attach/serve wiring over `std/editor/frontend`), a
  `--attach NAME` / headless-core entry in `src/main.blsp`.
- Tests: spawn a core proc, attach a frontend proc, `send` keys, assert the frames
  pushed back — the spawn-and-assert style the web tests already use
  (`tests/web_fuzz_session_test.blsp`, `tests/web_logging_test.blsp`).

### Slice 2 — Presence & multiple cursors *(the multiplayer payoff)*

Move point/selection off the buffer onto a **per-frontend participant** (Part 1
§1.2 markers + §1.3 model). The core tracks N participants; each frame carries
everyone's cursors/selections; the view renders remote cursors with a name tag +
color (Live Share / Google-Docs style). Two people attached to one core now edit
the same buffers and see each other move and type. Edits stay serialized through
the one core — **no CRDT** (Part 1 §1.4 v1).
- New: a participant registry in `src/model.blsp`, remote-cursor rendering in
  `src/view.blsp`, per-frontend focus/layout.
- Tests (pure, no window — like the existing view tests): participant folds; a
  remote cursor renders at the right cell; my insert above your cursor shifts your
  marker (the markers 1.2 behaviour).

### Slice 3 — Buffers-as-processes / distribution endgame *(the long game)*

The full `actor-architecture.md` path: buffers become processes that can live on
another node, services promoted to processes, per-buffer fault isolation, and —
with the v2 CRDT (Part 1 §1.4) — independent/offline editing. This is the endgame,
already the design-of-record; **cross-reference `actor-architecture.md`, don't
re-plan it here.**

---

## Sequencing & first move

| Slice | Brood needed | Independently useful | Effort | Status |
|---|---|---|---|---|
| 0 — read-write web mirror | none | remote edit from a browser/phone | days | ✅ shipped + live-verified |
| 1 — native remote attach | §1.1 frontend protocol | `emacsclient` daemon model | weeks | ✅ shipped (GUI two-window pending a `../brood` reinstall) |
| 2a — shared-model editing | none (additive to serve) | collaborative live editing (one cursor) | days | ✅ shipped (headless-tested) |
| 2b — distinct per-user cursors | §1.2 markers + point-off-buffer | Google-Docs-style presence | weeks | ⬜ deferred (needs the actor refactor) |
| 3 — buffers-as-processes | §1.4 CRDT (v2) | offline / fault isolation | large | ⬜ |

### Slice 0 — as built ✅
`src/web.blsp` gained a `POST /input` route + a keydown listener in the page: the browser
`fetch`es each keystroke, `web-key->token` (Brood, unit-tested against `gui.rs`'s vocabulary)
maps it to the editor's key token, and the worker `send`s that bare token to the editor
process — where the ui-run loop polls it as ordinary input, dispatched through the keymap
with **no change to `input`/`commands`** (a bare token isn't a `[:tag …]` system event). Tests:
`tests/web_input_test.blsp` (vocabulary + end-to-end dispatch + the handler's body→`send`
chain) + a live socket probe (real POST → token in the editor mailbox, status 204).

### Slice 1 — as built ✅
The Brood substrate already shipped `std/editor/serve.blsp` (ADR-090: `serve` daemon +
`remote-display` + terminal `attach`); the one gap was that the thin client was terminal-only.
**Part 1 (Brood):** added `attach-display` — the client generalized to *any* `ui-run` display
(a native window), reading frames + window input off one unified mailbox loop. `serve_test`
6/6 + the `serve_attach.rs` cross-node integration pass. **Part 2 (editor):** `src/remote.blsp`
(`ed-serve` daemon / `ed-attach` GUI client / model factory / CLI arg dispatch) + `main`'s
`--serve` / `--attach` modes. The real editor-as-daemon session (ed-view/ed-update folding
shipped keys, re-rendering frames) is verified headlessly in `tests/remote_test.blsp`.
**To use it:** rebuild Brood so its `std` includes `attach-display`
(`cd ../brood && ./configure --with-gui && make install`), then `bedit --name ed --serve` in
one place and `bedit --attach ed` in another. The two-window GUI is the one part unverifiable
without a display.

### Slice 2 — as built (shared editing ✅; distinct cursors deferred)
Split honestly in two:

- **2a — shared-model editing ✅.** Added `serve-shared` to `std/editor/serve.blsp`: instead
  of a fresh model per client (`serve`), it runs **one** `ui-run` and fans its frames to every
  attached client through a dynamic hub while merging all their input into the one loop — so
  everyone edits the same buffers and sees each other's edits live. Additive (no core-buffer
  change), and headless-tested (`serve_test`: two clients share one model, an edit by one is
  seen by both). Editor side: `ed-serve-shared` + the `--shared` modifier
  (`bedit --name ed --serve --shared`). Because input merges through one mailbox, edits
  serialize with **no CRDT** (Part 1 §1.4 v1) — the actor's per-buffer total ordering.
- **2b — distinct per-participant cursors ⬜ (deferred).** All clients share **one** cursor
  today (the single model's point). Giving each participant their own caret + selection needs
  **edit-surviving markers** in `std/buffer` (§1.2) *and* point moved off the buffer onto a
  participant record — the `docs/actor-architecture.md` decided-but-deferred refactor, which
  touches every command and is GUI-verified. Markers were deliberately **not** added yet: their
  only consumer (distinct cursors) depends on that refactor, so adding them now would be unused
  risk in the editor's most-depended-on module. This is the next real chunk of Track 1.

**Start with Slice 0.** It ships value on day one, needs no Brood change, and the
frame/event shapes it exercises become the spec for `std/editor/frontend` (§1.1) —
so we design the protocol from a working thing, not on paper. Then §1.1 + Slice 1
(the daemon model), then the markers investment (§1.2) that unlocks Slice 2's
multiplayer *and* Track 3's multi-cursor at once.
