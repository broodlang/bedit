# Packages — an extension ecosystem (design note)

**Status:** design-of-record. Mostly **not built yet**; the editor today loads only its
own bundled modules at startup. Revised 2026-08-02, when the substrate turned out to be
further along than this note assumed: **[hive](../../hive) — Brood's package registry —
is live and `nest` already speaks it.**

The question that started this: *how do we load editor packages to enhance or change the
editor — almost like Emacs?* The answer is unusually clean because of the prime
directive: **Brood already has a package manager and a registry**, and the editor's
late-bound, registry-driven design is already shaped to reuse them. We don't invent a
package system — we point the one Brood has at the editor, and mark the packages that
are ours.

It builds on [`configurability.md`](configurability.md): a package "hooks into" the
editor by calling the **same registration functions** core uses (`defcommand`,
`register-type-layers`, `bind-key`, `add-hook`, `defsetting`, `register-theme`, …). The
registries *are* the plugin API — the Emacs property that everything uses the same
primitives as the core.

## What already exists (checked, not assumed)

Brood/`nest` ships the hard parts (ADR-037, ADR-147 in the brood repo):

- **Manifests with `:dependencies`** — `:path`, `:git`, `:tarball`, and **`:registry`**
  deps. A registry dep is spelled `[name :version "0.2.1"]`; resolution is an **exact
  version match, no semver solver** (ADR-037's direct-refs-only invariant).
- **A hosted registry — hive.** `*config-registry*` (default `https://brood.fly.dev`,
  set per-user in `~/.config/brood/config.blsp`) is an HTTP base URL. `nest search` GETs
  `/api/v1/packages?q=`; resolving a registry dep GETs the release metadata, downloads
  the immutable tarball, **verifies its sha256**, and extracts it into `_deps/<name>/`.
  `nest publish` builds a source tarball and POSTs it with a per-user Bearer token;
  releases are immutable, so a re-publish is refused.
- **Transitive resolution + a committed lockfile** — `project.lock.blsp` records the
  version *and* the checksum (the integrity pin), `_deps/` is the cache, and a current
  cache resolves **network-free**.
- **CLI** — `nest add` / `fetch` / `update` / `tree` / `remove` / `search` / `publish`.
- Critically: **`*load-path*` is mutable and consulted at runtime**, and `(require 'mod)`
  loads a module into the *running* image once its dir is on the path.

And the editor's modules already wire themselves in purely by calling registration
functions at load time — `defcommand`, `register-type-layers` / `register-file-type`,
`register-profile`, `register-log-route`, the mode-service facets.

Put those two facts together and the design falls out:

> **An editor package is a Brood nest, published to hive like any other.** The user's
> `~/.config/bedit/` directory *is itself a nest*; installed packages are its
> `:dependencies`; hive is the archive and `nest`'s resolver is the installer. A package
> hooks into the editor by calling the same registration functions core uses.

## Concept mapping (Emacs → bedit)

| Emacs | bedit |
|---|---|
| `.el` file with `(provide 'foo)` | a `defmodule` in a Brood nest |
| `load-path` | `*load-path*` (already runtime-mutable) |
| `require` / `load` | `require` / `load` (already exist) |
| MELPA / GNU ELPA | **hive** (`https://brood.fly.dev`), one registry, sha256-pinned |
| `~/.emacs.d/elpa/` | the config nest's `_deps/` + `project.lock.blsp` |
| `package-refresh-contents` | nothing to refresh — hive is queried live |
| `package-install` | add the dep + resolve + `require`, **in the running image** |
| `Package-Requires: ((emacs "29.1"))` | `:bedit-version ">= 0.3"` (checked by the editor) |
| `defcustom` / `define-key` / `add-hook` / `auto-mode-alist` | the settings / `bind-key` / `add-hook` / `register-file-type` registries ([`configurability.md`](configurability.md)) |
| `use-package` | a declarative `(package …)` form in `init.blsp` — **data, not code** |
| autoloads | the `M-x` registry + late-bound command symbols |
| `M-x list-packages`, `C-h P` | `M-x package-list` (a `*Packages*` buffer), `C-h P` describe-package |

So most of "load packages like Emacs" **already exists** — it just isn't pointed at the
editor yet.

## 1. Marking editor packages in hive

hive is *Brood's* registry, not bedit's: it holds web apps, a Postgres store, an S3
client. An editor package has to be identifiable, for two different reasons:

- **Discovery.** `M-x package-list` must show the packages that extend *this editor*, not
  every package published for the language. Emacs never had this, and MELPA's flat
  namespace is exactly why `list-packages` opens on thousands of unrelated rows.
- **Safety.** An editor package calls editor registration functions and is loaded *into
  the editor's own image*. "Is this meant to be loaded into bedit?" is a question the
  installer should be able to answer before it loads anything.

**The marker is one manifest key: `:kind`.**

```clojure
;; a published editor package's project.blsp
(project
  :name "bedit-zig"
  :version "0.1.0"
  :description "Zig syntax highlighting + structural nav for bedit."
  :repository "https://github.com/…/bedit-zig"
  :kind :bedit                      ; ← what this package extends
  :bedit-version ">= 0.3"           ; ← the host it needs (editor-checked, see below)
  :dependencies [])
```

`:kind` defaults to `:library` (every existing package keeps working unchanged) and is a
small open vocabulary — `:bedit`, later `:hatch-plugin`, `:nest-plugin`. It rides the
existing metadata path: `project.blsp` → `nest publish`'s JSON envelope → a hive column →
the search API's filter. Three small changes, one per layer (see the gaps below). There
is precedent for a package declaring what it extends: hive's own manifest carries
`:format-plugins [hatch]`.

**Why a field and not a `bedit-*` name convention.** A convention can't be queried, so
`M-x package-list` would have to pull the whole index and filter client-side; it can't be
enforced, so a package that forgets the prefix is invisible; and it carries no version
compatibility. A prefix is still a good *naming* habit (`bedit-zig` reads well) — it just
isn't the mechanism.

**Why not a dependency on `bedit` instead.** The host is already in the image; a package
does not need the editor's *source* as a dep, and making it one would drag the whole
editor into `_deps/` for a 40-line mode. `:bedit-version` states the requirement without
a resolvable dep, and it is checked by **the editor at load time** rather than by the
resolver — deliberately, so ADR-037's exact-version invariant (no semver solver) stays
untouched. A too-old editor declines the package with a message instead of loading
something that will misbehave.

## 2. What a package author writes (the payoff)

Because a package calls the same registration functions core does, there is *no plugin
API to learn*. A whole syntax-highlighter package:

```clojure
(defmodule bedit-zig
  "Zig syntax highlighting + structural nav for bedit."
  (:use editor/layers) (:use editor/treesit))

(defn zig-fontify (text) (treesit/fontify text :zig bedit-zig/zig-face-of))

(def zig-mode-layer
  {:name 'zig :parser :tree-sitter :ts-lang :zig
   :file-pattern "\\.zig$" :fontify 'bedit-zig/zig-fontify :comment-syntax "// "})

(modes/register-prog-mode 'bedit-zig/zig-mode-layer :zig)   ; ← the same call core makes
(provide 'bedit-zig)
```

`nest publish` from that directory puts it on hive. That's the entire package.

## 3. The gaps — prime-directive split

### Part 1 — Brood / `std` / hive (the language + registry gaps)

1. **`:kind` end to end (small, three layers).**
   - *Brood* — `project-apply` reads `:kind` (and carries `:bedit-version` for the editor
     to read); `registry--publish-payload` includes it; `nest search` grows `--kind <k>`.
   - *hive* — `packages.kind text not null default 'library'`, written from the publish
     envelope exactly as `description` / `latest_version` already are (package-level
     metadata denormalized from the newest release; releases stay immutable),
     `GET /api/v1/packages?q=&kind=`, and a facet in the web UI.
   - Both sides are additive: an old client publishing without `:kind` gets `library`, and
     an old registry ignores the field.
2. **`load-nest` — resolve and load a nest's deps into the *running* image (small).**
   Everything today is CLI-shaped: `nest fetch`, then `nest run`. Expose a callable entry
   in `std/tool/package.blsp` — `(load-nest <dir>)` — that runs the existing `ensure-deps`
   on a manifest, appends the resolved source dirs to `*load-path*`, `require`s the entry
   modules, and **returns what it added** (so the caller can report it and, on failure,
   unwind the path). Every piece exists; this is packaging them as a library entry rather
   than a CLI path.
3. **Package-rooted namespaces (ADR-070) — the gate for third-party.** Module names must
   be globally unique across a project and all its deps (the global table is flat), so two
   packages that both define a `theme` or a `git` module **collide**. This is exactly the
   gap the prime directive predicted the editor would surface — and it is **in flight**:
   the prelude registries (`*package-module-files*`, `*package-modules-of*`) and the
   heap-side rooting (`root_module_name`, so a dep's modules load as `foo/b`) landed
   2026-08-02; the package-manager side that populates them is next. Until it closes,
   *curated* packages (ours, with names we coordinate) are safe and an *open* third-party
   ecosystem is not.
4. **A teardown seam for live disable (optional).** There is no `unrequire`, so *disable*
   is best modeled at the registry level — drop the package's layers, binds and hooks —
   not by unloading code. `std/editor/layers` already has the `:on-close` / `:deactivate`
   cleanup seam to build on. Not blocking: `package-delete` + restart is honest in the
   meantime, and is what Emacs does anyway.
5. **(Nice-to-have) a tar primitive.** `nest publish` shells out to `run-process "tar"`.
   Fine on a dev box; a `tar-create` / `tar-extract` builtin would let publish and install
   work where `tar` isn't on PATH — which a bundled editor installing a package for a
   user cannot assume.

### Part 2 — the editor

Built on Part 1 and on the config registries from
[`configurability.md`](configurability.md).

1. **Config dir as a nest + startup loader.** `~/.config/bedit/` gets a `project.blsp`
   (`:name "bedit-config"`, `:dependencies` = the user's packages) beside `init.blsp`. At
   startup `main` calls `load-nest` on it → the packages' modules load and register live →
   then `init.blsp` is applied on top. **Deferred, like the rest of startup:** package
   loading joins the async deferred-load path (`a1647d8`), so a slow package can't hold the
   first frame. Bundled modes stay first-party; migrating one to a `:path` dep later is the
   cheapest way to dogfood the seam.
2. **The `*Packages*` buffer (`M-x package-list`).** A read-only generated buffer with its
   own mode layer — the exact pattern dired / occur / `*git-status*` / the process list
   already use, so it costs a mode registration and a render function, not a new
   subsystem:

   ```
    Status     Package        Version  Latest  ↓Downloads  Description
    installed  bedit-zig      0.1.0    0.1.0        1 204  Zig syntax + structural nav
    upgrade    bedit-magit    0.4.0    0.5.1        8 810  Git porcelain, magit-style
    available  bedit-vertico           0.2.0        3 097  Minibuffer completion UI
   ```

   Single-key actions in Emacs's `list-packages` vocabulary: `i` mark install, `d` mark
   delete, `u` unmark, `U` mark all upgrades, `x` execute the marks, `RET` describe
   (`C-h P` from anywhere), `g` refresh, `/` filter, `q` quit. The rows are one hive query
   (`?kind=bedit`) joined against the config nest's manifest + lock — so "installed",
   "upgrade" and "available" fall out of one request and one file read.
3. **`M-x package-install`, live.** Completion over hive's search results through **plume**
   (our Vertico) with marginalia — downloads and description in the annotation column,
   which `src/completion.blsp` already renders. Then: add the dep to the config nest's
   manifest, `ensure-deps`, append to `*load-path*`, `require`. Because the registries are
   **late-bound and the image is live, a freshly installed package's commands, modes and
   keybindings take effect with no restart** — which genuinely beats Emacs's
   restart-or-autoload dance, and is a direct payoff of the late-bound design.
4. **All of it off the loop.** Registry HTTP, tarball download and extraction take
   *seconds*, so they run in a worker that streams progress into the buffer —
   `src/procstream.blsp` is the shared streaming-subprocess worker the test and app runners
   already ride, and this is the same shape (a `:packages` handler). A network fetch on the
   `ui-run` loop would freeze the editor, which is precisely the class of thing the actor
   work removed.
5. **`M-x package-upgrade` / `package-delete` / the lockfile.** `project.lock.blsp` in the
   config dir is a **reproducible editor config**: version + sha256 per package, so the
   same editor comes up on another machine — what Emacs users needed straight.el / elpaca
   to get. `package-upgrade` re-resolves one dep; `package-delete` drops it from the
   manifest and `_deps/` (effective next start, per Part 1.4).
6. **Trust, stated plainly.** A package is arbitrary Brood code in the editor's image;
   `:kind` is discovery metadata, **not a sandbox**. The policy: explicit installs only
   (nothing auto-installs), immutable releases pinned by checksum in the lock, and `C-h P`
   shows what a package registers before you install it. The real answer is the one this
   editor is already built on — **a package could run in its own process**, the way every
   buffer already does (`src/hosted.blsp`) — and that is the direction to take if untrusted
   packages ever matter. Emacs never solved this; we at least know where our answer comes
   from.
7. **`use-package`-style declarative integration.** Once 1–6 plus the config registries
   exist, `init.blsp` ties a package to its configuration in one data form:

   ```clojure
   (package bedit-magit
     :install  [:version "0.5.1"]              ; or [:git "…" :ref "v1"] / [:path "~/src/…"]
     :autoload [magit/cmd-git-status]          ; don't load until one of these runs
     :bind     {"C-x g" magit/cmd-git-status}
     :hook     {:prog-mode magit/diff-hl-on}
     :setting  {:magit/auto-revert true}
     :mode     {"\\.diff$" magit/diff-mode})
   ```

   | `use-package` | here | note |
   |---|---|---|
   | `:ensure t` | `:install [:version "…"]` | the dep spec *is* the ensure |
   | `:bind`, `:hook`, `:mode` | same names | straight into the `bind-key` / `add-hook` / `register-file-type` registries |
   | `:custom` | `:setting` | the `defsetting` registry ([`configurability.md`](configurability.md)) |
   | `:defer` / `:commands` | `:autoload` | see 8 |
   | `:after` | `:after` | load ordering only |
   | `:init` / `:config` **(bodies)** | **not supported — deliberately** | `init.blsp` is read as *data*, never eval'd (ADR-065). User *code* lives in a small local package the config nest depends on by `:path`. |

   That last row is the one real divergence from `use-package`, and it is a feature: the
   config stays inspectable, diffable and portable, and "my init file is a program that
   sometimes fails to boot" is not a state this editor can get into. The escape hatch
   (`:path` to your own package) is a directory, not a language feature.
8. **`autoload`, for startup cost.** The `M-x` registry already maps a name → a command;
   generalize an entry to "require module X, then dispatch". `(autoload 'pkg/cmd-foo
   "bedit-foo")` registers the name without loading the module; first use loads it. Late
   binding makes this a few lines, and it keeps startup flat as the package count grows —
   which matters more here than in Emacs, since module load is already the dominant
   startup cost (`ROADMAP.md` §H).

## A staged path

1. **Stage 1 — the marker and a live install (no language change).** `:kind` end to end
   (Part 1.1) + `load-nest` (1.2) + config-dir-as-nest startup (2.1) + `M-x
   package-install` / `package-list`, async (2.2–2.4), restricted to curated packages.
   That already gives a live, restart-free, Emacs-like flow over machinery that exists
   today — and publishing our first `bedit-*` package to hive is the end-to-end proof.
2. **Stage 2 — the declarative surface.** `(package …)` (2.7) and `autoload` (2.8), once
   the settings / `bind-key` / `add-hook` registries land
   ([`configurability.md`](configurability.md)) — they are what those keys write into.
3. **Stage 3 — open the doors.** ADR-070 package-rooted namespaces (1.3, in flight) is
   what makes *untrusted third-party* packages safe from name collisions; the
   package-as-process idea (2.6) is what would make them safe from each other.

## When to actually do this

After the customization surface ([`configurability.md`](configurability.md)) — a package
configures the editor *through* those registries, so they come first, and Stage 2's keys
are literally their public face. Stage 1 is attractive before that even so: it is thin
glue over a registry, a resolver and a lockfile that already work, and it proves the
"config dir is a nest, packages load live" model end to end.

The headline: we point the package manager and registry Brood already has at the editor,
mark editor packages with one manifest key so they are discoverable and checkable, treat
the user's config dir as a nest, and let packages register through the same late-bound
registries the core uses — so "core" and "package" are the same mechanism, which is the
property that made Emacs's ecosystem possible.
