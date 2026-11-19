#!/usr/bin/env bash
# Deploy the build to every host named on the command line.
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ comment
set -euo pipefail
# ^ function

readonly TARGET="${DEPLOY_TARGET:-/srv/app}"
# ^^^^^^ keyword
#               ^ string
count=0

log() {
  local level="$1"
  # ^^^ keyword
  shift
  printf '%s [%s] %s\n' "$(date +%T)" "$level" "$*"
  # ^^^^ function
}

deploy_host() {
  local host="$1"
  if ! ssh "$host" true; then
    log error "cannot reach $host"
    return 1
  elif [[ -z "$TARGET" ]]; then
    return 2
  else
    rsync -a build/ "$host:$TARGET"
    # ^^^ function
  fi
  case "$host" in
    *.staging)
      log info "staging host"
      ;;
    *)
      log info "production host"
      ;;
  esac
}

for host in "$@"; do
  deploy_host "$host" && count=$((count + 1))
done

while read -r line; do
  echo "$line"
  # ^^ function
done < /etc/hosts

cat <<EOT
deployed to $count hosts
EOT
