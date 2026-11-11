# Packages — an extension ecosystem (design note)

**Status:** design-of-record, partly built. The package MANAGER exists (`src/packages.blsp`,
`M-x package-list`): it installs, updates and removes hive packages that `:enhances bedit`
into `~/.config/bedit/packages` at runtime and loads them at startup, and a package may
declare its own settings (`:bedit/settings`) and themes. The registration surfaces this note
names as `bind-key`, `add-hook` and `defsetting` are, as built, init.blsp's `:keys` /
`:mode-keys` and std's `settings/define`; named hooks and the `(package …)` form are not
built ([`configurability.md`](configurability.md) has what is). Revised 2026-08-02, when the substrate turned out to be
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
- **A hosted registry — hive.** `project/*config-registry*` (default `https://brood.fly.dev`,
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
| `Package-Requires: ((emacs "29.1"))` | `:enhances {bedit ">= 0.1"}` (the marker *and* the version check) |
| `defcustom` / `define-key` / `add-hook` / `auto-mode-alist` | `settings/define` (`:bedit/settings`) / init.blsp's `:keys` and `:mode-keys` / `add-hook` (not built) / `register-file-type` registries ([`configurability.md`](configurability.md)) |
| `use-package` | a declarative `(package …)` form in `init.blsp` — **data, not code** |
| autoloads | the `M-x` registry + late-bound command symbols |
| `M-x list-packages`, `C-h P` | `M-x package-list` (a `*Packages*` buffer), `C-h P` describe-package (`help/cmd-describe-package`: installed or not, the version against the hive's newest, what it enhances, the themes it contributes, the init.blsp settings its sources declare; RET on a `*Packages*` row) |

So most of "load packages like Emacs" **already exists** — it just isn't pointed at the
editor yet.

## 1. Marking editor packages — without teaching the toolchain about bedit

hive is *Brood's* registry, not bedit's: it holds web apps, a Postgres store, an S3
client. An editor package has to be identifiable, for two different reasons:

- **Discovery.** `M-x package-list` must show the packages written for *this editor*, not
  every package published for the language. Emacs never had this, and MELPA's flat
  namespace is exactly why `list-packages` opens on thousands of unrelated rows.
- **Safety.** An editor package calls editor registration functions and is loaded *into
  the editor's own image*. "Is this meant to be loaded into bedit?" is a question the
  installer should be able to answer before it loads anything.

### The hard constraint

> **Nothing in `brood`, `nest` or `hive` may know that bedit exists.** The toolchain is
> the language's, not one application's. Whatever marks an editor package must be a
> *generic* mechanism whose vocabulary is supplied by package authors — so a Hatch web
> app, a `nest` format plugin, or an app nobody has written yet gets the same
> affordance without a line of code changing anywhere.

That rules out an app-named manifest key (`:bedit-version`), an app-specific `kind`
seq, and any `if name == "bedit"` anywhere in the tooling.

### The mechanism: one generic key, `:enhances`

A package declares **which application it adds functionality to, and which versions of it
that requires**:

```clojure
;; a published editor package's project.blsp
(project
  :name "bedit-zig"
  :version "0.1.0"
  :description "Zig syntax highlighting + structural nav for bedit."
  :repository "https://github.com/…/bedit-zig"
  :enhances {bedit ">= 0.1"}          ; ← the whole marker
  :dependencies [])
```

```clojure
;; …and the same mechanism, no new code, for other ecosystems
:enhances {hatch ">= 1.0"}            ; a web-framework plugin
:enhances {nest ">= 0.4"}             ; a `nest` subcommand / format plugin
:enhances {bedit ">= 0.1", waggle ">= 0.2"}   ; useful inside either application
;; absent entirely = an ordinary library (every package published so far)
```

The name is **Debian's `Enhances:`** field, which means exactly this — *"this package adds
functionality to that one"* — and comes from packaging, the domain this actually belongs
to. Two names were tried and rejected first: **`:extends`** carries OO inheritance
baggage, and a package does not subclass an editor; **`:host` / `:hosts`** collides with
what "host" already means across this project — a *machine* (`bedit --attach ed@HOST:PORT`,
"the host's own window"). `:enhances` reads as a plain sentence with no gloss needed:
*bedit-zig enhances bedit >= 0.1*.

**The names in it are data.** `brood`/`nest`/`hive` parse the map, carry it, store it and
filter on it; they never enumerate its keys. `bedit` is a symbol a package author typed,
exactly like `hatch` or anything else. The vocabulary is open by construction, not by a
promise to extend a list later.

**Discovery** becomes `GET /api/v1/packages?q=&enhances=bedit` — generic on both sides;
`nest search --enhances hatch` works the same day it works for the editor.

**Compatibility** is checked by the *enhanced application*, at load time, against its own
version — not by the resolver. bedit reads its own entry out of the package's manifest and
declines a package that needs a newer editor, with a message. Deliberately: ADR-037's
resolver takes **exact versions and has no semver solver**, and this must not smuggle one
in. A *predicate* ("does 0.1.0 satisfy `>= 0.1`?") is not a solver — it decides nothing
about which version to fetch — and it belongs in `std` because **hive already hand-rolled
it** (`version/compare` / `version/core` in `src/registry.blsp`) and bedit would be the
third to write it.

### Why not the alternatives

| Alternative | Why not |
|---|---|
| **`:extends {bedit …}`** | Reads as OO inheritance (`class Foo extends Bar`), which is the wrong mental model: a package is *loaded beside* an application and calls its registries, it does not specialise a type. |
| **`:host` / `:hosts`** | "Host" already means a *machine* in this project — `--attach ed@HOST:PORT`, the daemon's host window. Reusing it for "application I plug into" makes two unrelated things one word. |
| A `bedit-*` **name convention** | Can't be queried (the editor would pull the whole index and filter client-side), can't be enforced (a package that forgets the prefix is invisible), and carries no version compatibility. Still a good *naming* habit — just not the mechanism. |
| A **`:kind` seq** (`:bedit`, `:hatch-plugin`, …) | One concept too many: what a package enhances already implies what kind it is. And an seq invites a blessed list in the toolchain, which is the thing being avoided. |
| A **dependency on `bedit`** | The application is already in the image. It would drag the whole editor into `_deps/` for a 40-line mode, and needs a version *range*, which the resolver deliberately doesn't do. |
| A free-form **`:meta {…}`** map | Maximally open, but every application invents its own key, so the registry can't index anything consistently and discovery dies. One named field with author-supplied values is the right altitude. |

Emacs marks packages the same way, notably: `Package-Requires: ((emacs "29.1"))` puts the
application in a requirements list rather than in a category field. `:enhances` is that
idea, kept separate from `:dependencies` because what it names is *present*, not
*fetched*.

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

1. **`:enhances` end to end (small, three layers — and generic at every one).**
   - *Brood* — `project-apply` parses `:enhances` into `project/*enhances*` (a
     name → constraint map, beside the existing `project/*dependencies*`);
     `registry--publish-payload` includes it; `nest search` grows `--enhances <app>`.
     No application name appears anywhere in the implementation.
   - *hive* — store it the way `dependencies` already is (a JSON **text** column on the
     release, since the param encoder is scalar-only), plus a denormalized application list on
     `packages` for listing filters — the same denormalization `description` /
     `latest_version` already get from the newest release. Then
     `GET /api/v1/packages?q=&enhances=<app>`, and a web-UI facet whose values come from
     the data rather than a list in the code.
   - *`std`, promoted not invented* — `version/satisfies?`, over the `version/compare` /
     `version/core` pair that **already exists in hive** (`src/registry.blsp`) because
     `std` lacks it. Two consumers today (hive deciding which release is latest, an application
     deciding whether a package is compatible with it), and any application hosting
     plugins is the third. **Explicitly not a resolver change:** the predicate answers a
     yes/no question about two versions and never chooses one, so ADR-037's
     exact-version, no-solver invariant stands untouched.
   - Both sides are additive: a package published without `:enhances` is an ordinary
     library, and today's hive already ignores unknown metadata fields (its publish
     handler reads named keys off the envelope), so a new client is safe against the
     registry as deployed.
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
   (`?enhances=bedit` — the editor names itself; the registry doesn't) joined against the
   config nest's manifest + lock, so "installed", "upgrade" and "available" fall out of
   one request and one file read.
3. **`M-x package-install`, live.** Completion over hive's search results through **plume**
   (our Vertico) with marginalia — downloads and description in the annotation column,
   which `src/completion.blsp` already renders. Then: add the dep to the config nest's
   manifest, `ensure-deps`, append to `*load-path*`, `require`. Because the registries are
   **late-bound and the image is live, a freshly installed package's commands, modes and
   keybindings take effect with no restart** — which genuinely beats Emacs's
   restart-or-autoload dance, and is a direct payoff of the late-bound design.
4. **All of it off the loop.** Registry HTTP, tarball download and extraction take
   *seconds*, so they run in a worker. **Done (2026-11-04)** for the runtime package manager
   (`src/packages.blsp`): the list fetch, an install and an update are a `std/task` in the
   model's `:package-job` slot — one at a time, C-g cancels it, C-x C-c asks while it runs —
   and the `*Packages*` status line says what is running and how the last one ended, with
   the registry's REASON when it failed (brood ADR-559 made the registry calls answer a
   failure carrying it instead of nil or a bare raise). An install lands in a staging dir and
   is moved into place only once it verified and enhances this bedit, so a failed, refused
   or cancelled install keeps the copy that was there. `M-x package-install` and `C-h P` fetch
   the list themselves when it has never been fetched: the prompt opens at once saying so,
   and its candidates arrive with the answer. An update reloads the plugin's files in load
   order (brood's `reflect/source-load-order`), so a changed macro reaches its callers on the
   one reload. **An update is shown before it is applied (2026-11-10, Emacs bug #74604's
   wish):** `u` in `*Packages*` and `M-x package-update` stage the new version off the loop and
   open `*Package Diff: NAME*` — `NAME old → new`, the package's own `CHANGELOG.md` (or `NEWS`)
   entries for the versions after the installed one up to the new one, then every file the
   new version adds, deletes or changes as hunk sections painted as every diff in bedit is
   (`src/package-review.blsp` over `vcsproc/vcs-hunk-sections` and `diffpaint`; TAB folds).
   `C-c C-c` moves the staged copy into place and applies it live; `C-c C-k` or `q` deletes
   the staged copy and keeps the installed one. Until `C-c C-c` the installed copy is never
   touched, so a failed fetch, a refusal, a C-g, a drop or a review left open all keep it. An
   open review's staging dir is noted in the runtime's `:packages/reviews` registry so the
   next install's clean-up leaves it alone; killing the buffer leaves the copy until the
   package is reviewed again or a later session's first install clears it.
   `:package-review-updates false` in init.blsp applies an update as soon as it arrives, as
   before. **Updating every package (2026-11-10):** `M-x package-update-all` (`U` in
   `*Packages*`, where Emacs's package menu marks the upgrades with `U` and runs them with `x` —
   here the review is the confirmation) is ONE job off the loop that stages every installed
   package with something newer, each in its own staging dir beside the others, and shows ONE
   `*Package Diff*`: a title naming any package whose update could not be staged (and why),
   then a folded section per package (`NAME old → new (N files changed)`; TAB opens its
   changelog and file diffs). `C-c C-c` moves them all into place and applies each live, a
   package that fails to move said while the rest go on; `C-c C-k` or `q` drops them all. A
   package that is current, or a local one the registry does not publish, is left out; C-g
   stops the job, leaving every installed copy as it was. With `:package-review-updates
   false` the job installs them all and each is applied when it lands. A network fetch on the `ui-run` loop
   would freeze the editor, which is precisely the class of thing the actor work removed.
5. **`M-x package-upgrade` / `package-delete` / the lockfile.** `project.lock.blsp` in the
   config dir is a **reproducible editor config**: version + sha256 per package, so the
   same editor comes up on another machine — what Emacs users needed straight.el / elpaca
   to get. `package-upgrade` re-resolves one dep; `package-delete` drops it from the
   manifest and `_deps/` (effective next start, per Part 1.4).
6. **Trust, stated plainly.** A package is arbitrary Brood code in the editor's image;
   `:enhances` is author-declared metadata, **not a sandbox**. The policy: explicit installs only
   (nothing auto-installs), immutable releases pinned by checksum in the lock, and `C-h P`
   shows what the hive says of a package before you install it, and once it is installed the
   settings its sources declare and the themes it contributes (its sources are read, not run,
   for the settings). The real answer is the one this
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

## What removing or updating a package takes back (built)

Removing a package (`packages/remove!`, `d` in *Packages*) and updating one
(`packages/update-plugin!`) go through ONE retirement, `package-ledger/retire-package`, and then
put the open buffers right. Like Emacs's `unload-feature`, it leaves the editor as it was
before the package loaded:

- **bedit's registry rows** — idle jobs, task replies, event / down / timer handlers, exit
  queries, post-steps, mode line chips, M-x commands, keymap profiles, modes, file types,
  interpreters, themes, chrome faces, settings — are CLAIMED for the file that registered them
  (`src/ownership.blsp`): at load by `reflect/current-file`, at run time by the namespace of
  the command or hook that ran (`with-symbol-claimant`). Every row a package claimed goes; a
  core row it replaced comes back.
- **std registries it wrote directly** (`editor/layers`' tables, faces, abilities, a
  `registry/put!` of its own) are found with Brood's `registry/written-by` (ADR-582): the
  kernel credits each write a load made to its module, or to the FILE for a file with no
  `defmodule`, so the package's writers are its module symbols and its files' absolute paths
  (`package-ledger/package-writers`). A list member is taken back (`registry/retract`). A map entry
  keeps a per-entry stack, `:packages/std-layers`: what it held before any package, then each
  package's write in load order. Retiring the package whose write is live gives the entry to
  the layer below it — another package's write, credited to that package again — or to what
  it held before (`registry/restore`), or takes it back; retiring a lower one leaves the live
  write alone. Both are conditional on the entry still being the package's, checked by the
  kernel under the registry lock, so an entry something else wrote since is left as it is.
- **any row still naming the package** — a hook symbol in its namespace, a function defined
  there — is dropped, as a backstop.
- **core functions it redefined** are restored through a per-function stack, so two packages
  patching the same function come off in either order.
- **globals it first defined** are removed (`reflect/undef`); a core name is never undefined.
- **open buffers in a mode it took away** are seeded again in the mode their type has now
  (an update's, or the core mode the package replaced), else in fundamental mode, said in
  *Messages*.

**The one limit:** a hook a package registers as a bare CLOSURE from a timer or a process it
spawned has nothing to attribute it by — no load, no command or hook symbol to take the
claimant from, no symbol in its value to find it by — so it outlives the package. The kernel
cannot say which package's code is running in such a process; Brood tracks it as KI-356
(`../brood/docs/known-issues.md`). Register hooks as symbols (`'pkg/hook`), as every bedit
registry asks, and this does not arise.

## A plugin's library dependencies (built, partly)

A plugin with code may use a library that is not bedit's: bedit-agent uses `agentkit`, which
any Brood program driving a coding agent can use and which knows nothing of bedit. The plugin
names it under `:dependencies`; a library INSTALLED BESIDE it in the package dir goes on the
load path before the plugin loads (`packages/installed-dependencies`). A library needs no
`:enhances`, and startup does not report it as a package it failed to load. Not built yet:
installing a plugin does not fetch its dependencies from the hive, so the library is installed
by hand beside it.

## A staged path

1. **Stage 1 — the marker and a live install (no language change).** `:enhances` end to end
   (Part 1.1) + `load-nest` (1.2) + config-dir-as-nest startup (2.1) + `M-x
   package-install` / `package-list`, async (2.2–2.4), restricted to curated packages.
   That already gives a live, restart-free, Emacs-like flow over machinery that exists
   today — and publishing our first `bedit-*` package to hive is the end-to-end proof.
   **The test that Stage 1 stayed honest:** `grep -ri bedit ../brood ../hive` finds
   nothing outside prose. If it does, the mechanism leaked into the toolchain and the
   next ecosystem will have to leak too.
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

The headline: we point the package manager and registry Brood already has at the editor;
a package says what it enhances (`:enhances {bedit ">= 0.1"}`) in a field whose vocabulary
is the author's, so the toolchain gains *plugin ecosystems* as a concept and never learns
this editor's name; the user's config dir is a nest; and packages register through the
same late-bound registries the core uses — so "core" and "package" are the same
mechanism, which is the property that made Emacs's ecosystem possible. Whatever gets
written next on Brood gets the ecosystem for free, which is the only version of this
worth building.
