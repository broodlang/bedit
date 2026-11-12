#!/bin/sh
# The test files a change reaches, one per line — and with --run, each run on its own.
#
# A change in one module shows up in the tests of modules that never name it (a registry row,
# a keymap, a which-key panel), so the tests of the touched files are not enough: CI went red
# on 2026-11-10 on four things none of them covered. The selection:
#   - every changed tests/*_test.blsp
#   - src/foo-bar.blsp → tests/foo_bar_test.blsp when it exists
#   - every test file that names a changed module: `(:use mod`, `(:use-internals mod`, or a
#     qualified `mod/name` reference
#   - any src/ change → the registry pins and the guards (tests/registries_test.blsp,
#     tests/guards_test.blsp), which every registration reaches
#   - a tests/support/ change → every test file that `:use`s it
#
# The change set is the commits ahead of the upstream and the working tree (staged, unstaged,
# untracked). `--files` reads it from stdin instead, one path per line. `--run` runs each
# selected file by itself (`nest test FILE`, headless), says ok or FAIL per file with the
# failures, and exits non-zero when any failed — the sweep before a push, never the whole
# suite at once.
#
#   tools/affected-tests.sh                 # list
#   tools/affected-tests.sh --run           # run them, one file at a time
#   git diff --name-only HEAD~3 | tools/affected-tests.sh --files --run
set -u
cd "$(git rev-parse --show-toplevel)" || exit 1

from_stdin=0
run=0
for argument in "$@"; do
    case "$argument" in
        --files) from_stdin=1 ;;
        --run) run=1 ;;
        *) echo "affected-tests: unknown argument $argument" >&2; exit 2 ;;
    esac
done

if [ "$from_stdin" -eq 1 ]; then
    changed=$(cat)
else
    upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo origin/main)
    changed=$( { git diff --name-only "$upstream..HEAD" 2>/dev/null; \
                 git diff --name-only HEAD 2>/dev/null; \
                 git diff --name-only --cached 2>/dev/null; \
                 git ls-files --others --exclude-standard 2>/dev/null; } | sort -u )
fi

selected=""
add() { [ -f "$1" ] && case " $selected " in *" $1 "*) ;; *) selected="$selected $1" ;; esac; }

# the test files that name module `$1`
naming() {
    grep -lE "\((:use|:use-internals) $1([ )]|$)|[ ('\`]$1/[a-z*]" tests/*_test.blsp 2>/dev/null
}

src_changed=0
for path in $(printf '%s\n' "$changed" | grep -E '\.blsp$'); do
    case "$path" in
        tests/support/*)
            module=$(basename "$path" .blsp)
            for test_file in $(naming "$module"); do add "$test_file"; done ;;
        tests/*_test.blsp)
            add "$path" ;;
        src/*)
            src_changed=1
            module=$(basename "$path" .blsp)
            add "tests/$(echo "$module" | tr '-' '_')_test.blsp"
            for test_file in $(naming "$module"); do add "$test_file"; done ;;
    esac
done
if [ "$src_changed" -eq 1 ]; then
    add tests/registries_test.blsp
    add tests/guards_test.blsp
fi

if [ "$run" -eq 0 ]; then
    for test_file in $selected; do echo "$test_file"; done
    exit 0
fi

failed=0
total=0
for test_file in $selected; do
    total=$((total + 1))
    output=$(BROOD_GUI_HEADLESS=1 nest test "$test_file" 2>&1)
    if printf '%s\n' "$output" | grep -qE '^[0-9]+ tests?, .* 0 failed'; then
        echo "ok   $test_file"
    else
        failed=$((failed + 1))
        echo "FAIL $test_file"
        printf '%s\n' "$output" | grep -E 'test failed|assert:|actual:|expect:|error' | head -12 | sed 's/^/     /'
    fi
done
# the docstring examples of the changed src/ modules (`nest doctest FILE.blsp`, brood ADR-716): an
# example a module's own test file never runs; skipped, and said, on a nest without it
doc_files=$(printf '%s\n' "$changed" | grep -E '^src/.*\.blsp$' | while read -r path; do [ -f "$path" ] && echo "$path"; done)
if [ -n "$doc_files" ]; then
    # shellcheck disable=SC2086
    doc_output=$(BROOD_GUI_HEADLESS=1 nest doctest $doc_files 2>&1)
    if printf '%s\n' "$doc_output" | grep -q '^Usage: nest doctest'; then
        echo "skip doc examples (this nest's doctest takes no source files)"
    elif printf '%s\n' "$doc_output" | grep -qE ' 0 failing example'; then
        echo "ok   doc examples of $(echo $doc_files | wc -w) src file(s)"
    else
        failed=$((failed + 1))
        echo "FAIL doc examples"
        printf '%s\n' "$doc_output" | grep -E '^src/|failing' | head -12 | sed 's/^/     /'
    fi
fi
echo "affected-tests: $total files, $failed failed"
[ "$failed" -eq 0 ]
