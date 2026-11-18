#!/bin/sh
# bedit installer. Usage:
#   curl -fsSL https://raw.githubusercontent.com/broodlang/bedit/main/scripts/install.sh | sh
#
# Downloads the bedit binary for your OS/arch from the latest GitHub release, checks it
# against the release's .sha256, and installs it. The binary carries its own Brood runtime:
# nothing else needs installing. On Linux it also installs the desktop entry and icon, so
# bedit launches from the app menu with its own name. Override with env vars:
#   BEDIT_VERSION=v0.11.0      install a specific release (default: latest)
#   BEDIT_INSTALL_DIR=/path    install location (default: $HOME/.local/bin)
set -eu

REPO="broodlang/bedit"
INSTALL_DIR="${BEDIT_INSTALL_DIR:-$HOME/.local/bin}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"

say()  { printf '%s\n' "bedit-install: $*"; }
die()  { printf '%s\n' "bedit-install: error: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- detect platform ---------------------------------------------------------
os="$(uname -s)"
arch="$(uname -m)"
case "$os/$arch" in
  Linux/x86_64|Linux/amd64)   target="x86_64-unknown-linux-gnu" ;;
  Linux/aarch64|Linux/arm64)  target="aarch64-unknown-linux-gnu" ;;
  Darwin/arm64|Darwin/aarch64) target="aarch64-apple-darwin" ;;
  Darwin/x86_64) die "there is no Intel Mac build yet; build from source (see the README)" ;;
  *) die "there is no bedit build for $os on $arch; build from source (see the README)" ;;
esac

# --- download helpers --------------------------------------------------------
if have curl; then
  dl()  { curl -fsSL "$1"; }
  dlo() { curl -fsSL -o "$2" "$1"; }
elif have wget; then
  dl()  { wget -qO- "$1"; }
  dlo() { wget -qO "$2" "$1"; }
else
  die "need curl or wget"
fi

# --- resolve the version -----------------------------------------------------
version="${BEDIT_VERSION:-}"
if [ -z "$version" ]; then
  version="$(dl "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$version" ] || die "could not determine the latest release (set BEDIT_VERSION)"
fi

name="bedit-${target}"
url="https://github.com/${REPO}/releases/download/${version}/${name}.tar.gz"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
say "downloading bedit ${version} for ${target}…"
dlo "$url" "$tmp/pkg.tar.gz" || die "download failed: $url"

# The check is not optional: a sidecar that will not download, or no tool to hash with,
# stops the install rather than installing what nothing has checked.
dl "${url}.sha256" > "$tmp/pkg.sha256" 2>/dev/null && [ -s "$tmp/pkg.sha256" ] \
  || die "could not download ${url}.sha256 to check the archive against"
expected="$(cut -d' ' -f1 < "$tmp/pkg.sha256")"
if have sha256sum; then actual="$(sha256sum "$tmp/pkg.tar.gz" | cut -d' ' -f1)"
elif have shasum;   then actual="$(shasum -a 256 "$tmp/pkg.tar.gz" | cut -d' ' -f1)"
else die "need sha256sum or shasum to check the download"; fi
[ "$expected" = "$actual" ] || die "checksum mismatch (expected $expected, got $actual)"
say "checksum ok"

# --- install -----------------------------------------------------------------
tar -C "$tmp" -xzf "$tmp/pkg.tar.gz"
mkdir -p "$INSTALL_DIR"
install -m 0755 "$tmp/${name}" "$INSTALL_DIR/bedit"
say "installed bedit ${version} to ${INSTALL_DIR}/bedit"

# The desktop entry names the window in the dash and alt-tab. Its Exec= is the installed
# path: a desktop launch does not inherit a login shell's PATH. Advisory: a failure here
# leaves a working bedit, so it warns and goes on.
if [ "$os" = Linux ]; then
  raw="https://raw.githubusercontent.com/${REPO}/${version}/assets"
  apps="$DATA_DIR/applications"
  icons="$DATA_DIR/icons/hicolor/scalable/apps"
  if mkdir -p "$apps" "$icons" \
     && dlo "$raw/bedit.svg" "$icons/bedit.svg" \
     && dl "$raw/bedit.desktop" | sed "s|^Exec=bedit|Exec=$INSTALL_DIR/bedit|" > "$apps/bedit.desktop"; then
    have update-desktop-database && update-desktop-database "$apps" >/dev/null 2>&1 || true
    have gtk-update-icon-cache && gtk-update-icon-cache -qtf "$DATA_DIR/icons/hicolor" >/dev/null 2>&1 || true
    say "installed the desktop entry: bedit is in your app menu"
  else
    say "could not install the desktop entry; bedit itself is installed"
  fi
fi

# --- PATH hint ---------------------------------------------------------------
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) say "add it to your PATH:  export PATH=\"$INSTALL_DIR:\$PATH\"" ;;
esac
"$INSTALL_DIR/bedit" --version 2>/dev/null || true
say "done — run:  bedit   (or bedit notes.txt)"
