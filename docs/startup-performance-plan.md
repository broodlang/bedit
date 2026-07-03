# Startup performance — async loading + image cache

Two complementary fixes for brood-edit's ~1.1 s cold startup. **Async deferred
loading** (editor-side, ships now) fixes the *cold* path; an **image cache**
(a Brood feature, later) fixes the *warm* path. They reinforce each other — the
async background loader doubles as the image writer, and on a warm launch the
image makes async a no-op. Ship async first, layer the image cache second.

## Motivation (measured, 25 modules)

`nest run` → `main`-entry is ~**1.17 s**; the in-`main` setup (config, project,
buffer, `gui-display`, model, theme, logging) is only **53 ms** — and
`gui-display` (window + GPU) is 50 ms of that. The cost is the **module load,
before `main` runs**:

| Phase | Cost | Notes |
|---|---|---|
| nest base (prelude) | 40 ms | — |
| std modules the editor uses | +40 ms | — |
| parse all 25 files (1213 forms) | 10 ms | negligible |
| top-level macroexpand | 31 ms | negligible |
| **eval of the editor's 25 modules** | **~1.0 s** | the target |
| `gui-display` (window + GPU) | 50 ms | not the bottleneck |

Parse and macroexpand are trivial; the ~1 s is **eval** — creating ~1200 closures
and running module-level construction (199 `defcommand` registrations, 265
`keymap-bind` calls, face/mode/layer registries). No form-level cache helps; the
eval must be either **deferred** (async) or **skipped** (image cache).

The first-frame + core-editing closure is only ~**98 ms**; the rest is dominated
by feature modules that `commands`/`input`/`model` eagerly `(:use)` — `web`,
`lsp`, `git`, `gitdiff`, `bshell`, `compile`, `proctree` — none of which is
needed to render the first screen (keymaps dispatch their commands by *symbol*,
resolved late).

## Two fixes, two launches

| | Cold launch (first run / after any source edit) | Warm launch (sources unchanged) |
|---|---|---|
| **Async loading** | window usable in ~0.4 s, features fill in behind it | (same — still evals) |
| **Image cache** | still evals (cache miss) → relies on async for UX | hydrate everything in ~0.1 s |

Neither alone is instant on every launch: async still pays the ~1 s of CPU (just
off the critical path); the image cache is instant only when valid. Together they
cover both.

---

# Fix 1 — Async deferred loading (cold path, no Brood change)

## Feasibility — verified

Two crux points were confirmed with probes:

- **Late binding without `(:use)`.** A module can reference `feat/fn` with no
  `(:use feat)` and still load fine before `feat` exists; the reference resolves
  at *call* time. So the eager `(:use …)` can be dropped while keeping the
  `ns/fn` call sites.
- **Async load via shared globals.** Brood processes share one global table
  (`docs/shared-code.md`), so a **spawned process** that `(require 'feat)`
  populates definitions the main editor then calls (`caller/call-it => 42` right
  after the spawn). Background loading is real.

The direct calls to `lsp/…`, `web/…`, `git/…`, `bshell/…`, `compile/…`,
`proctree/…` all live **inside command bodies / event handlers** — they run only
when the feature is used, so at load they are just late-bound references.

## Approach (all editor-side)

1. **Drop the eager `(:use …)`** of the deferrable features in
   `commands`/`input`/`model` (`web lsp git gitdiff bshell compile proctree`),
   keeping the `ns/fn` references.
2. **`main` loads the core synchronously** (view, model, input, commands-core,
   keymaps, modes) → window is usable fast.
3. **Spawn a background loader** right after first paint: `(require 'git)`
   `(require 'lsp)` … — filling the shared globals within a few hundred ms.
4. **Guard the few early entry points** so a very fast user is safe: a feature
   command/handler does an idempotent `(require '…)` before its first call (cheap
   once loaded; blocks only that one first use).

## Expected win

~1.1 s → ~**0.4 s** perceived (editor immediately responsive), features arriving
~0.5 s later in the background — before a realistic `C-x g`.

## Caveats to handle

- **`model.blsp` → `gitdiff/gitdiff-annotate`** feeds the diff-hl gutter, which
  fires on the idle beat right after opening a file — early enough to race the
  background load. Guard: skip diff-hl until `gitdiff` is loaded (no change-bars
  for the first ~½ s is harmless).
- **`nest check`** (typecheck) may warn on `ns/fn` refs without `(:use)`.
  `nest run` doesn't typecheck, so runtime is unaffected — confirm, and if needed
  keep a lightweight forward declaration so `check` stays clean.
- Event-handler refs (`bshell/…`, `compile/…`, `web/…` in `input`) only fire
  *after* their subsystem is started by a command, so the module is already
  loaded by then — safe.

---

# Fix 2 — Image cache (warm path, a Brood feature)

Skip the ~1 s eval on a warm launch by caching the **evaluated global table** to
disk and re-hydrating it when the sources are unchanged.

## Why tractable (feasibility findings)

- The global table is `RwLock<SymbolMap<Value>>` — `Symbol(u32) → Value`
  (`crates/lisp/src/core/heap.rs`). `Value` is mostly heap **handles** plus
  immediates and `Native(NativeId)`.
- **A closure's body is `body: Vec<Value>` — AST-as-data, not bytecode**
  (`Closure`/`ClosureArm` in `core/value.rs`). The "compiled" function *is*
  serializable Brood data.
- `Native(NativeId)` is a builtin — **re-linkable by identity**, not serialized.
- Brood is **late-bound**: functions reference each other by *symbol* (global
  lookup), not heap pointer — so the graph rooted at globals is largely a DAG.
- Existing machinery: `Heap::snapshot_globals` / `GlobalsSnapshot` /
  `restore_globals` (hardened in `d22619d`); typed heap arenas;
  `crates/lisp/src/bundle.rs` (an id-based binary (de)serializer to model on);
  env frames `EnvFrame { bindings, parent: Option<EnvId> }`.

## Design

**Cache key.** Hash of (a) every loaded source file's content (project `src/` +
transitively-required `std`), (b) the brood build id (`BROOD_GIT_SHA` — pins
builtin/`NativeId` layout *and* the `Value` repr), (c) an image-format version.
Path mirrors `release.rs::runtime_cache_path`:
`$XDG_CACHE_HOME/brood/images/<project-id>/<hash>.img`. Any mismatch → cold path.

**What to serialize** (id-based graph from the globals roots):
immediates inline; `Str/Bytes/BigInt/Decimal` by value;
`Pair/Vector/Map/Range/SeqView` recurse (shared structure via ids);
`Fn/Macro` as `name` + `arms` (`params`, `optionals`, `rest`, `body: Vec<Value>`,
docstring) + `env` (`None`→global, `Some`→serialize the reachable `EnvFrame`
chain), **skip `passthrough`** (re-derive on load); `Native` by stable identity.
**Symbols by NAME**, re-interned on load into a remap. **Non-serializable guard:**
`Ref/Socket/Subprocess/Table`/live `Rope` reachable from globals → **abort
caching** (fall back to cold eval); a safety net, not an expected path.

**Load.** Verify version + key → re-intern symbols → relink natives → two-pass
alloc + patch refs → re-derive `passthrough` → install globals
(`restore_globals`-style, from deserialized data).

**Integration.** `std/tool/project.blsp::project-load-sources` (or the Rust run
bootstrap): read-on-warm (hydrate, skip eval), write-on-cold *off the critical
path*. Flags `--no-image-cache` / `BROOD_NO_IMAGE_CACHE`.

## Stages

0. **Feasibility spike (GO/NO-GO):** round-trip the editor's globals into a fresh
   runtime; assert sampled functions return identical results; measure warm-load
   vs the ~1 s cold eval. Stop here if closure-env / native relink is intractable.
1. **Serializer** — graph walk; all `Value` kinds; symbol-by-name; native
   identity; env frames; non-serializable guard → abort.
2. **Deserializer** — two-pass alloc + patch; symbol remap; native relink;
   `passthrough` re-derive; install globals.
3. **Keying + invalidation** — source + build + format-version hash; cold rewrite
   off the critical path.
4. **Integration + flags** — hook the load path; corrupt/partial image → cold
   fallback.
5. **Validation** — full brood + brood-edit suites pass from image; a diff test
   that hydrate ≡ eval; warm-startup target **< 150 ms**; stale/corrupt → fallback.

## Invariant

Hydrate-from-image MUST be behaviorally identical to source eval. Any anomaly —
unknown `Value` kind, missing native, hash mismatch, truncation — is a **silent
fallback to cold eval**, never a crash or a wrong result. The image is a *cache*:
deletable anytime, never authoritative.

---

# How they reinforce (best of both)

1. **The async background loader *is* the image writer.** After the background
   process finishes loading the features, the global table is complete — exactly
   the moment to serialize the image, off the critical path. One mechanism, both
   payoffs.
2. **On a warm start the image makes async a no-op.** Hydrating the whole table in
   ~0.1 s means core + features are already present; async silently becomes the
   **cache-miss fallback** (first run after an edit) — never wasted.
3. **Optional tiered image** (strongest form): cache the **core** modules as their
   own small image → hydrate the usable editor in ~50 ms, *and* keep hydrating /
   loading features in the background. Instant-to-usable **and** complete.

# Combined roadmap

1. **Ship async deferred loading now** — ~1.1 s → ~0.4 s felt, no Brood change,
   no risk, and the right architecture permanently.
2. **Layer the image cache later** (when the file-loading work lands) — warm
   launches → ~0.1 s. The async loader becomes the image writer + cold-path
   fallback.
3. Keep the `Value`/`Closure` layout stable, or **bump the image-format version**
   so the two never fight.

# Risks & fallbacks

- Module-level closures capturing non-trivial `let` locals → serialize env frames;
  if an env reaches a non-serializable value, abort → cold path.
- `Value`/native layout drift across builds → key includes `BROOD_GIT_SHA` +
  format version.
- Mutable module-level state (`Table`/atom) → guard aborts caching if present.
- **The fallback is always cold eval**, so both fixes can only fail to *speed up*
  — never change behavior or break a build.
