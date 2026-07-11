# The actor-model editor (design note, deferred)

**Status:** design-of-record — and as of 2026-07-10/11 its first real slices are
**built and shipped** by Track 1 (`remote-multiplayer-plan.md`): buffers as
processes for SHARED buffers (`std/editor/buffer` `spawn-buffer` + subscriptions +
versioned delta pushes), edit-surviving **markers** adjusted inside the process
(presence cursors/selections/viewports ride them), and concurrent-splice
transforms. The local single-window editor still runs the single-process pure
`ui-run` loop; still open from this note: point-off-buffer for local panes,
per-buffer supervision/fault isolation, services as processes, and the view as a
pure aggregator of pushed projections.

The question that started this: *why not have a process per buffer?* — and then, more
pointedly, *what if we lean into message-passing instead of cataloguing what stops
us?* This note is the answer: how an actor-model editor would actually work in Brood,
why it's the right end-state for **this** editor specifically, and how we'd get there
without a big-bang rewrite.

## Where we are today, and why it's good

The loop is TEA: `view = f(model)`, `model' = update(model, input)`, both pure, and
**the model is one immutable value** with every buffer inside it (`:buffers`). That
single fact is why a lot of hard things are currently trivial:

- **Undo** is just keeping old buffer values; the **web mirror** and the ~280 tests
  are just reading the model value; **two panes on one buffer** see each other's edits
  because it's literally the same value.
- Every command is a pure `(model, key) -> model` testable with no window, no
  spawning, no mailbox.
- Commands that touch a buffer **and** global state — `kill-region` (delete text *and*
  push to the kill-ring), `C-x k`, the minibuffer, pane layout — are one synchronous
  step over one value, with no interleaving.

The editor is single-process *on purpose*: the buffer pool **is** the model, and a
pure model is the editor's biggest current asset. It is also the one place in this
codebase that doesn't use Brood's process-everywhere grain.

## The reframe: push, not pull

The standard objection to buffers-as-processes is "then the loop has to query every
buffer every frame." That's only true if messaging is **pull**. Make it **push** and
the objection inverts:

- A buffer process owns its text and, on every change, **publishes a small
  projection** — the visible viewport's text + spans + a **version number** — to its
  subscribers (the panes showing it).
- The renderer keeps the *latest projection per visible buffer*, always fresh because
  the buffer pushes it. Rendering reads local projections and never blocks on a query.
- The buffer becomes the **source of truth**; the loop becomes a **view aggregator**.
  The loop's "model" shrinks to *focus + layout + the projection cache* — small, and
  still pure to render.

So "more messaging" doesn't force pull-per-frame; it moves the truth into the buffer
and lets it flow outward. That's a cleaner separation than today, where the loop owns
everything.

## The decomposition (who owns what)

Split state by **who anchors to text positions**:

- **Buffer process** — the rope, **markers/overlays** (positions that survive edits),
  undo. It is already an `io` sink (`[:io-write s]` appends — see `std/buffer`'s
  `buffer--serve`). Owns everything anchored to text.
- **Pane / view** — `point` and scroll. (Today point lives *on the buffer*, so two
  panes on one buffer share a cursor — not even real Emacs behaviour. Moving point to
  the pane *fixes* that and is the natural actor split.)
- **Session / loop** — focus, layout, routing each keystroke to the focused buffer,
  folding pushed projections into a frame.
- **Services as processes** — kill-ring (a clipboard service), logger (done), LSP /
  diagnostics, fontify / parse, web mirror (done), eval (done).

Editing stays atomic for free: a keystroke becomes an **edit closure shipped to the
buffer process** (`buffer-edit` already does this — closure-as-data, ADR-033), applied
serially. No intra-buffer races, ever — the actor model guarantees per-buffer total
ordering.

## What it unlocks

These become easy or free, and are hard any other way:

- **Concurrency for free** — fontify, parse, LSP diagnostics, indexing each run in
  their own process; the loop never stalls on a 100k-line file. Cashes in the
  per-process-heap / `gc_floor` work.
- **Supervision everywhere** — a crashed buffer/worker is restarted by its supervisor,
  the same pattern as the logger. ("process-per-buffer recovery" becomes real.)
- **Distribution ≈ collaboration, nearly free** — a buffer process can live on another
  node (`remote-spawn` + node links). Two editors subscribed to the same buffer pid =
  collaborative editing, because *messaging doesn't care about locality*. A
  shared-value model can never reach this; a push/actor model gets it as a side
  effect.
- **Self-editing** — a buffer's mode/services are processes you swap live; the
  late-bound keymap we already have extends naturally to late-bound *services*.
- **`*LSP*`-as-process** — that buffer is a direct `process-backend` log target; the
  LSP client streams straight into it, no loop relay. (This is why the log-routing
  foundation — one logger, a filtered backend per buffer — was built first.)

## The genuinely hard parts — and their answers

Design problems, not blockers:

1. **Stale frames / ordering.** Each projection carries a **version**; the renderer
   keeps the highest seen and drops older ones. Editors render async anyway; a
   one-frame lag reconciled by version numbers is standard. Within a buffer, ordering
   is total (the actor serializes), so there's never intra-buffer inconsistency.
2. **Read-then-decide commands** (`kill-region`: read region → push to kill-ring).
   Send the buffer a closure that returns *both* the new buffer **and** the killed text
   in its reply; the loop forwards the text to the kill-ring service. One round-trip,
   still ordered — the same shape as today's `:task-done` eval reply.
3. **Cross-buffer atomicity** (a refactor over N buffers). Rare; a small coordinator
   process drives it, or accept eventual consistency. ~99% of ops are single-buffer.
4. **Testability.** Changes shape, not difficulty: Brood's own suite is full of
   `spawn → send → assert on the reply/push` (the supervisor, log, and buffer-actor
   tests are exactly this). We trade pure `(model, key) -> model` for spawn-and-assert
   — a proven, well-supported style here.

## A staged path (ambitious, not big-bang)

Move the *truth* into processes incrementally, behind today's accessors:

1. **Host one buffer as a process** behind the model API: the model holds
   `{:pid :projection}` instead of a buffer value; `ed-current-buf`-style reads hit the
   projection; edits ship closures; the buffer pushes `[:buffer-updated id projection]`
   → a new event handler folds it (the `input.blsp` event bus is already the inbound
   seam). Prove push-rendering on one buffer, everything else unchanged.
2. **Flip the pool** — every buffer hosted; point/scroll move to the pane; the loop
   model becomes focus + layout + projection cache.
3. **Promote services** — kill-ring → process; fontify/parse → per-buffer worker; then
   the LSP client. Each under a supervisor, extending the logger tree.
4. **The free wins** — a buffer on a second node → collaborative editing.

A smaller, lower-risk first slice that proves the pattern without touching the model
for everything: move **fontification to a per-buffer worker process** that ships the
text out (as a string — ropes are process-local), computes spans off-loop, and pushes
them back through the event bus. Same shape the LSP client will use.

## Prime-directive split (what's Brood vs. what's the editor)

**Part 1 — Brood / `std`.** The maximal version wants a few real primitives:
- **Markers** — edit-surviving positions — in `std/buffer` (overlays/diagnostics/LSP
  all need them).
- A **versioned-projection / subscribe** helper (a reactive-value pattern in `std`).
- A **supervised buffer-worker** abstraction: a buffer plus its fontify/LSP children
  under a per-buffer supervisor, restartable — generalizing the logger supervisor we
  already wrote.
- Distribution is already there (`remote-spawn`, node links).

The actor shell itself already exists — `std/buffer`'s `spawn-buffer` / `buffer-edit` /
`buffer-query` / `stop-buffer`, with the hard constraint that **a rope never crosses a
process boundary**: edits and reads cross as *closures*, and a read closure must return
a non-rope value. That constraint is a feature — it forces share-nothing, which is what
makes the system robust and distributable.

**Part 2 — the editor.** The staged restructuring above.

## When to actually do this

Not now. The single-process pure model is serving us well, and the actor rewrite
dismantles it. Earn into it per-buffer when a buffer is genuinely heavy (huge files),
externally backed (a `*shell*`/comint buffer that *owns* a subprocess — those should be
buffer-processes, and the `[:io-write]` sink is built for it), or when we want true
per-buffer fault isolation or collaboration. The conviction: the actor model is the
right end-state for *this* editor — it's the one app Brood exists to make possible —
and push-projection rendering removes the cost that would otherwise argue against it.
