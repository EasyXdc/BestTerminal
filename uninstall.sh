#!/usr/bin/env bash

set -euo pipefail

REPOSITORY="EasyXdc/BestTerminal"
BRANCH="${BEST_TERMINAL_BRANCH:-main}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/scripts/uninstall.sh" ]]; then
  exec /bin/bash "$SCRIPT_DIR/scripts/uninstall.sh" "$@"
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/best-terminal-uninstall.XXXXXX")"
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
  "https://github.com/${REPOSITORY}/archive/refs/heads/${BRANCH}.tar.gz" |
  tar -xz -C "$TEMP_DIR"

/bin/bash "$TEMP_DIR/BestTerminal-$BRANCH/scripts/uninstall.sh" "$@"
