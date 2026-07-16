#!/usr/bin/env bash

set -euo pipefail

REPOSITORY="EasyXdc/BestTerminal"
BRANCH="${BEST_TERMINAL_BRANCH:-main}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/scripts/install.sh" ]]; then
  exec /bin/bash "$SCRIPT_DIR/scripts/install.sh" "$@"
fi

command -v curl >/dev/null 2>&1 || {
  printf 'ERROR curl is required to download BestTerminal.\n' >&2
  exit 1
}
command -v tar >/dev/null 2>&1 || {
  printf 'ERROR tar is required to unpack BestTerminal.\n' >&2
  exit 1
}

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/best-terminal.XXXXXX")"
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

ARCHIVE_URL="https://github.com/${REPOSITORY}/archive/refs/heads/${BRANCH}.tar.gz"
printf '==> Downloading BestTerminal (%s)\n' "$BRANCH"
curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
  "$ARCHIVE_URL" | tar -xz -C "$TEMP_DIR"

DOWNLOADED_ROOT="$TEMP_DIR/BestTerminal-$BRANCH"
[[ -f "$DOWNLOADED_ROOT/scripts/install.sh" ]] || {
  printf 'ERROR The downloaded archive does not contain the installer.\n' >&2
  exit 1
}

/bin/bash "$DOWNLOADED_ROOT/scripts/install.sh" "$@"
