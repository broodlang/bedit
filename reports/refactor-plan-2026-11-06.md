# Refactor plan: cohesion and boundaries (2026-11-06)

Merged from three read-only reviews (bedit core, bedit features, brood). Nothing here is done.
Line numbers are from 2026-11-06. Numbers are heuristic (awk over source), so check before relying on one.

## What is actually wrong

- The `:use` graph has no cycles, but calls by qualified name form one 54-module strongly
  connected set. Simulated: cutting `scroll`->`results` alone takes it from 49 to 26.
- CLAUDE.md's "the core names no feature" is false in three places: `view` (rainbow, glyphless,
  whitespace, spell, isearch, avy, pulse, headerline, solong), `input` (terminal, bshell secrets),
  `pool` (`ed-kill-at`, `ed-open-text`).
- `hittest`'s claim that input never imports the renderer is false: `input`->`hittest`->`view`.
- 17 of 159 src files are over 1000 lines; commands 4148, view 3312, model 3041.
- `editor/buffer` claims to be pure and holds the buffer process, file I/O and text commands.

## Traps every step must respect

- Guest allowlist `ed-guest-modules` is by module name: moving a command refuses it for guests silently.
- `keymap-run` catches errors, so a stale or unloaded symbol is a dead key with no error.
- A new command module must be `:use`d from `input` or `main`; only drive-deferred sees the gap.
- Quoted symbol tables do not follow a move (`*typing-commands*`, `ed-kill-commands`,
  `*repeat-commands*`, `*completion-auto-commands*`, `ed-event-handlers`, quoted `'model/` hooks).
- No re-export in Brood: a moved name means a `:use` in every consumer, tests too (102 `:use model`).
- `tests/layout_test:62` slurps src/view.blsp and passes vacuously if the code leaves it.
- A module name reserves itself against hive packages, and std (`tool`, `proc`, `net` too) wins.
- Brood: each new module needs `embedded_module!`, each moved public name a `renames.rs` entry, and
  a bedit move lands with a `BEDIT_REF` bump.
- Keep post-step and idle-job `:order` values; several orders are load-bearing.

## Part 1: what we can do in Brood

No missing primitive blocks this. These are boundary fixes in brood itself.

1. `:syntax/*` faces -> `editor/face`. Removes `lexer`'s `:load editor/highlight`.
2. Break the props/splice-log/undo cycle inside buffer.blsp (4 functions move, no new file).
3. `editor/span-properties` (~240 lines), no caller changes.
4. `editor/buffer-server` (~520 lines): `editor/buffer` becomes pure. 14 bedit files add a `:use`.
5. `editor/attach` + `editor/serve-protocol` (~420 lines).
6. `editor/frontend` (~438 lines): a thin client stops loading the loop.
7. `editor/line-cache` (~436 lines): lexer and stringstate get it without the Brood lexer.
8. `editor/grammar-install` (~230 lines): `treesit` becomes pure.
9. `builtins/image.rs`, `backend/fonts.rs`, `backend/ink.rs`, `paint/strips.rs`, retained-frame struct.
10. `host/treesit/{disabled,grammar,injections}.rs`.
11. `builtins/gui.rs` (~1946 lines out of terminal/native.rs): the largest fix, the worst conflict risk.
12. Move rectangles, whitespace/join and paragraph motion to bedit (~380 lines, ADR-417).
13. `editor/buffer-file` (~175 lines), after charset lands.

Behaviour fixes found on the way, not mechanical: three CSI scanners disagree (`ansi-csi-final?`
takes letters only, so `render` on `ESC[3~` swallows text; read, not run). Rope diff duplicated in
treesit.rs. Three face readers. Three `[:key ...]` shapes across four `receive` forms.

## Part 2: what we will do in bedit

### Phase A: guards, nothing moves
0. Snapshot the guest-allowed M-x set; assert every keymap and mode symbol is bound; add new
   modules to drive-deferred; make layout_test fail if its target code moved.

### Phase B: cut the cycle (highest value, do first)
1. `model` -> `guest`, with a declared allow set beside the commands. Needs care.
2. Command traits in `interactive` replace the four quoted tables. `model` names no command.
3. `model` -> `clipboard` (~480 lines).
4. `model` + `input` -> `minibuffer` (~495 lines); `ed-post-step` to `input`.
5. Cut `scroll`->`results` (`inlay-lines` down). One edge, 49 to 26.
6. `panes` -> `spancache` (~790) and `mouse` (~600). `panes` drops to ~490.
7. `view` -> `modeline` (~345), `overlayview` (~159); helpers to `ui-kit`, `theme`, `model`.
   `hittest` drops `:use view`.
8. `input` -> `events` (~364).
9. `commands` -> `lifecycle` (~385), `project-commands` (~235).
10. `cmd-kill-buffer` -> `pool`, `*no-region-message*` -> `model`. Importers of commands 11 -> ~5.
11. Residual cuts: `cmd-welcome-link`, `ed-scope`, `profile-keymap-with`, embark's keys.

### Phase C: features register, the core names none
12. `register-slot-keeper` + `register-visit-step` (Emacs's find-file-hook): `ed-kill-at` and
    `ed-open-text` name no feature; the three `ed-drop-*-slot` copies go. Order is load-bearing.
13. `register-file-handler` (file-name-handler-alist), sudoedit its first row; `ed-*-as-root` go.
14. Highlight-source registry in `view`. `ui-memo` deps must gain each source's inputs or paint goes stale.
15. Overlay registry in `input`, ranks reproducing today's order; secret logic into `passwd`.

### Phase D: feature splits
16. `languages` -> `org-mode` (~165). Run tools/check-modes.sh.
17. `isearch` -> `query-replace` (~340).
18. `bshell` -> `comint` (~220): all 19 terminal->bshell refs go. Rename `cmd-bshell-*` separately.
19. `packages` -> `package-store` (~90), `package-ledger` (~470).
20. `stringstate` -> `stringlex` (~320), `stringwarm` (~105); drop private `line-text` copies.
21. `autosave` -> `autorevert` (~150), `sidecar` (~180).
22. `config` -> `config-paths` (~70), `display-rules` (~100).
23. `pool` -> `file-save` (~130), after step 13.
24. `languages` -> `language-core` + family files. Last: size only.
25. Split where a second job is real: `lsp` protocol, `lsp-commands` filing, `tutor`, `testrun` warm
    runner, `gitstatus` actions, `complete-at-point`.

### Duplicates, any time
`ed-primary-quit` twice with different arity; `ed-line-blank?` / `ed-blank-line?`; `ed-link-abs-string`
and `cmd-visit-location`; three line-offset helpers; `(= (:type b) :term)` five times; scrollbar logic
in three modules; `display-buffer` action names in `config` and `pool`.

### Leave alone
`ownership`, `electric`, `fill`, `startup`, `remote`, `sudoedit`, the `config` settings table, the
`model` registries, structural and indent in `commands`, macro replay in `input`, the edit and undo
core of `editor/buffer`, `rope_regex.rs`, `decoder.rs`, `screen.rs`, `ansi.blsp`.

## Verification per step
`nest check`, `nest format --changed`, the test files the step touches, drive-deferred for any
command move. Full suites go to CI, one push at a time, so a red names one step.
