# Remote & multiplayer editing — current state

**Status:** built (2026-07). One editor core you attach to from anywhere; multiple
people editing the same buffers with live presence. Usage lives in
[`working-from-another-computer.md`](working-from-another-computer.md); the dated
build history is in [`devlog.md`](devlog.md); the actor endgame this feeds is
[`actor-architecture.md`](actor-architecture.md).

## The architecture, as built

- **Serve/attach (the daemon/emacsclient model)** — `std/editor/serve` (ADR-090):
  the daemon runs the editor (model/`ed-view`/`ed-update`); a thin client paints
  pushed frames and ships keys over a Brood node link. Sessions are per-client;
  the host's own window is just another attach (`attach-display-local`). Clients
  carry an identity opts map (`--as` → `[:client-opts …]`); the daemon-side
  displays pass async mailbox messages through to the app's update (the event
  bus works served exactly as local); `serve-stop` ends every session.
- **Shared content = a buffer process** — `src/collab.blsp` over
  `std/editor/buffer`: the document is authoritative in ONE process; every
  session subscribes and receives versioned pushes. A per-daemon **file registry**
  gives each path one process, and `collab-autoshare` links any file a session
  visits — the whole project is collaborative, not just the launch file.
- **Edits are based positional splices** — `buffer-splice` + the slot's version.
  The process transforms a stale-based splice over what landed since
  (`splice-transform`, a ring of the last 64); clients mirror the transform
  against their in-flight `:pending` splices. Concurrent typing in different
  places merges exactly (no CRDT); your own echo is origin-tagged and folds as a
  version bump (no flicker); an ambiguous same-span collision resyncs from the
  process. Pushes carry deltas — the document never ships after the seed.
- **Presence rides markers** — cursor / `[pid :mark]` selection / `[pid :top]`
  viewport markers keyed by the session pid, adjusted *inside* the process's edit
  primitives and deleted by it when a subscriber dies (no ghost carets). The view
  renders other carets as coloured bars (name tags fade a few beats after that
  caret moves), selections as owner-coloured tints, plus a modeline chip and
  join/leave echoes.
- **Follow / mirror** — `share-follow` (C-x f) pins your point (and buffer —
  presence migrates with the leader, so followers switch files with them);
  `share-mirror` also adopts their viewport. Any move of your own takes the wheel
  back. `M-x share-session` / `share-session-stop` host from a live editor — the
  collab chain (`collab-step`) runs at `ed-update`'s tail and is a no-op unless
  the model is shared.
- **Transport** — a per-user Unix socket always; `--listen [HOST:]PORT` adds a
  cookie-authenticated TCP listener (kernel dual-listen, ADR-074), so
  `bedit --attach ed@HOST:PORT` works from another machine.

## Kernel ground this track won (all upstream)

Pid equality/hash across `node-start` (a captured pre-node pid silently stopped
matching); exit signals reaching natively-nested receives (the immortal-process
bug, ADR-132); `%isolate`'s reap no longer kills its own caller; native
`scan-form-start` (eldoc/fontify restarts had gone multi-second interpreted);
buffer-process subscriber lifecycle + structured deltas + splice transforms.

## Open

- **v2 CRDT** (`std/text/replica`-shaped) — offline / high-latency divergence;
  everything above assumes connected round-trips.
- **Per-participant undo** — "undo *my* edits" once histories interleave.
- **Cross-machine verification** — `--listen` is loopback-verified; the same code
  path needs one real second-machine run.
- ~~Point-off-buffer for local panes, per-buffer supervision, services as
  processes~~ — **built 2026-07-11**: the §E.2 endgame flipped the pool (every
  buffer hosted, fault-isolated, services async; `actor-architecture.md` is now
  the as-built record). This ledger's shared-buffer machinery became the general
  case: std `editor/buffer-client` (ADR-134) + `src/hosted.blsp`, with `collab`
  reduced to the presence layer.
