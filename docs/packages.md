# Packages — an extension ecosystem (design note, deferred)

**Status:** design-of-record for a direction we've decided on but are **not building
yet**. Captured so the reasoning isn't lost. Nothing here is implemented; the editor
today loads only its own bundled modules at startup.

The question that started this: *how do we load editor packages to enhance or change
the editor — almost like Emacs?* This note is the answer, and the answer is unusually
clean because of the prime directive: **Brood already has a package manager**, and the
editor's late-bound, registry-driven design is already shaped to reuse it. We don't
invent a package system — we point the one Brood has at the editor.

It builds on [`configurability.md`](configurability.md): a package "hooks into" the
editor by calling the **same registration functions** core uses (`defcommand`,
`register-type-layers`, `bind-key`, `add-hook`, `defsetting`, `register-theme`, …). The
registries *are* the plugin API — the Emacs property that everything uses the same
primitives as the core.

## The key realization

Brood/`nest` already ships the hard parts (ADR-037 in the brood repo):

- **Manifests with `:dependencies`** — `:git` (`[name :git "url" :ref "ref"]`) and
  `:path` (`[name :path "dir"]`) deps (`std/tool/project.blsp`).
- **Transitive resolution + a committed lockfile** — `project.lock.blsp`, a `_deps/`
  cache, tree-hashing (`std/tool/package.blsp`).
- **CLI** — `nest add` / `fetch` / `update` / `tree` / `remove`.
- Critically: **`*load-path*` is mutable and consulted at runtime**, and `(require 'mod)`
  loads a module into the *running* image once its dir is on the path
  (`std/prelude.blsp`). `(load path)` evaluates every form in a file from an arbitrary
  path, with namespace bracketing.

And the editor's modules already wire themselves in purely by calling registration
functions at load time — `defcommand`, `register-type-layers` / `register-file-type`,
`register-profile`, `register-log-route`, the mode-service facets.

Put those two facts together and the design falls out:

> **An editor package is a Brood nest. The user's `~/.config/bedit/` directory
> *is itself a nest*; installed packages are its `:dependencies`; the existing `nest`
> package manager is the package system. A package hooks into the editor by calling the
> same registration functions core uses.**

The brood repo already anticipated this (`docs/decisions.md`, ADR-037 motivation):
*"as soon as the editor (M2+) starts inviting plugins / modes / syntax-highlighters,
the absence of a package story stops a real ecosystem from forming."* The package
manager **is** the intended plugin substrate.

## Concept mapping (Emacs → bedit)

| Emacs | bedit |
|---|---|
| `.el` file with `(provide 'foo)` | a `defmodule` in a Brood nest |
| `load-path` | `*load-path*` (already runtime-mutable) |
| `require` / `load` | `require` / `load` (already exist) |
| `~/.emacs.d/elpa/`, `package.el`, MELPA | the config nest's `:dependencies` + `_deps/` + `nest fetch` |
| `package-install` | `nest add` against the config nest + `require` (live) |
| `defcustom` / `define-key` / `add-hook` / `auto-mode-alist` | the settings / `bind-key` / `add-hook` / `register-file-type` registries ([`configurability.md`](configurability.md)) |
| `use-package` | a declarative `(package …)` form in `init.blsp` |
| autoloads | the `M-x` registry + late-bound command symbols |

So most of "load packages like Emacs" **already exists** — it just isn't pointed at the
editor yet.

## What a package author writes (the payoff)

Because a package calls the same registration functions core does, there is *no plugin
API to learn*. A whole syntax-highlighter package:

```clojure
(defmodule pkg-zig
  "Zig syntax highlighting + structural nav for bedit."
  (:use editor/layers) (:use editor/treesit))

(defn zig-fontify (text) (treesit/fontify text :zig pkg-zig/zig-face-of))

(def zig-mode-layer
  {:name 'zig :parser :tree-sitter :ts-lang :zig
   :file-pattern "\\.zig$" :fontify 'pkg-zig/zig-fontify :comment-syntax "// "})

(modes/register-prog-mode 'pkg-zig/zig-mode-layer :zig)   ; ← the same call core makes
(provide 'pkg-zig)
```

Its `project.blsp` declares `:name "pkg-zig"` and any deps; that's the entire package.

## The gaps — prime-directive split

**Part 1 — Brood / `std` (the language gaps packages expose).**

1. **Package-rooted namespaces + author `:exports` — the big one.** Today module names
   must be **globally unique** across a project and all deps (the global table is flat;
   ADR-070 in the brood repo defers package namespacing). Two packages that both define
   a `theme` or `git` module **collide**. A real third-party ecosystem cannot exist
   without this — it is exactly the gap the prime directive predicted the editor would
   surface. Implement ADR-070's package-rooted namespaces + `:exports` / import aliases.
   *Everything third-party is gated on this;* first-party and curated path/git packages
   we control work before it.
2. **Load a nest's deps into a *running* image (small).** `nest run` resolves + loads
   sources at startup. Expose a callable runtime entry — `(load-nest <dir>)` — that runs
   `package/ensure-deps` on a manifest, appends the source dirs to `*load-path*`, and
   `require`s the entry modules. The pieces exist (`ensure-deps` returns the dirs;
   `project-setup` can re-run); this is packaging them as a clean `std/tool` entry rather
   than CLI-only.
3. **(Maybe) a teardown seam for `require`.** There is no `unrequire`, so live *disable*
   is best modeled at the registry level (drop the package's layers/binds), not by
   unloading code. `std/layers` already has the `:on-close` / `:deactivate` cleanup seam
   to build on. Not blocking.

**Part 2 — the editor.** Built on Part 1 and on the config registries from
[`configurability.md`](configurability.md):

1. **Config dir as a nest + startup loader.** Treat `~/.config/bedit/` as a nest: a
   `project.blsp` whose `:dependencies` are the user's packages, plus `init.blsp` (still
   declarative data, ADR-065 intact). At startup `main` calls `load-nest` on it →
   packages' modules load and register live → then `init.blsp` is applied. Bundled modes
   (brood/markdown/ruby/…) stay first-party, or migrate to path-deps later to dogfood the
   seam.
2. **`M-x package-install` / `package-list` / `package-delete`, live.** Thin wrappers
   over the package manager: `package-install` = add the dep to the config nest's
   manifest, `ensure-deps`, append to `*load-path*`, `require`. Because registries are
   **late-bound and the image is live, a freshly installed package's commands / modes /
   keybindings take effect with no restart** — which genuinely beats Emacs's
   restart-or-autoload dance, and is a direct payoff of the immutable, symbol-resolved
   design. A `*Packages*` buffer is a read-only mode-as-layer, exactly like the
   *Process List* / dired buffers we already have.
3. **An `autoload` abstraction (fast startup).** The `M-x` registry already maps a name →
   a command; generalize it so a name can map to "require module X, then dispatch."
   `(autoload 'pkg/cmd-foo "pkg-foo")` registers the name without loading the module;
   first use requires it then runs. Late binding makes this a few lines and keeps startup
   cheap as the package count grows.
4. **`use-package`-style declarative integration.** Once 1–3 plus the config registries
   exist, `init.blsp` ties a package to its config in one data form (no eval — ADR-065
   holds):

   ```clojure
   (package magit
     :install [:git "https://…/brood-magit" :ref "v1"]
     :bind    {"C-x g" magit/cmd-git-status}
     :hook    {:prog-mode magit/diff-hl-on}
     :setting {:magit/auto-revert true})
   ```

   User-authored *function bodies* live in a small local package the config nest
   depends on via `:path`, not inline in `init.blsp`.

## A staged path

1. **Now (no language change).** `load-nest` runtime entry (Part 1.2) + config-dir-as-nest
   startup loader (Part 2.1) + `M-x package-install/list` over the manager (Part 2.2),
   restricted to `:path` and trusted/curated `:git` deps. This already gives a live,
   restart-free, Emacs-like package flow using the existing manager.
2. **Then.** `autoload` (Part 2.3) and the `(package …)` declarative form (Part 2.4),
   once the settings / `bind-key` / `add-hook` registries land
   ([`configurability.md`](configurability.md)).
3. **The gating language work.** ADR-070 package-rooted namespaces + `:exports`
   (Part 1.1) — required before a *third-party* (multiple untrusted packages) ecosystem
   is safe. Until then, curated path/git packages work fine.

## When to actually do this

After the customization surface ([`configurability.md`](configurability.md)) — a
package configures the editor through those registries, so they come first. Stage 1 is
attractive early even so: it's thin glue over machinery that already exists and proves
the "config dir is a nest, packages load live" model end-to-end. The one real language
investment is ADR-070 namespacing — and that's deferred until we actually want to open
the doors to untrusted third-party packages.

The headline: we point the package manager Brood already has at the editor, treat the
user's config dir as a nest, and let packages register through the same late-bound
registries the core uses — so "core" and "package" are the same mechanism, which is the
property that made Emacs's ecosystem possible.
