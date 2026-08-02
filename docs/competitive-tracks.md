# Competing with Neovim, Emacs & VSCode — the three tracks

**Status:** strategy note. Where bedit stands against the big three, and the
three tracks that would make someone *choose* it over them rather than settle for
a smaller Emacs. **Track 1 (remote & multiplayer) is now largely BUILT** — daemon
attach, one shared mode with per-participant carets/presence, follow/mirror,
share-session from a live editor, delta+transform merges, TCP `--listen`; see the
as-built ledger in [`remote-multiplayer-plan.md`](remote-multiplayer-plan.md) and
the runbook in [`working-from-another-computer.md`](working-from-another-computer.md).
Remaining on that track: the v2 CRDT and per-participant undo. This doc is the map.

## Where we actually stand

bedit is well past "toy." The feature-parity checklist most young editors are
missing is largely *checked* (see `ROADMAP.md` for the full list): undo with
Emacs-style boundaries/amalgamation, keyboard macros, LSP wired all the way
through (goto-def, references, hover, rename — not just completion), tree-sitter
fontification + structural motions, diagnostic underlines, Vertico-style
completion, a Magit porcelain, dired, isearch/query-replace, projects, registers,
bookmarks, occur, modes/themes, splits, a live web mirror.

So the useful question is **not** "what features are missing." It's **"where do we
stop chasing and start winning?"**

## The trap: don't out-checklist a 40-year ecosystem

You will never out-feature the big three by matching them one capability at a
time. VSCode has thousands of extensions and a paid team on the debugger; Emacs
has org-mode and 30 years of packages; Neovim has the tree-sitter/Lua plugin
explosion. Chase parity and bedit is always *N* features behind, forever.

The reason this project exists (the prime directive) is that it's written in
**Brood — a language built to host a self-editing, remotely-hostable editor**. So
the comparison that matters isn't "does it have what they have," it's **"does it
do the thing they structurally can't?"** That's where the effort goes. Each track
below leads with the *language* work (Brood / `std`) and only then the editor
work, because most of these are really Brood features surfaced in the editor.

## Track 1 — Remote & multiplayer *(the flagship — where Brood wins outright)*

One editor core you attach to from anywhere, and multiple people editing the same
buffers with live presence. This is TRAMP + VSCode Remote-SSH + Live Share + the
web editor, in one — and it's the thing none of the big three can copy cheaply,
because their models are single-process and local. Brood's is not.

- **Why it's ours to win:** Brood's thesis is *the frontend is a protocol;
  local-native and remote are the same code path with different transports*
  (`../brood/docs/node-connect.md`). The distribution substrate already ships —
  `node-start`/`connect` by name, remote pids, location-transparent `send`,
  `nest run --name` (the `emacsclient --daemon` model), all done (ADR-068). And
  `src/web.blsp` is *already* a read-only multi-frontend broadcast. The endgame is
  the decided-direction actor architecture (`docs/actor-architecture.md`), which
  names this outright: "distribution ≈ collaboration, nearly free."
- **Reachability:** high. Most of the substrate exists; the missing pieces are a
  `std` frontend/session protocol, `std/buffer` markers, and a participant model.
- **Full two-part plan:** [`remote-multiplayer-plan.md`](remote-multiplayer-plan.md).

## Track 2 — Self-editing, live *(the other Brood-native superpower)*

Emacs's actual killer feature isn't org-mode — it's redefining any command while
it runs. bedit already has the hard part: **late-bound command symbols and
hot-swappable keymaps** (a key dispatches to a *symbol* resolved at call time, so
a `C-x C-e` on a `defcommand` hot-swaps the binding under your fingers, no
restart). Turning that into a first-class experience — `describe-key` /
`describe-function` that jump to and edit the defining form, a discoverable
command/settings surface, redefine-and-see-it-live — is mostly editor work on
primitives that already exist.

- **Language work:** the customization surface Brood-side gaps are already scoped
  in [`configurability.md`](configurability.md) (a `std/settings` registry, the
  `kbd` key-parse/describe bijection) and the ecosystem gaps in
  [`packages.md`](packages.md) (package-rooted namespaces + `:exports`, runtime
  `load-nest`). Those docs are Track 2's Part 1.
- **Reachability:** high, and it makes the editor *demo itself*. Good second bet.

## Track 3 — Selective table-stakes still genuinely missing

Not a checklist chase — the few high-signal gaps a user hits immediately. Pick
these off opportunistically; they're how you avoid embarrassment, not how you win.

| Gap | Note | Cost |
|---|---|---|
| **Multi-cursor editing** | VSCode's signature interaction; not present. The immutable buffer model makes N-cursor edits clean, and the *same* per-participant cursor primitive Track 1 needs (`std/buffer` markers) serves this. Highest bang-for-buck. | medium |
| **Diagnostics / quickfix list** | We render underlines but there's no "jump through all errors" buffer + navigation (flycheck / `:copen`). | small |
| **Snippets / templates**, signature-help popups | Everyday LSP-adjacent polish. | small–medium |
| **Rectangles**, narrow-to-region | Already tracked in `ROADMAP.md` §D (narrow needs a `std/editor/buffer` restriction — the one real language gap there). | small |
| **Integrated debugging (DAP)** | The one big VSCode thing with no analog here. Large; defer unless it's a target use case. | large |

## Recommendation

Don't spread across all three. **Pick a flagship and go deep** — that's what makes
someone choose bedit over the big three. The order that plays to Brood's strengths
and to what's already built:

1. **Track 1 (remote & multiplayer)** — the flagship. On-thesis, the substrate is
   mostly there, and nobody else can follow. Start here; see the plan doc.
2. **Track 2 (self-editing)** — the most reachable, and it makes the editor
   demonstrate its own premise.
3. **Track 3** — pick off **multi-cursor** first (it doubles as Track 1's cursor
   primitive), then the diagnostics list; leave DAP for last.
