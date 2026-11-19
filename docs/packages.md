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
API to learn*. A whole language package is one module written exactly as bedit's own
languages are — `(:use languages)` and one spec ("A language package" below has the template):

```clojure
(defmodule bedit-lang-zig
  "Zig for bedit."
  (:use languages))

(deflanguage zig
  {:lang :zig :pattern "\\.zig$" :faces zig-face-table :indent zig-indent-spec
   :grammar {:url "https://github.com/tree-sitter-grammars/tree-sitter-zig" :revision "b670c8d…"}
   :comment "// "})

(defn bedit-plugin () {})
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
   wish):** `i` on an installed package in `*Packages*`, `M-x package-install` of an installed
   name and `M-x package-update` stage the new version off the loop — newer only, never a
   downgrade — with the new libraries it needs staged beside it (not installed), and
   open `*Package Diff: NAME*` — `NAME old → new`, the package's own `CHANGELOG.md` (or `NEWS`)
   entries for the versions after the installed one up to the new one, then every file the
   new version adds, deletes or changes as hunk sections painted as every diff in bedit is
   (`src/packages/review.blsp` over `diffs/vcs-hunk-sections` and `diffs`; TAB folds).
   `C-c C-c` moves the staged copies into place (the old copy renamed aside first, so a failed
   move puts it back) and applies it live — after a y/n naming the change when its signing key
   changed, which holds even an unreviewed update for review; `C-c C-k` or `q` deletes
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

Removing a package (`packages/remove!`, after a y/n — `M-x package-remove`, or `d` to mark and
`x` to delete in *Packages*) and updating one
(`packages/update-plugin!`) go through ONE retirement, `packages/ledger/retire-package`, and then
put the open buffers right. Like Emacs's `unload-feature`, it leaves the editor as it was
before the package loaded:

- **bedit's registry rows** — idle jobs, task replies, event / down / timer handlers, exit
  queries, post-steps, mode line chips, M-x commands, key bindings, keymap profiles, modes, file types,
  interpreters, themes, chrome faces, settings — are CLAIMED for the file that registered them
  (`src/ownership.blsp`): at load by `reflect/current-file`, at run time by the namespace of
  the command or hook that ran (`with-symbol-claimant`). Every row a package claimed goes; a
  core row it replaced comes back.
- **std registries it wrote directly** (`editor/layers`' tables, faces, abilities, a
  `registry/put` of its own) are found with Brood's `registry/written-by` (ADR-582): the
  kernel credits each write a load made to its module, or to the FILE for a file with no
  `defmodule`, so the package's writers are its module symbols and its files' absolute paths
  (`packages/ledger/package-writers`). A list member is taken back (`registry/retract`). A map entry
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

## A plugin's `bedit-plugin` map (built)

A plugin's entry, `(defn bedit-plugin () {...})` in its main module, answers what bedit asks
for BY NAME; everything else it adds is registered as its modules load, through the same
calls core makes. The keys:

| key | what bedit does with it |
|---|---|
| `:themes` | each registered (`M-x theme-select`), claimed for the package |
| `:keys` | global bindings, written as init.blsp's `:keys` (`{"C-c a" claude}`): compiled when the package loads (`userkeys/register-package-keys`) into `:packages/keys`, claimed for the package |
| `:mode-keys` | one mode's bindings, as init.blsp's `:mode-keys` (`{markdown {"C-c C-c" …}}`) |
| `:on-retire` | a `(model) -> model` symbol run before the package is removed or updated: stop what it started |

A package's keys sit UNDER the user's: dispatch lays init.blsp's `:keys` and M-x
global-set-key over them (`userkeys/ed-user-scope`), so `"C-c a" nil` in init.blsp takes a
package's key away. C-h k and where-is report them as they run. A key that does not read, or
a command that is not one, is logged naming the package. Retiring the package takes its keys
back with the rest of its rows.

## A language package (built)

**One template.** bedit's own languages (`src/languages/<lang>.blsp`) and a language package
(`bedit-lang-<lang>`) are written the same way, against the same public module, and tested by
the same harness. The built-in ones stay in bedit; a new one can be either, and moving one from
bedit to a package (or back) is a rename of its module and nothing else: its samples, golden
listings (whose header names `corpus/write-golden`, the same in either place) and known gaps move
as they are. The sample package
is `bedit-lang-zig` (Zig over tree-sitter-zig), kept beside bedit as `../bedit-lang-zig`.

### The layout

```
bedit-lang-zig/
  project.blsp                 :enhances {bedit ">= 0.12"}, :dev-dependencies [[bedit :path "../bedit"]]
  src/bedit-lang-zig.blsp      the language: one spec, its toolchain row, a `bedit-plugin` entry
  tests/corpus_test.blsp       (corpus/define-tests) — that line is the whole file
  tests/corpus/zig/*.zig       realistic samples, with caret assertions …
  tests/corpus/zig/*.zig.faces … and their golden face listings
  tests/corpus/known-gaps.blsp the lines a check cannot get right yet, with why (optional)
  README.md
```

In bedit's tree the same parts are `src/languages/zig.blsp` (module `languages/zig`),
`tests/corpus/zig/` and an entry in `tests/corpus/known-gaps.blsp`; the corpus test file
(`tests/language_corpus_test.blsp`) is the same one line, for every language at once.

### The API: `(:use languages)`

```clojure
(defmodule bedit-lang-zig            ; bedit's own: (defmodule languages/zig …)
  "Zig for bedit: …"
  (:use languages))

(def zig-face-table
  (merge {:comment :syntax/comment :string :syntax/string :integer :syntax/number
          {:parent :function_declaration :field :name} :syntax/definition}
    (call-faces [{:kind :identifier :field :member :of :field_expression}])))

(deflanguage zig
  {:lang :zig
   :pattern "\\.zig$"
   :faces zig-face-table
   :indent {:width 4 :brackets #{:block :struct_declaration …} :verbatim #{:multiline_string}}
   :restart {:item-start "^((pub|const|var|fn|test)\\b|//|\\})" :opaque []}
   :definitions {:kinds #{:function_declaration :test_declaration}}
   :lsp {:id "zig" :servers [{:name "zls" :commands [["zls" []]] :root-markers ["build.zig"]}]}
   :format ["zig" "fmt"]
   :grammar {:url "https://github.com/tree-sitter-grammars/tree-sitter-zig"
             :revision "b670c8df85a1568f498aa5c8cae42f51a90473c0"
             :fingerprint "0f7a6572a2be7724af1f9986d123cf634f16b72773aebde1f860821527fc02dc"}
   :comment "// "})

(toolchain/register-toolchain        ; optional: the project type its manifest marks
  {:id :zig :name "Zig" :markers ["build.zig"] :compile "zig build" :test "zig build test"})

(defn bedit-plugin () {})            ; a package only: what bedit asks of it by name
```

`languages` (src/languages.blsp) is the whole authoring surface: the three macros —
`deflanguage` (a tree-sitter grammar), `deflexer` (a line lexer) and `deflisp` (an s-expression
dialect) — the face-table helpers (`call-faces`, `method-call-faces`, `field-faces`,
`token-faces`), the Lisp helpers (`head-set`, `lisp-indent-with`) and the tables several
languages share (`*quote-pairs*`, `*backtick-pairs*`, `*hash-strings*`, `*c-strings*`,
`*block-comment-opaque*`, `*triple-quote-opaque*`, `*backtick-opaque*`,
`*triple-quote-heredocs*`, `*prettier*`, `*case-label-electric*`). A language names nothing of the
context's machinery — `languages/core` and the rest are its detail. It names another language
module only to build on it, and only inside bedit: C++'s spec merges C's, TypeScript's and TSX's
JavaScript's, a `deflexer` names its lexer module's stem (`'languages/lex-configs/yaml`). A
package builds on bedit's languages through their registered specs, never their modules. A table
one language uses is that language's own. The macro names what it generates by the module it
expands in (`zig-spec`, `zig-fontify`, …), and refuses to replace a definition of that name it
did not generate (a hand-written `zig-indent` raises at load). Every
table it writes is claimed for the file that loads it, so a package's language goes back with
the package. One spec carries everything the editor knows of the language, and a key it does not
take (`:interpeters`) fails the load, naming the one meant:

| spec key | what it gives the editor |
|---|---|
| `:pattern`, `:interpreters` | which files open in the mode: a name pattern, `#!` programs |
| `:names` | the other words it is named by (a Markdown fence, a heredoc marker) |
| `:grammar {:url :revision :fingerprint}` | where its tree-sitter grammar lives, pinned |
| `:faces`, `:injections` | colours, and the code embedded in it |
| `:indent`, `:restart`, `:definitions`, `:folds` | RET/TAB, the windowed fontify, C-M-a, folding |
| `:resume [{:open :close}]` | the outer construct a window far down the file may begin inside (PHP's `<?php … ?>`): the last marker above it decides, an opener being re-read first |
| `:count-above true` on a `:restart` `:opaque` pair | a symmetric multi-line string (`"""`) is counted over the whole text above a window too, so a window in or below a docstring longer than the lead-in knows it (`:heredocs` markers always are) |
| `:format` | the formatter M-x format-buffer and format-on-save run: a command, alternatives, or a function of the buffer's layout (`formatter/buffer-layout`) answering either |
| `:lsp {:id :ids :servers}` | its language servers, reached by every buffer in the mode however it got there (name, `#!`, M-x), and its LSP `languageId` — `:ids` only for an extension LSP names apart (`jsx`) (`model/register-lsp`) |
| `:snippets` | its built-in snippet templates |
| `:embedded-languages` | a function of the text answering the languages it embeds that only the text names (Markdown's fence info strings): the corpus's golden check runs only once their grammars are loaded too |
| `:pairs`, `:strings` | electric pairs, and its strings and comments without a parse (`stringstate`) |
| `:fallback` | a line lexer to colour by while the grammar is missing |

The rest of what a language has is registered by the same calls bedit's own make, from the
same module: a toolchain row (`toolchain/register-toolchain` — a package's `build.zig` is a
project root, and M-x compile, C-c t and M-x run ask it), keys for its mode (the plugin map's
`:mode-keys`), anything else through `model/register-*`.

**The pin.** `:revision` is the grammar commit the tables were written against; `:fingerprint`
is that revision's SHAPE, `editor/treesit/grammar-fingerprint` — the sha256 of its ABI, its
named and anonymous node kinds and its field names, sorted — so a library built by hand, with no
install manifest, is still known to be the pinned one. Compute it from a build of the pin:

```bash
nest eval --test '(grammars/grammar-install-into :zig {:url "https://github.com/tree-sitter-grammars/tree-sitter-zig" :revision "b670c8d…"} "/tmp/g" "/tmp/g/src")'
nest eval --test '(do (%tree-sitter-load-grammar "/tmp/g/libtree-sitter-zig.so" :zig) (editor/treesit/grammar-fingerprint (editor/treesit/grammar-info :zig)))'
```

### Installing and removing

- **From the hive:** `M-x package-install` (or `i` in *Packages*).
- **From a checkout:** `M-x package-install-directory` installs the package in a directory as
  the hive's install would — copied into the package dir (its `.git` and `_deps` left out),
  checked that it `:enhances` this bedit, applied live — so an author tries a package before
  publishing it. Run it again after editing the checkout: it updates the installed copy (the
  old version retired first, as an update is).
- **Its grammar comes with it:** the grammars it declares that are not ready are fetched and
  built at their pins, off the loop, as `M-x grammar-install` does
  (`grammars/missing-package-grammars`) — installing the package is the asking. It needs git and
  a C compiler; a failure is said, and the language colours once `M-x grammar-install` runs.
- **Remove:** the mode, its file patterns, its servers, its toolchain row, its grammar
  declaration and its generated globals go back with the package; an open buffer in the mode is
  re-typed. The grammar library stays in `~/.config/bedit/grammars` (another language may parse
  with it).
- **Name it** `bedit-lang-<language>`, its main module the package's name: a package's modules
  may not take a name of bedit's (`languages/...` included) or of a std module.

`tests/language_package_test.blsp` pins this path: a package written to the template installed
from its directory, a file of it opened in its mode — coloured, indented, its server and
toolchain rows there — and removed with every row taken back.

### Testing a language

A language is tested by its CORPUS: realistic files in `tests/corpus/<mode>/`, the directory
named for the mode type, each written as the language's formatter writes it. ONE harness checks
bedit's languages and a package's — `corpus` (src/corpus.blsp), in bedit's `src/` so a package
reaches it through its dev dependency on bedit — and its one entry point is a test file of one
line:

```clojure
(defmodule corpus-test (:use test))
(corpus/define-tests)
```

`nest test` in the package (or bedit) then gives every sample each check below, a test named by
the file and the check. The paths are the project's own (`tests/corpus/`,
`tests/corpus/known-gaps.blsp`), and the languages a run answers for are the ones the project
registers (`corpus/own-languages`). A sample whose grammar is not loadable here is SKIPPED, and
said so: the grammar comes from `$BROOD_TEST_GRAMMARS` (CI's directory of every pinned grammar,
`tools/ci/install-grammars.blsp`), else the user's `~/.config/bedit/grammars`, read and never
written. A dotfile sample is kept as `dot.<name>` and visited as `.<name>` (`dot.gitignore`), so
git and editors never take the corpus's `.gitignore`, `.gitattributes` or `.editorconfig` for
their own:

1. **mode** — the file's name opens it in the mode its directory names.
2. **faces** — the sample's own caret assertions hold. A comment line whose text is carets puts
   a face under the columns of the line above (`ert-font-lock`'s idea, in bedit's faces):
   `// ^^^^ keyword  ^^^ function`, `!string` for NOT that face, `plain` for none, `<-` for the
   column the comment marker starts at. The marker is the mode's `:comment`, or its
   `:comment-block` pair for a language with only block comments (`<!-- ^^^ string -->`).
3. **golden faces** — `<file>.faces` beside it lists every painted token (`LINE:COL "text"
   face`); `corpus/write-golden` rewrites it after a deliberate change — `nest run
   tools/corpus-golden.blsp -- <lang>` in bedit, `nest eval --test '(corpus/write-golden
   ["zig"])'` in a package — and the diff is what gets reviewed.
4. **indentation, three ways** — every line indents to where it is written; the whole file,
   its indentation stripped, re-indents (C-x h C-M-\) to the sample; and typed a line at a time
   (RET, the text, electric indent) below a half-built buffer, every line lands at its column.
   Lines of verbatim content (a heredoc's body) are found from the spec's `:indent :verbatim`
   kinds and kept as written.
5. **restart** — fontifying from the spec's `:restart` answer paints what the whole text paints,
   at every line: the windowed fontify's one assumption, proven per sample — and again from a
   short lead-in, read after what is open above it (a `<?php`, a docstring), wherever the restart
   finds a point in it.
6. **robustness** — seeded random one-character edits: fontify, indent, restart, fold extent and
   breadcrumbs raise nothing and the spans stay in bounds and in order.

And the project's languages are checked against every registered one — bedit's own included, which
a package's run loads first (`corpus/load-languages`). A conflict is the project's when one of
its OWN languages is in it, so a package's run never fails for a pair of bedit's: none of its
languages shares a `:names` word or `#!` program with another, no corpus file is claimed by two
patterns, each of its specs passes its kind's check (its keys, its `:lsp` and every server row's
`:name :commands :root-markers` — the same check that fails the load), every entry of the known
gaps names a sample and a check, and every language it registers has a sample. A gap the
language cannot close yet — a line its indenter misplaces — goes in `tests/corpus/known-gaps.blsp`
with why, which only shrinks: a listed line that starts passing fails the test until it is removed.

The languages a run answers for are the ones the project's `:source-paths` register
(`corpus/own-languages`) — never the bedit a `:git` dev dependency fetches into `_deps/`. A sample
is judged at its LANGUAGE's conventions: no `.editorconfig` is read for it (`corpus/file-model`),
and the three indent checks all indent through TAB's own path (`indent/ed-indent-target`) at the
buffer's indent and tab widths. Markdown and Brood, whose modes are written by hand, register a
spec of the registration facts through the same path (`languages/core/hand-written-*-kind`), so
they take part in every check across languages too.

## A plugin's library dependencies (built)

A plugin with code may use a library that is not bedit's: bedit-agent uses `agentkit`, which
any Brood program driving a coding agent can use and which knows nothing of bedit. The plugin
names it under `:dependencies` (`[[agentkit :version "0.1.0"]]`):

- **Install:** installing the plugin installs each hive dependency not yet installed beside
  it in the package dir (`packages/hive-dependencies`), said with the install. A `:path` or
  `:git` dependency is not fetched.
- **Load:** a library installed beside the plugin goes on the load path before the plugin
  loads (`packages/installed-dependencies`). It needs no `:enhances`, and startup does not
  report it as a package it failed to load.
- **List and update:** *Packages* lists it as `library for bedit-agent` with the hive's
  latest version, and updates it as it updates a plugin.
- **Remove:** a library another installed package depends on is refused, naming who uses it
  (`packages/removal-refusal`). Removing a plugin removes the libraries only it used, said
  (`packages/orphaned-by`).
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
