#!/usr/bin/env bash
# ^^^^^^^^^^^^^^^^^ comment
# deploy: build and ship
# ^^^^^^^^^^^^^^^^^^^^^^ comment
readonly ROOT="$(cd "$(dirname "$0")" && pwd)"
#              ^^ special
#                ^^ function

usage() {
  # ^ definition
  cat <<'USAGE'
usage: deploy [-n] TARGET
  -n   dry run
USAGE
# ^^^ string
}

function build {
  #      ^^^^^ definition
  local target=$1
  # ^^^ keyword
  if [[ -z $target ]]
  # <- keyword
  then
    usage
    return 1
  elif (( ${#target} > 9 )); then
    #                  ^ number
    echo long
  else
    echo "building $target"
    #     ^^^^^^^^^ string
    #              ^^^^^^^ special
  fi
  docker build \
    --tag "app:$target" \
    --file Dockerfile .
  find . -name '*.tmp' |
    #          ^^^^^^^ string
    xargs rm -f
    # ^^^ function
  while read -r line; do
    echo "$line"
  done <"$ROOT/list"
  for f in *.sh
  do
    (
      cd "$f" || exit
      make
    )
  done
  case "$target" in
    prod | staging)
      echo "remote"
      ;;
    *)
      echo "local"
      ;;
  esac
  # ^^ keyword
  files=(
    # ^ special
    a.txt
    b.txt
  )
  msg="line one
line two"
  echo "$msg" $((1 + 2))
}

build "$@"
