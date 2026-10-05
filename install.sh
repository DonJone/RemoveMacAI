#!/bin/bash
# RemoveMacAI: turn Apple Intelligence off on macOS and delete its models.
#
#   curl -fsSL https://raw.githubusercontent.com/omlahore/RemoveMacAI/main/install.sh | bash
#
# Undo everything later with the same line plus "-s revert":
#
#   curl -fsSL https://raw.githubusercontent.com/omlahore/RemoveMacAI/main/install.sh | bash -s revert
#
# It downloads the latest release, checks its SHA-256, runs it from a temporary
# folder and deletes it afterwards. Nothing is installed.
set -euo pipefail

self="curl -fsSL https://raw.githubusercontent.com/omlahore/RemoveMacAI/main/install.sh | bash"
base="${REMOVEMACAI_URL:-https://github.com/omlahore/RemoveMacAI/releases/latest/download}"
asset="removemacai-darwin-arm64.tar.gz"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "RemoveMacAI is for macOS." >&2
  exit 1
fi
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" != "1" ]; then
  echo "Apple Intelligence only runs on Apple silicon Macs, so there is nothing to remove here." >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "$base/$asset" -o "$tmp/$asset"
curl -fsSL "$base/$asset.sha256" -o "$tmp/$asset.sha256"
expected="$(awk '{print $1}' "$tmp/$asset.sha256")"
actual="$(shasum -a 256 "$tmp/$asset" | awk '{print $1}')"
if [ "$expected" != "$actual" ]; then
  echo "The download does not match its checksum, so it was not run." >&2
  exit 1
fi
tar -xzf "$tmp/$asset" -C "$tmp"

export REMOVEMACAI_UNDO="$self -s revert"
if (exec < /dev/tty) 2>/dev/null; then
  "$tmp/removemacai" "$@" < /dev/tty
else
  "$tmp/removemacai" "$@"
fi
