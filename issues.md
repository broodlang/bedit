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

- [ ] **S4 Buffers are shared by display NAME.** `src/hosted.blsp:96`,
  `src/frames.blsp:52`, std `editor/buffer-registry`. `/a/README.md` then `/b/README.md`
  share one process — B's edits splice into A. `C-x C-w` renames without telling the
  registry (leak; other frames keep the old name).
  *Brood:* key the registry by a stable identity (path / id), name is metadata.

- [ ] **S5 Eval-on-type runs half-typed side-effecting forms.** Electric pairs close
  `(file/spit "notes.txt" "")` early and it runs (`liveeval.blsp:64`,
  `modes.blsp:704-711`). Same for the Elixir playground against a started Repo.
  *Brood:* a restricted eval mode in `eval-server` (no writes / spawns unless explicit),
  or checker-flagged effectful calls.

- [ ] **S6 A `--serve` session evaluates playground/tutor code inside the daemon.**
  `model.blsp:1813` checks `(whereis :editor)`; only `main.blsp` registers it. In-image
  path has no timeout — a loop hangs the session; a `defn` rebinds editor functions for
  every client.
  *Brood:* a per-session reply address in `std/editor/serve` / `evalsession`.

- [ ] **S7 Unquoted paths into `sh -c`.** `toolchain.blsp:119-120,183,200` (`pytest `,
  `go test `, `npm test -- ` + file), `npm run <script>`; `git.blsp:2922`
  `sequence.editor=cp <file>` (git runs it through the shell). Spaces break; a crafted
  filename runs code.
  *Brood:* `os/shell-quote`. *bedit:* argv rows where possible; quote the rest.

- [ ] **S8 Web mirror / collab trust model.** `remote.blsp:92-117` — the machine-wide
  cookie is what the docs tell you to hand a collaborator (full code execution on every
  node); bare `--listen PORT` binds `0.0.0.0`; `--as NAME` is trusted.
  *Brood:* capability-scoped links. *bedit:* loopback default; docs say attach = full trust.

- [ ] **S9 Plugins: checksum only, no authenticity.** `packages.blsp:114-120`; the sha256
  comes from the same registry response. `install!`/`update!` skip the `:enhances`
  version check startup applies; `load-installed!` adds refused packages to the load path.

## P1 — correctness

### Input / view / theme
- [ ] **C1 ✔ `C-u 3 C-x o` inserts `oo`.** `input.blsp` `ed-run-arg` re-runs
  `keymap-step` N times; step 1 clears `:pending`, steps 2..N look the last key up at top
  level. Fix: resolve once, repeat the command.
- [ ] **C2 ✔ `C-u -` on a chord leaves `:pending` set** (the inverse branch bypasses
  `step`: no `:pending`/`:echo` reset, no `try`).
- [ ] **C3 ✔ Theme switch leaves region / hl-line / brackets / scrollbar / isearch in the
  old palette.** `view.blsp:59-63,1051`, `isearch.blsp:20` copy faces at load;
  `theme.blsp:173-236` hand-duplicates face formulas and drops `:bold` on 8 faces.
  *Brood:* palette-derived chrome faces in `std/editor/face`.
- [x] **C4 ✔ Read-only yank is silent; `C-k` at EOL pushes `"\n"` before the refusal.**
  (Falls out of S2's single mutation path.)
- [ ] **C5 Registries reset on reload.** `interactive.blsp:269,291`
  (`*prefix-consuming*`, `*command-inverse*`), `keymaps.blsp:504` `*profiles*` — `def`,
  not `defonce`.
- [ ] **C6 Mode line / ui-kit widths count chars, not cells.** `statusbar.blsp:66,100,123,
  130-132`, `ui-kit.blsp:108,159,178`; `ui-clip` duplicates `view/ed-fit`.
- [ ] **C7 Horizontal scroll ignores tab width.** `model.blsp:2223` uses
  `buffer-column`; the view measures cells.
- [ ] **C8 Three different "visible rows" computations.** `input.blsp:1179` ignores
  inlays; `ed-scroll`, `panes/ed-pane-rows` each rebuild the predicate.
- [ ] **C9 `ui-row-ops` label runs under the key column.** `ui-kit.blsp:196`.
- [ ] **C10 Tab in a minibuffer with no `:complete-fn` calls nil** (compile, preset-save,
  beam trace, term prompts).

### Editing commands
- [ ] **E1 ✔ `C-t` at end of line swaps the newline** (`commands.blsp:861`); at EOB it
  no-ops. Emacs swaps the two chars before point.
- [ ] **E2 ✔ Repeated `C-x C-t` toggles** — point stays on the current line
  (`commands.blsp:893`).
- [ ] **E3 ✔ `M-q` destroys indentation and comment prefixes.** *Brood:* `string/fill`
  with a fill prefix.
- [ ] **E4 `C-M-h` / `C-x n d` parse every buffer as Brood** (`commands.blsp:2327,2372`).
- [ ] **E5 ✔ Kill coalescing list incomplete; `M-w` wrongly appends.**
  `ed-kill-commands` (`commands.blsp:755`).
- [ ] **E6 isearch vs Emacs:** wraps without "Failing"; C-s→C-r skips the current match;
  DEL re-searches from origin.

### Git / tooling
- [ ] **G1 Ruby `@@var` context line splits a hunk.** `git.blsp:258` trims before the
  `@@` test → corrupt patch to `git apply`.
- [ ] **G2 Renames lose the original path** (`git-parse-z`, `git.blsp:304`); unstage of a
  staged rename leaves the delete staged. `k` on a staged row / hunk discards the wrong thing.
- [ ] **G3 Unborn branch / detached HEAD.** `git-branch` returns `HEAD`/`?`; `u` fails
  before the first commit. Two `git-branch` implementations (`projects.blsp:135`).
- [ ] **G4 Background fetch can prompt for credentials.** `git.blsp:1083,1106`.
  *Brood:* `:env` (and a timeout) on `os/cmd`.
- [ ] **G5 Token-only URLs not redacted** in the process log (`git.blsp:1369`).
- [ ] **G6 find-file: `git ls-files` without `-z`** (quoted non-ASCII names; deleted
  files listed). `projects.blsp:129`.
- [ ] **G7 Two location parsers disagree** (`compile.blsp:31-43` vs `results.blsp:34-66`);
  URLs / `0.0.0.0:8080` read as errors; `:col` ignored.
- [ ] **F1 Format-on-save skips the disk-changed check; `mix format` runs in the file's
  dir (ignores `.formatter.exs`) and blocks the UI.** `commands.blsp:4590`,
  `format.blsp:54,78-84`. No tests.

### Processes / sessions
- [ ] **P1 `C-c t` (cold) and `C-c r` run the project's `:main`.** `apprun.blsp:29`,
  `testrun.blsp:97` — `path/temp` gives no `.blsp` suffix; `nest run` opens it as a
  document.
- [ ] **P2 BEAM attach: trace/break/resume/pstate act on the local VM.**
  `elixir/bedit_agent.exs:357-420,490-510`.
- [ ] **P3 A warm test session keeps its first project's root.** `testrun.blsp:597-613`.
- [ ] **P4 The shared `:sandbox` re-roots back and forth** (`sandbox.blsp:174` turns nil
  into `/tmp`; diagnostics re-root it) — wipes playground state.
- [ ] **P5 Removing a breakpoint can revert a later redefinition** (`debugger.blsp:548-575`);
  editor-internal processes can be paused.
- [ ] **P6 LSP URIs not percent-encoded** (`lsp.blsp:257-260,534`).
- [ ] **P7 LSP advertises `workspace/configuration` then answers MethodNotFound.**
- [ ] **P8 LSP handshake drops server messages before the initialize reply.**
- [ ] **P9 bshell: no interrupt; non-pty children are not killed as a group.**

### Live eval
- [ ] **L1 Tutor clears pending on ready** (`tutor.blsp:1179`) — the bug playground-core
  fixed; a test asserts it. Tutor should be a client of playground-core.
- [ ] **L2 Spy pane cache keyed by form index shows the wrong form after a shift**
  (`playground-core.blsp:583`).
- [ ] **L3 Elixir playground: `x = x + 1` doesn't depend on `x`** (`form-deps`).
- [ ] **L4 Playground/tutor in a second frame hang** — replies go to `:editor`.

### Hosted / collab
- [ ] **H1 `:shared?` means two things** — registry-owned vs presence-on; `share-session`
  never shares other files from the live editor (`collab.blsp:33-39,257`).
- [ ] **H2 Hosted edits diff whole text per edit, and misplace splices in runs of equal
  chars** (`hosted.blsp:124-130`). *Brood:* rope edits report their splice.
- [ ] **H3 SSE subscribers never monitored; snapshot per blink tick** (`web.blsp:293-306`).
- [ ] **H4 `:version-format` symbol calls any function** (`about.blsp:139`);
  `--attach` writes a default config (`remote.blsp:88`).

## P2 — structure, performance, tests

- [ ] **X1 `commands.blsp` (6.5k) split**: dired, LSP nav, vim grammar, collab, web,
  process list, project search, hexl → own modules; an `editing` core that every
  mutation goes through.
- [ ] **X2 Git status keymap lives in `modes.blsp`** and duplicates
  `git-dispatch-transient`'s table.
- [ ] **X3 Global `def` caches** (`wrap.blsp:104`, `view.blsp:107`,
  `complete-at-point.blsp:59`). *Brood:* bounded memo / LRU.
- [ ] **X4 `model.blsp` names its feature clients.** *Brood:* `autoload` declarations.
- [ ] **X5 Perf:** word motion / completion preview / `qr-replace` stringify the whole
  buffer per key. *Brood:* rope-scanning word motion + rope slice.
- [ ] **X6 Duplicated parsers:** two unified-diff parsers (*Brood:* `diff/parse-unified`),
  LSP JSON-RPC framing in bedit (*Brood:* `std/jsonrpc`).
- [ ] **T1 No tests for git's destructive commands, format.blsp, the playground send side,
  undo atomicity, `:modified` after kill/yank.**
- [ ] **T2 `strict_ratchet_test` tracks the installed nest**; stale references to
  deleted Python drivers (`tools/drive-elixir.blsp:8`, `tools/term-tutor.blsp:27`).
