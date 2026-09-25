# bedit — open issues from the 2026-09-23 whole-program review

Six parallel reviews (core loop/UI, commands/completion, git/modes/projects,
processes/sessions, distributed/config, live-eval/tests). ✔ = confirmed by a run or
by reading the exact code path; the rest are from careful reading. Each issue names
the Brood (language) side first when there is one — the prime directive.

Status: `[ ]` open · `[x]` fixed · `[~]` partly / deferred (reason given)

## P0 — security and lost work

- [x] **S1 ✔ The web mirror's `/input` accepts keys from any web page.**
  `src/web.blsp:414-449`. No token, no Origin/Host check; a `mode:'no-cors'` text/plain
  POST from any tab reaches `send editor tok` — M-x, `C-x C-e`, shell. DNS rebinding also
  reads `/` and `/events`.
  *Brood:* token + Host/Origin guard as `std/http` middleware.
  *bedit:* a per-server random token in the page URL, required on every route; reject a
  non-loopback `Host`.

- [x] **S2 ✔ Most edits never set `:modified`.** Only `ed-edit` (`commands.blsp:69`) sets
  it. `ed-kill-span` (C-k, M-d, M-DEL, C-M-k, M-z, M-k), `cmd-yank`, `cmd-yank-pop`,
  `qr-replace`, `ed-undo-step`, paredit edits (`ed-apply`), `preview-accept` bypass it —
  C-k then C-x k asks nothing and the edit is lost; auto-save skips the buffer.
  *Brood:* the buffer owns "modified" (rope ≠ saved rope, or bumped by every mutator).
  *bedit:* every mutation goes through one path; read-only refusal comes with it (C4).

- [x] **S3 ✔ `replace-region` is two undo steps.** `std/editor/buffer.blsp:1134`
  (delete + insert). `M-q` then `C-/` empties the paragraph; `M-c`, `C-t`, `M-t`, case
  region, comment toggle, cycle-spacing, completion accept; query-replace `!` takes 2×N
  undos through broken states.
  *Brood:* atomic `replace-region`; a `with-undo-group` for multi-edit commands.

- [x] **S4 Buffers are shared by display NAME.** `src/hosted.blsp:96`,
  `src/frames.blsp:52`, std `editor/buffer-registry`. `/a/README.md` then `/b/README.md`
  share one process — B's edits splice into A. `C-x C-w` renames without telling the
  registry (leak; other frames keep the old name).
  *Brood:* key the registry by a stable identity (path / id), name is metadata.

- [ ] **S5 Eval-on-type runs half-typed side-effecting forms.** Electric pairs close
  `(file/spit "notes.txt" "")` early and it runs (`liveeval.blsp:64`,
  `modes.blsp:704-711`). Same for the Elixir playground against a started Repo.
  *Brood:* a restricted eval mode in `eval-server` (no writes / spawns unless explicit),
  or checker-flagged effectful calls.

- [x] **S6 A `--serve` session evaluates playground/tutor code inside the daemon.**
  `model.blsp:1813` checks `(whereis :editor)`; only `main.blsp` registers it. In-image
  path has no timeout — a loop hangs the session; a `defn` rebinds editor functions for
  every client.
  *Brood:* a per-session reply address in `std/editor/serve` / `evalsession`.
  FIXED (with L4): a `--serve` client's loop binds `*ui-loop*`, so `ed-headless?` reads it as live and it evaluates in the sandbox child, its answers routed back to it.

- [x] **S7 Unquoted paths into `sh -c`.** `toolchain.blsp:119-120,183,200` (`pytest `,
  `go test `, `npm test -- ` + file), `npm run <script>`; `git.blsp:2922`
  `sequence.editor=cp <file>` (git runs it through the shell). Spaces break; a crafted
  filename runs code.
  *Brood:* `os/shell-quote`. *bedit:* argv rows where possible; quote the rest.

- [~] **S8 Web mirror / collab trust model.** FIXED: bare `--listen PORT` binds loopback; docs say attaching is full trust. OPEN (Brood): per-session cookies, a link that cannot ship code, trusted `--as`. `remote.blsp:92-117` — the machine-wide
  cookie is what the docs tell you to hand a collaborator (full code execution on every
  node); bare `--listen PORT` binds `0.0.0.0`; `--as NAME` is trusted.
  *Brood:* capability-scoped links. *bedit:* loopback default; docs say attach = full trust.

- [~] **S9 Plugins: checksum only, no authenticity.** FIXED: install/update/startup share the `:enhances` check; refused packages stay off the load path (untested: needs a redirectable config dir). OPEN (Brood std/package): signatures or trust-on-first-use for hosted packages. `packages.blsp:114-120`; the sha256
  comes from the same registry response. `install!`/`update!` skip the `:enhances`
  version check startup applies; `load-installed!` adds refused packages to the load path.

## P1 — correctness

### Input / view / theme
- [x] **C1 ✔ `C-u 3 C-x o` inserts `oo`.** `input.blsp` `ed-run-arg` re-runs
  `keymap-step` N times; step 1 clears `:pending`, steps 2..N look the last key up at top
  level. Fix: resolve once, repeat the command.
- [x] **C2 ✔ `C-u -` on a chord leaves `:pending` set** (the inverse branch bypasses
  `step`: no `:pending`/`:echo` reset, no `try`).
- [~] **C3 ✔ Theme switch leaves region / hl-line / brackets / scrollbar / isearch in the
  old palette.** `view.blsp:59-63,1051`, `isearch.blsp:20` copy faces at load;
  `theme.blsp:173-236` hand-duplicates face formulas and drops `:bold` on 8 faces.
  *Brood:* palette-derived chrome faces in `std/editor/face`. — FIXED in bedit (aliases gone, `:bold` restored, a drift test). OPEN: the two formula copies in theme.blsp remain — one registry of palette-derived faces in std would remove them.
- [x] **C4 ✔ Read-only yank is silent; `C-k` at EOL pushes `"\n"` before the refusal.**
  (Falls out of S2's single mutation path.)
- [x] **C5 Registries reset on reload.** `interactive.blsp:269,291`
  (`*prefix-consuming*`, `*command-inverse*`), `keymaps.blsp:504` `*profiles*` — `def`,
  not `defonce`.
- [x] **C6 Mode line / ui-kit widths count chars, not cells.** `statusbar.blsp:66,100,123,
  130-132`, `ui-kit.blsp:108,159,178`; `ui-clip` duplicates `view/ed-fit`.
- [x] **C7 Horizontal scroll ignores tab width.** `model.blsp:2223` uses
  `buffer-column`; the view measures cells.
- [x] **C8 Three different "visible rows" computations.** `input.blsp:1179` ignores
  inlays; `ed-scroll`, `panes/ed-pane-rows` each rebuild the predicate. — FIXED: one `model/ed-row-wise?` read by all three; the cursor step counts inlay rows.
- [x] **C9 `ui-row-ops` label runs under the key column.** `ui-kit.blsp:196`.
- [x] **C10 Tab in a minibuffer with no `:complete-fn` calls nil** (compile, preset-save,
  beam trace, term prompts).

### Editing commands
- [x] **E1 ✔ `C-t` at end of line swaps the newline** (`commands.blsp:861`); at EOB it
  no-ops. Emacs swaps the two chars before point.
- [x] **E2 ✔ Repeated `C-x C-t` toggles** — point stays on the current line
  (`commands.blsp:893`).
- [x] **E3 ✔ `M-q` destroys indentation and comment prefixes.** *Brood:* `string/fill`
  with a fill prefix.
- [x] **E4 `C-M-h` / `C-x n d` parse every buffer as Brood** (`commands.blsp:2327,2372`).
- [x] **E5 ✔ Kill coalescing list incomplete; `M-w` wrongly appends.** (M-w appending after a kill is Emacs's own `copy-region-as-kill` behaviour — kept.)
  `ed-kill-commands` (`commands.blsp:755`).
- [x] **E6 isearch vs Emacs:** wraps without "Failing"; C-s→C-r skips the current match;
  DEL re-searches from origin. — FIXED: fail in place then wrap, turn round on the same match, DEL pops a step history (tests in editing_test).

### Git / tooling
- [x] **G1 Ruby `@@var` context line splits a hunk.** `git.blsp:258` trims before the
  `@@` test → corrupt patch to `git apply`.
- [x] **G2 Renames lose the original path** (`git-parse-z`, `git.blsp:304`); unstage of a
  staged rename leaves the delete staged. `k` on a staged row / hunk discards the wrong thing.
- [x] **G3 Unborn branch / detached HEAD.** `git-branch` returns `HEAD`/`?`; `u` fails
  before the first commit. Two `git-branch` implementations (`projects.blsp:135`).
- [x] **G4 Background fetch can prompt for credentials.** `git.blsp:1083,1106`.
  *Brood:* `:env` (and a timeout) on `os/cmd`.
- [x] **G5 Token-only URLs not redacted** in the process log (`git.blsp:1369`).
- [x] **G6 find-file: `git ls-files` without `-z`** (quoted non-ASCII names; deleted
  files listed). `projects.blsp:129`.
- [x] **G7 Two location parsers disagree** (`compile.blsp:31-43` vs `results.blsp:34-66`);
  URLs / `0.0.0.0:8080` read as errors; `:col` ignored.
- [x] **F1 Format-on-save skips the disk-changed check; `mix format` runs in the file's
  dir (ignores `.formatter.exs`) and blocks the UI.** `commands.blsp:4590`,
  `format.blsp:54,78-84`. No tests. — FIXED: check order, project root, stamp/unmodified on failure, tests; the formatter runs in a task (`:format-proc`), your edits since the save kept.

### Processes / sessions
- [x] **P1 `C-c t` (cold) and `C-c r` run the project's `:main`.** `apprun.blsp:29`,
  `testrun.blsp:97` — `path/temp` gives no `.blsp` suffix; `nest run` opens it as a
  document.
- [x] **P2 BEAM attach: trace/break/resume/pstate act on the local VM.**
  `elixir/bedit_agent.exs:357-420,490-510`. — FIXED: tracer, suspend, resume and the stopped-process read live in `Bedit.Remote` and run on the node being debugged. Found on the way: RESUME had never worked (only the suspending process may resume — now the tracer does), and every attached observation failed (`:erlang.function_exported?` is not an Erlang function). Live two-node test in beam_test.
- [x] **P3 A warm test session keeps its first project's root.** `testrun.blsp:597-613`.
- [x] **P4 The shared `:sandbox` re-roots back and forth** (`sandbox.blsp:174` turns nil
  into `/tmp`; diagnostics re-root it) — wipes playground state.
- [~] **P5 Removing a breakpoint can revert a later redefinition** (`debugger.blsp:548-575`); FIXED the revert, and any LOOP process (every window, every `--serve` client — `*ui-loop*`) now runs through a breakpoint, not only the first window. OPEN:
  other editor-internal processes (buffer processes, the registry) can still be paused.
- [x] **P6 LSP URIs not percent-encoded** (`lsp.blsp:257-260,534`).
- [x] **P7 LSP advertises `workspace/configuration` then answers MethodNotFound.**
- [x] **P8 LSP handshake drops server messages before the initialize reply.**
- [x] **P9 bshell: no interrupt; non-pty children are not killed as a group.** — FIXED: brood `os/signal` (3c243c45) signals the child's process group (`os/spawn` already made it one, and `os/close` already killed it); `C-c C-c` in a shell buffer interrupts the running command. The worker now answers the loop that opened it (`*ui-loop*`), not `:editor`.
- [x] **P10 Off-loop workers answered `:editor`, the first window.** A compile, a test run, a project run, a terminal or a shell started from a second frame (or a `--serve` client) painted its output into the first. — FIXED: `model/ed-loop-address` is captured on the loop when work is handed off; procstream handlers BUILD events and the worker delivers each run's to the address that run came with. Left on purpose: `frames` asks the primary; the LSP connection and the `*Messages*` log are shared by every frame.

### Live eval
- [~] **L1 Tutor clears pending on ready** (`tutor.blsp:1179`) — FIXED (pending kept, test corrected). OPEN: the tutor is still a second copy of playground-core's launch/reply logic, not a client of it. Was: the bug playground-core
  fixed; a test asserts it. Tutor should be a client of playground-core.
- [x] **L2 Spy pane cache keyed by form index shows the wrong form after a shift**
  (`playground-core.blsp:583`). — FIXED: `workings/rekey` moves each report through the same form pairing the notes use, before the stale ones are forgotten.
- [x] **L3 Elixir playground: `x = x + 1` doesn't depend on `x`** (`form-deps`).
- [x] **L4 Playground/tutor in a second frame hang** — replies go to `:editor`. — FIXED (with S6): brood `evalsession` routes each answer to the loop that asked and the lifecycle to every subscriber (87c2ef44); `ui-run` binds `*ui-loop*` (593e909a), which `ed-headless?`, `session/start` and `session/request` read, so a second frame or a `--serve` client is a loop like the first. Verified by brood's evalsession tests and every driver; no live second-frame driver yet.

### Hosted / collab
- [ ] **H1 `:shared?` means two things** — registry-owned vs presence-on; `share-session`
  never shares other files from the live editor (`collab.blsp:33-39,257`).
- [x] **H2 Hosted edits diff whole text per edit, and misplace splices in runs of equal
  chars** (`hosted.blsp:124-130`). *Brood:* rope edits report their splice. — FIXED: brood c16e28a1 — the edit primitives log `[rope-before rope-after lo hi repl]`; `link-propagate-buffers` sends those (no text read), diffing only when the log cannot account for a change (undo).
- [x] **H3 SSE subscribers never monitored; snapshot per blink tick** (`web.blsp:293-306`). (The snapshot half was already debounced to the idle beat behind `:web-dirty`.)
- [x] **H4 `:version-format` symbol calls any function** (`about.blsp:139`) — KEPT by design: it is a documented extension point in the user's own config, which is not a trust boundary; FIXED:
  `--attach` writes a default config (`remote.blsp:88`).

## P2 — structure, performance, tests

- [ ] **X1 `commands.blsp` (6.5k) split**: dired, LSP nav, vim grammar, collab, web,
  process list, project search, hexl → own modules; an `editing` core that every
  mutation goes through.
- [x] **X2 Git status keymap lives in `modes.blsp`** and duplicates
  `git-dispatch-transient`'s table. — RESOLVED: the keymap STAYS in modes (git is a deferred module, and a git buffer another frame rebuilds from the registry needs its keys before git loads); the two tables are held together by transient_test — every dispatch key, pressed directly, opens the same menu or runs the same command (`g` excepted, as in Magit).
- [ ] **X3 Global `def` caches** (`wrap.blsp:104`, `view.blsp:107`,
  `complete-at-point.blsp:59`). *Brood:* bounded memo / LRU.
- [ ] **X4 `model.blsp` names its feature clients.** *Brood:* `autoload` declarations.
- [ ] **X5 Perf:** word motion / completion preview / `qr-replace` stringify the whole
  buffer per key. *Brood:* rope-scanning word motion + rope slice.
- [x] **X6 Duplicated parsers:** two unified-diff parsers (*Brood:* `diff/parse-unified`),
  LSP JSON-RPC framing in bedit (*Brood:* `std/jsonrpc`). — FIXED: gitdiff reads hunk headers with `diff/hunk-header`; the LSP client builds and decodes through brood's new `std/jsonrpc` (3f87601c), its framing tests moved there.
- [ ] **T1 No tests for git's destructive commands, format.blsp, the playground send side,
  undo atomicity, `:modified` after kill/yank.**
- [x] **T2 `strict_ratchet_test` tracks the installed nest** (now checks with `os/exe-path`, the nest running the suite); stale references to
  deleted Python drivers (`tools/drive-elixir.blsp:8`, `tools/term-tutor.blsp:27`).
