#!/usr/bin/env bash
# Print the top of a bedit GitHub Release: how to install that version without Brood. The
# release workflow puts it above GitHub's generated list of changes; run it by hand to fix
# an old release:
#   gh release edit TAG --notes-file <(scripts/release-notes.sh TAG)
set -euo pipefail

tag="${1:?usage: release-notes.sh TAG}"

cat <<NOTES
## Install

One file, with its own Brood runtime inside: nothing else to install. Linux (x86_64 and
arm64) and macOS (Apple Silicon):

\`\`\`sh
curl -fsSL https://raw.githubusercontent.com/broodlang/bedit/main/scripts/install.sh | BEDIT_VERSION=$tag sh
\`\`\`

It installs \`bedit\` into \`~/.local/bin\` (and, on Linux, the app-menu entry). Leave out
\`BEDIT_VERSION\` to get the newest release. Then run \`bedit\`, or \`bedit notes.txt\`.

By hand: take \`bedit-<target>.tar.gz\` below, unpack it, and put the one file on your
\`PATH\` as \`bedit\`. On macOS, a file downloaded by a browser needs
\`xattr -d com.apple.quarantine bedit\` before it will open.
NOTES
