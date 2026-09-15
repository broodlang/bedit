#!/usr/bin/env bash
# tools/check-modes.sh — open one file of every lexical mode in the INSTALLED `bedit`, from
# $HOME, and fail if the view ever printed an error frame.
#
# Why from $HOME, and why the installed binary: a mode names its services by SYMBOL, resolved
# at render time. The model tests load every module, so a symbol whose module nothing loads
# on that path is bound there and unbound in the released editor — `render error: unbound
# symbol: editor/lexer/line-restart` on every frame of a shell buffer (2026-09-15), the X
# button dead behind it. Only the released binary, opened on a file of that mode with no
# project around it, shows the gap. `ed-view` prints every such failure to stdout.
#
#     make check-modes             # ~6 s per mode, needs a display (it opens the window)
#     BEDIT=./bedit tools/check-modes.sh
set -u
bedit=${BEDIT:-$HOME/.local/bin/bedit}
seconds=${SECONDS_PER_FILE:-6}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

printf 'export A=1 # c\nif [ -n "$A" ]; then echo ok; fi\nf() { :; }\n' > "$work/.bashrc"
printf 'FOO=bar\n# c\n' > "$work/.env"
printf 'FROM debian\nRUN apt-get update # c\n' > "$work/Dockerfile"
printf '{"a": 1, "b": [true, null], "c": "x"}\n' > "$work/x.json"
printf 'key: value\nlist:\n  - a: 1\n---\n' > "$work/x.yaml"
printf '[package]\nname = "x"\nversion = "1.0"\n' > "$work/x.toml"
printf 'all: build\n\tmake -C src\nCC := gcc\n' > "$work/Makefile"
printf '[core]\n\tautocrlf = false\n; c\n' > "$work/x.ini"
printf 'feat(x): subject\n\n# Please enter\n' > "$work/COMMIT_EDITMSG"
printf '# Title\n\nSome *text* and `code`.\n' > "$work/x.md"
printf '(defn f (x) (+ x 1))\n' > "$work/x.blsp"

fail=0
for f in .bashrc .env Dockerfile x.json x.yaml x.toml Makefile x.ini COMMIT_EDITMSG x.md x.blsp; do
  ( cd "$HOME" && timeout "$seconds" "$bedit" "$work/$f" > "$work/$f.log" 2>&1 )
  n=$(grep -c 'render error' "$work/$f.log")
  if [ "$n" -gt 0 ]; then
    echo "FAIL $f: $n render errors — $(grep -m1 'render error' "$work/$f.log")"
    fail=1
  elif ! grep -q 'bedit started' "$work/$f.log"; then
    echo "FAIL $f: the editor never started — $(head -c 200 "$work/$f.log")"
    fail=1
  else
    echo "ok   $f"
  fi
done
exit $fail
