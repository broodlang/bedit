# The web-fuzz render-error anomaly (compiled code ≠ source semantics)

**Status:** open Brood lead, editor unaffected in normal states. Found 2026-07-10 while the
working tree happened to have exactly 4 modified files; **reproduced at HEAD** (a clean
worktree given the same dirty-file shape), so it predates the collab work that surfaced it.

## Symptom

`tests/web_fuzz_session_test.blsp` fails with

    render error: rope-line->char: line 13 out of bounds (valid 0..=12)

while it walks `*git-status*` rows RET-ing diff previews — but only when the repo's git
status has a particular shape (≈12 status lines), and only in some run histories.

## What was established (all deterministic once the state is reached)

- The thrower is `view/ed-diagnostic-overrides` (view.blsp:148, the `bol` binding), on the
  `*git-status*` buffer, with a **stale diagnostic** `{:line 14 :col 1}` on the model
  (left over from an earlier `.blsp` buffer's check) and `n = (buffer-line-count buf) = 12`.
- The function's filter — `(< (dec (get d :line)) n)` → `(< 13 12)` → false — **must drop
  that diagnostic**. Probed in the same broken state, from the test module:
  - the identical inline predicate keeps **0** of the same list;
  - `buffer-line-count` = `rope-line-count` = 12; `rope-line->char rope 12` = 234 (EOF ok),
    `13` rejected — the rope is internally consistent;
  - `:line`/`:col` are numbers (`number?` true), `dec` = 13.
- Yet calling `ed-diagnostic-overrides` (the view-module compilation) with those very values
  — even with a minimal `{:diagnostics ds}` model — **throws**, meaning *its* compiled filter
  passed the line-14 entry. Same expression, same inputs, different result by compilation
  unit + call history.
- Fresh-context repros do NOT trigger it: big-buffer-then-small-buffer calls behave; a
  synthetic buffer with the exact status text behaves. Reaching the state needs the fuzz
  test's full editor session history (find-file on a 3091-line buffer, scrolls, git-status,
  repeated renders) — i.e. it smells like **JIT state** (inline caches / shape
  specialization) in the view module's compiled `ed-diagnostic-overrides` diverging from
  source semantics after certain warmup.

## Why it comes and goes

The trigger needs (a) a stale `:diagnostics` entry whose line exceeds the status buffer's
line count, and (b) the status buffer small enough (few dirty files) for the bounds filter
to matter. Commit or touch more files and the status grows past the stale line → latent.

## Repro sketch

With a working tree of ~4 modified files (status ≈ 12 lines):

    nest test tests/web_fuzz_session_test.blsp     # fails at "git-show-diff at line N"

The bisect harness that established the facts above lived in the session scratchpad; its
method: rebuild the model with the fuzz's exact fold, then call each `ed-pane-ops`
constituent (`ed-pane-spans` / `ed-diagnostic-overrides` / `ed-bracket-overrides` /
`ed-hl-ranges`) under `try`, print the predicate's inputs, and compare an inline copy of the
filter against the module-compiled call on identical values.

## Next step (Brood, prime directive)

This is a language-level correctness lead, not an editor bug: two compilations of the same
pure expression disagreeing on the same inputs. Hunt it in `../brood`'s JIT (map-shape
inline caches / closure capture under `filter`-inside-`mapcat`) with the fuzz session as
the warmup driver. Until then, `ed-diagnostic-overrides` is source-correct — do **not**
paper over it in the editor.
