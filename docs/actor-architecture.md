# The actor-model editor (design note — BUILT)

**Status: built, 2026-07-11.** Every open item from this note shipped as the §E.2
endgame (a staged sequence on top of Track 1's collab slices):

- **Every buffer hosted as a process** — the live window's model carries
  `:host-buffers?`; `hosted/hosted-reconcile` at the loop tail backs every pool slot
  (files, `*Messages*`, dired, occur) with a `std/editor/buffer` process, no
  call-site cooperation. The pool value is the local **projection cache**: commands
  stay pure `model -> model` (local-apply-first — the caret never waits), the loop
  tail ships based splices (`hosted-step`), pushes fold back with echo suppression.
  The content protocol's client half was extracted to **std `editor/buffer-client`**
  (ADR-134: `link-init`/`link-propagate`/`link-fold`/`text-splice`, native
  `%str-splice-diff`); a collab-SHARED buffer is now just a hosted slot whose
  process has remote subscribers (`collab` = the presence layer, nothing more).
- **Point off the buffer** — pane point/mark/scroll/zoom were already per-pane; the
  invariant is now explicit and test-guarded (window_point_test): pane point is
  authoritative while displayed, the pooled `:point` is only the Emacs-style saved
  default (`ed-show-index` its one consumer). Kept deliberately — Emacs' own model.
- **Per-buffer fault isolation** — every hosted process is monitored; `[:down]`
  rehosts a local slot from the pool cache (`hosted-rehost` — the cache IS the
  crash-recovery copy; at most in-flight splices lost) or re-shares a shared slot
  onto the registry's respawn (`collab-reshare`); the registry keeps a per-path
  text MIRROR (the same std client fold) and respawns died buffers from current
  content. Supervision-by-monitor was chosen OVER an OTP supervisor for buffers:
  restart must reseed from the newest cache, which lives with the model holder.
- **Services as processes** — eval, web mirror, logger, bshell, compile were
  already off-loop; diagnostics and now **eldoc** ride the `std/task` idle-beat
  pattern; **every LSP lookup is async** (corr-matched `:lsp-pending` + event-bus
  folds; mutating replies rope-guarded; completion keeps its bounded modal wait).
  diff-hl stays synchronous BY DECISION — E0's investigation exonerated the async
  reply path (the June-16 freeze was a stuck `:held-key` gating the idle beat) and
  the sync-on-idle git diff stands on its own merits.
- **View as aggregator** — definitionally complete: the pure `view` renders the
  pool, and the pool IS the latest-projection cache of the authoritative buffer
  processes, reconciled by version through `link-fold`.

**Deferred, with triggers** (the honest residue):
- **kill-ring as a process** — no present payoff (tiny single-writer model state);
  trigger: a SHARED kill-ring across collab sessions / OS-clipboard bridging.
- **fontify as a persistent per-buffer worker** — the lexer is stateless and the
  lex is viewport-windowed (bounded per frame); trigger: incremental parse state
  (tree-sitter incremental, ADR-103's deferral) worth keeping warm in a process.
- **supervising the collab registry process itself** (its buffers self-heal; its
  death keeps the graceful "sharing disabled" path) and **session-local hosted
  teardown** on serve-session death (needs a last-subscriber-stops policy in std).

**Review residue (2026-07-11 multi-angle review — accepted, not yet built).** The
review's correctness findings were fixed the same day (see the two `fix(…): …review
fixes…` commits + the brood repo's OT/`buffer-sync`/serve/require fixes); these
efficiency/altitude items were judged real but deferrable:
- **propagate cost**: the loop tail materialises the edited buffer's full text twice
  per keystroke to recover a splice the edit primitive already knew (~1 ms/key at
  100 KB, linear beyond). Deeper fix: stamp `:last-edit [lo hi repl]` on the buffer
  value in std's editing ops (or a native rope-diff) and let propagate read it O(1).
- **registry mirror is a string**: `text-apply-splice` rebuilds each shared document
  O(doc) per keystroke server-side; a rope-backed mirror (`replace-region`, text
  materialised only at respawn) is the drop-in fix. Extracting the whole mirror as a
  std "holder" (ADR-134's shape) would also delete the registry's inline fold.
- **presence ops ship the document**: announce/withdraw/mark-clear are closure edits
  → full-projection pushes to every subscriber; the wire wants `:marker-delete` and
  a participants-only delta op beside `:marker-set`, and the splice push could drop
  its full marker map (clients can shift markers locally).
- **eldoc ships the whole buffer** into its task per idle beat; a bounded window
  around point suffices.
- **wide-`receive` budget**: `buffer--serve` must stay ≤12 arms (brood KI-10 — the
  13th arm cost +65% wall/+80% peak across the buffer suite until the two `[:edit]`
  arms were merged). Bear it in mind before adding protocol ops; fix belongs in the
  kernel's receive compiler.
- smaller: LSP requests could carry protocol-level document versions instead of
  per-command rope guards; `hosted--proj`'s presence-triple encoder belongs beside
  its `view-parts` decoder in std; the `ht/ct-await-down` test helpers and the
  `buffer--serve` splice-arm bodies each want one shared shape.

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

## When to actually do this (historical)

This section originally said "not now — earn into it per-buffer." We earned into it:
Track 1 proved the seam on shared buffers, and the §E.2 endgame (2026-07-11) flipped
the pool. What made the flip cheap in the end was exactly what this note predicted —
the pure model never went away: the pool value became the projection cache, commands
stayed `(model, key) -> model`, and the ~800 pure tests run unchanged on unflagged
(headless) models. The conviction held: the actor model is the right end-state for
*this* editor, and push-projection rendering removed the cost that argued against it.
