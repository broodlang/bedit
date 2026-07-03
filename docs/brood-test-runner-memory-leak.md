# Report: unbounded memory growth running the full test suite (a Brood runtime bug)

**Status:** ✅ **RESOLVED** in `../brood` — fixed by `9f5c6e2 fix(runtime): rewrite
declared_sigs + form positions across a RUNTIME compaction` (and `71379f8
fix(test): scope the nest-mcp structured run-tests path too`); recorded as
KI-5..KI-8 in brood's known-issues. Kept here as a record + regression repro.
**Date:** 2026-07-03 (diagnosed), resolved same session.
**Brood build:** leaked on `0.1.0 (0d6d46e)`; fixed as of `0.1.0 (14870e3)`.
**Editor build:** `brood-edit` @ `0ce6085`.

## Resolution

The retained memory was **runtime-internal**, exactly as the diagnosis predicted
(not an editor global, not the JIT, not the test framework's logic): the runtime
did not rewrite `declared_sigs` + form positions across a **runtime heap
compaction**, so those structures were retained and grew as the long-lived runner
process exercised more distinct code. After the fix the full `brood-edit` suite
runs **725 passed, 0 failed, peak 199.5 MB, 1.7 s wall** (was OOMing at the 1 GB
soft cap, ~16–44 s). The rest of this document is the original diagnosis, kept
because the evidence, the ruled-out matrix, and the `probe_D` mechanism repro are
useful regression references.

## TL;DR

Running the whole `brood-edit` suite (`nest test`, 725 tests) dies with

```
runtime error: memory limit exceeded: ~1.13 GB allocated process-wide
  exceeds the 1073741824-byte soft limit
```

716 tests pass; **9 "fail" only because they are the workers that happen to be
allocating when the process-wide total crosses the 1 GB soft cap.** They are
victims, not causes — every one of them passes in isolation.

The memory is **live/GC-rooted (not collectable garbage), grows monotonically
with the number of *distinct* tests executed in one long-lived runner process,
and is independent of the JIT and of test parallelism.** It is a **Brood runtime
retention bug**, not an editor bug and not a test-suite logic bug. The suite is
logically green.

## How to reproduce

```bash
cd brood-edit
nest test                         # 9 "failures", all "memory limit exceeded"
nest test -j 1                    # same 9 — NOT concurrency
BROOD_NO_JIT=1   nest test        # same ~1.34 GB peak — NOT the JIT
BROOD_GC_STRESS=1 nest test       # still OOMs (driver itself dies) — NOT collectable garbage
BROOD_MEM_LIMIT=4294967296 nest test   # OOMs at ~3.3 GB — unbounded, cap just delays it
```

Single files always pass; the `mem-peak` line in the summary reports only the
**main/driver** process and is a constant ~175 MB regardless of file — it is
**not** the process-wide figure that trips the cap, so don't trust it as the
memory signal. The real signal is the `bytes allocated process-wide` counter
(`(mem-bytes)`), which is what the soft limit guards.

## Evidence

| Experiment | Result | Rules out |
|---|---|---|
| Full suite, `-j` default / `-j 2` / **`-j 1`** | OOM, same 9 tests | concurrency / parallel aggregate |
| `BROOD_NO_JIT=1` full suite | OOM ~1.34 GB | the JIT (HOF/unboxed-register work) |
| `BROOD_GC_STRESS=1` full suite | OOM (driver dies too) | **collectable garbage** — memory is live |
| `BROOD_MEM_LIMIT=4 GB` | OOM at ~3.3 GB | a merely-low ceiling — growth is unbounded |
| Each of 24 files **alone** | all pass, main-proc peak const 175 MB | any single heavy file / test |
| All 8 process-spawning files removed (470 tests) | still OOM ~1.32 GB | leaked spawned processes / subprocesses |
| Non-spawning files split in halves (113 / 357 tests) | **each half passes**; together OOM | a concentrated culprit — it is **additive** |
| Cumulative prefix at 1 GB cap | ~290 tests pass, ~425 tip over | — knee ≈ **1 GB per ~450 real tests ≈ ~2.3 MB/test retained** |

### Synthetic probes (pure Brood, no editor) — what does *not* leak

All four ran 300–600 spawned workers / tests and stayed **flat at ~10–15 MB**
`mem-bytes`:

- **Serial** spawn+await of 400 workers each allocating ~500k cons cells → flat.
  → basic process-exit heap reclamation works.
- **Concurrent** batches of 4 workers × 150 batches → flat.
  → the runner's concurrent-batch + collect machinery is fine.
- 500 tests exercising the **common editor pipeline** `(ed-init (make-buffer …))`
  + `ed-update` key dispatch on a small buffer → **pass**.
- 300 tests on an **8 KB buffer** with motion/render → **pass**.
- 500 tests interning **distinct symbols/keywords** via `read-string` → **pass**.

So the leak is **not** basic spawn/exit, not the collector, not the common
model/key-dispatch path, not large ropes, not symbol interning.

### The one synthetic probe that DOES leak — the mechanism

```brood
(def *sink* nil)
(describe "probe D"
  ;; ×400, each a separate parallel worker:
  (test "tN" (do (def *sink* (cons (repeat 30000 N) *sink*))
                 (is (> (count *sink*) 0)))))
```

→ **OOMs at 1 GB.** Because non-`:isolated` test workers **share one global
table** (by design — see `std/tool/test.blsp` "SHARE-SAFE TALLYING" and
`docs/shared-code.md`), a worker's `def` into a shared global **survives the
worker's exit** and **accumulates**, and it is **rooted by the global table so
no GC can reclaim it.** This exactly reproduces the observed signature:
live, GC-proof, additive, unbounded.

## What this means

The runner's whole memory-bounding strategy (`std/tool/test.blsp`, the block at
"The test runner" ~line 545) rests on: *each parallel unit runs in its own
worker process, and "each then exits and its LOCAL heap is reclaimed wholesale."*
That holds for a worker's **local** heap (proven by the serial/concurrent
probes). It does **not** hold for anything a worker writes into the **shared
global table** — that is retained for the entire run and is never reclaimed.

The editor suite therefore leaks ~2.3 MB of **rooted** memory per distinct test
and crosses 1 GB at ~450 tests. Note the trigger tracks **code diversity**, not
test volume: 500 *identical* synthetic tests do not leak, but 470 *diverse* real
tests do — pointing at something retained **per distinct execution path**, most
of which is almost certainly **runtime-internal** (see below), not an editor
`def`.

The editor's own shared-global registries were audited and are **not** big
enough to explain 2.3 MB/test — they are bounded `assoc`-by-name maps or tiny
`cons` lists holding small entries:

```
src/interactive.blsp  *command-syms* *commands* *prefix-consuming* *command-inverse*  (assoc by name — bounded)
src/keymaps.blsp       *profiles*                                                      (assoc by name — bounded)
src/complete.blsp      *completion-sources*                                            (cons of a symbol — tiny)
src/model.blsp         *log-routes*   (cons of {:category :buffer} — tiny; no call sites on the tested paths)
src/complete.blsp/view *word-cache* *bracket-cache*  (overwrite one slot — bounded to one rope)
```

So the retained object is most likely **inside the runtime**: some per-distinct-
function or per-distinct-form structure that is rooted globally and grows as the
suite exercises more of the codebase — e.g. an analyzed/prepared-form cache, a
dispatch/inline cache, a macro-expansion cache, or global-table/env entries that
are interned and never released. `BROOD_NO_JIT=1` still leaks, so it is **not**
the JIT code cache specifically.

## Suggested next steps in `../brood`

1. **Instrument the driver.** Add a `(mem-bytes)` print inside `run-driver`
   (`std/tool/test.blsp`) per step, and run a real OOM-ing subset (e.g. the 16
   non-spawning `brood-edit` files). Confirm the process-wide counter climbs
   step-by-step and identify the slope.
2. **Heap-profile the retained set.** Use `BROOD_GC_TRACE` / `BROOD_PERF_STATS`
   (and/or `nest observe` on a long run) to see what the live set is dominated by
   after N steps — is it env/global-table entries, prepared-form/AST nodes, a
   dispatch cache, or process control blocks?
3. **Confirm the mechanism** with probe D above (reproduces in seconds, no
   editor needed). Then bisect: does a purely runtime workload that calls many
   *distinct* freshly-defined functions across many workers grow the same way?
   If yes, the retained object is per-distinct-callee runtime state.
4. **Two directions for the fix** (per the brood-edit prime directive, prefer
   the language fix):
   - **Brood (preferred):** whatever per-distinct-execution structure is being
     retained globally should be reclaimable, scoped to a process, or bounded —
     so a long-lived runner running thousands of diverse tests stays flat. This
     also protects the `nest mcp` hot-reload session (ADR-013) and any
     long-lived image, not just the test runner.
   - **Runner mitigation (stopgap):** in `std/tool/test.blsp`, run parallel units
     in their own global-table scope (like `:isolated`'s `%isolate`, but without
     the serialization cost), or periodically snapshot/restore the shared table
     between batches, so worker-written global state can't accumulate across the
     whole run.

## Appendix — repro scripts

Saved under the session scratchpad during investigation (pure Brood, runnable
with `nest run <file>`):

- `spawn-leak.blsp` — serial spawn+await, no leak (baseline).
- `conc-leak.blsp` — concurrent batches, no leak (baseline).
- `runner-leak.blsp` — faithful driver/collector mimic.
- `probe_A/B/C.blsp` — editor pipeline / big-buffer / interning, no leak.
- `probe_D.blsp` — shared-global accumulation, **OOMs** (the mechanism).
```
