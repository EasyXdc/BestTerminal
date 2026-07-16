#!/usr/bin/env bash

set -euo pipefail

# These constants are consumed by scripts that source this library.
# shellcheck disable=SC2034
BEST_TERMINAL_ZSH_START="# >>> BestTerminal >>>"
# shellcheck disable=SC2034
BEST_TERMINAL_ZSH_END="# <<< BestTerminal <<<"
# shellcheck disable=SC2034
BEST_TERMINAL_GHOSTTY_START="# >>> BestTerminal managed defaults >>>"
# shellcheck disable=SC2034
BEST_TERMINAL_GHOSTTY_END="# <<< BestTerminal managed defaults <<<"
# shellcheck disable=SC2034
BEST_TERMINAL_BREW_START="# >>> BestTerminal Homebrew >>>"
# shellcheck disable=SC2034
BEST_TERMINAL_BREW_END="# <<< BestTerminal Homebrew <<<"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  COLOR_BLUE=$'\033[34m'
  COLOR_GREEN=$'\033[32m'
  COLOR_YELLOW=$'\033[33m'
  COLOR_RED=$'\033[31m'
  COLOR_RESET=$'\033[0m'
else
  COLOR_BLUE=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_RED=""
  COLOR_RESET=""
fi

info() {
  printf '%s==>%s %s\n' "$COLOR_BLUE" "$COLOR_RESET" "$*"
}

success() {
  printf '%sOK%s  %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*"
}

warn() {
  printf '%sWARN%s %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$*" >&2
}

fail() {
  printf '%sERROR%s %s\n' "$COLOR_RED" "$COLOR_RESET" "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

confirm() {
  local prompt="$1"
  local answer

  if [[ "${ASSUME_YES:-0}" == "1" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    fail "$prompt Re-run with --yes in a non-interactive shell."
  fi
  printf '%s [y/N] ' "$prompt" >/dev/tty
  read -r answer </dev/tty
  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

strip_managed_block() {
  local source_file="$1"
  local output_file="$2"
  local start_marker="$3"
  local end_marker="$4"

  awk -v start="$start_marker" -v end="$end_marker" '
    $0 == start { inside = 1; found = 1; next }
    $0 == end {
      if (inside) { inside = 0; next }
    }
    !inside { print }
    END {
      if (inside) exit 42
    }
  ' "$source_file" >"$output_file" || {
    local status=$?
    if [[ "$status" -eq 42 ]]; then
      fail "Unclosed managed block in $source_file. Restore the end marker before continuing."
    fi
    return "$status"
  }
}

trim_trailing_blank_lines() {
  local source_file="$1"
  local output_file="$2"

  awk '
    { lines[NR] = $0 }
    END {
      end = NR
      while (end > 0 && lines[end] == "") end--
      for (i = 1; i <= end; i++) print lines[i]
    }
  ' "$source_file" >"$output_file"
}

resolve_write_target() {
  local target="$1"
  local link_target
  local depth=0

  while [[ -L "$target" ]]; do
    depth=$((depth + 1))
    [[ "$depth" -le 20 ]] || fail "Too many symbolic links while resolving $1"
    link_target="$(readlink "$target")"
    if [[ "$link_target" == /* ]]; then
      target="$link_target"
    else
      target="$(cd "$(dirname "$target")" && pwd -P)/$link_target"
    fi
  done
  printf '%s\n' "$target"
}

atomic_install() {
  local source_file="$1"
  local target_file="$2"
  local mode="${3:-0644}"
  local target_dir
  local temp_file

  target_file="$(resolve_write_target "$target_file")"
  target_dir="$(dirname "$target_file")"
  mkdir -p "$target_dir"
  temp_file="$(mktemp "$target_dir/.best-terminal.XXXXXX")"
  cp "$source_file" "$temp_file"
  chmod "$mode" "$temp_file"
  mv -f "$temp_file" "$target_file"
}

backup_path() {
  local source_path="$1"
  local backup_root="$2"
  local name="$3"

  if [[ -e "$source_path" || -L "$source_path" ]]; then
    mkdir -p "$backup_root"
    cp -pR "$source_path" "$backup_root/$name"
  fi
}

state_value() {
  local state_file="$1"
  local key="$2"

  [[ -f "$state_file" ]] || return 1
  awk -F= -v wanted="$key" '$1 == wanted { sub(/^[^=]*=/, ""); print; exit }' "$state_file"
}

contains_assignment() {
  local file="$1"
  local key="$2"

  awk -v wanted="$key" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=/ {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      split(line, parts, /[[:space:]]*=/)
      if (parts[1] == wanted) found = 1
    }
    END { exit(found ? 0 : 1) }
  ' "$file"
}
