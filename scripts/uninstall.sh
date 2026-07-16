#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

ASSUME_YES=0
DRY_RUN=0
KEEP_STARSHIP=0

usage() {
  cat <<'EOF'
Usage: ./uninstall.sh [options]

Options:
  -y, --yes          Run without confirmation
      --dry-run      Show managed files without changing them
      --keep-starship  Keep the current Starship configuration
  -h, --help         Show this help

Only BestTerminal-managed configuration is removed. Homebrew packages and
user-owned settings are never uninstalled.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --keep-starship) KEEP_STARSHIP=1 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
  shift
done

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
MANAGED_DIR="$CONFIG_HOME/best-terminal"
STATE_DIR="$STATE_HOME/best-terminal"
STATE_FILE="$STATE_DIR/state"
ZSHRC="$(state_value "$STATE_FILE" ZSHRC_TARGET 2>/dev/null || printf '%s/.zshrc' "${ZDOTDIR:-$HOME}")"
STARSHIP_CONFIG_FILE="$(state_value "$STATE_FILE" STARSHIP_TARGET 2>/dev/null || printf '%s/starship.toml' "$CONFIG_HOME")"
GHOSTTY_CONFIG_FILE="$(state_value "$STATE_FILE" GHOSTTY_TARGET 2>/dev/null || printf '%s/ghostty/config' "$CONFIG_HOME")"
STARSHIP_MANAGED_SHA="$(state_value "$STATE_FILE" STARSHIP_MANAGED_SHA 2>/dev/null || true)"
STARSHIP_CREATED="$(state_value "$STATE_FILE" STARSHIP_CREATED 2>/dev/null || printf '0')"
STARSHIP_RESTORE="$(state_value "$STATE_FILE" STARSHIP_RESTORE 2>/dev/null || true)"
ZPROFILE="${ZDOTDIR:-$HOME}/.zprofile"

info "BestTerminal uninstall plan"
printf '  Remove managed zsh block from: %s\n' "$ZSHRC"
printf '  Remove managed Ghostty defaults from: %s\n' "$GHOSTTY_CONFIG_FILE"
printf '  Remove managed shell integration: %s\n' "$MANAGED_DIR/zsh/init.zsh"
printf '  Homebrew packages: keep\n'

if [[ "$DRY_RUN" == "1" ]]; then
  success "Dry run complete; no files were changed"
  exit 0
fi

confirm "Remove BestTerminal-managed configuration?" || {
  info "Uninstall cancelled"
  exit 0
}

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/best-terminal-uninstall.XXXXXX")"
BACKUP_DIR="$STATE_DIR/backups/uninstall-$(date +%Y%m%d_%H%M%S)"
if [[ -e "$BACKUP_DIR" ]]; then
  suffix=1
  while [[ -e "${BACKUP_DIR}_$suffix" ]]; do
    suffix=$((suffix + 1))
  done
  BACKUP_DIR="${BACKUP_DIR}_$suffix"
fi
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

mkdir -p "$BACKUP_DIR"
backup_path "$ZSHRC" "$BACKUP_DIR" zshrc
backup_path "$ZPROFILE" "$BACKUP_DIR" zprofile
backup_path "$STARSHIP_CONFIG_FILE" "$BACKUP_DIR" starship.toml
backup_path "$GHOSTTY_CONFIG_FILE" "$BACKUP_DIR" ghostty-config
backup_path "$STATE_FILE" "$BACKUP_DIR" state

remove_block_from_file() {
  local target="$1"
  local start="$2"
  local end="$3"
  local stripped="$TEMP_DIR/stripped"
  local trimmed="$TEMP_DIR/trimmed"

  [[ -f "$target" ]] || return 0
  strip_managed_block "$target" "$stripped" "$start" "$end"
  trim_trailing_blank_lines "$stripped" "$trimmed"
  if ! cmp -s "$target" "$trimmed"; then
    atomic_install "$trimmed" "$target"
    success "Removed managed block from $target"
  fi
}

remove_block_from_file "$ZSHRC" "$BEST_TERMINAL_ZSH_START" "$BEST_TERMINAL_ZSH_END"
remove_block_from_file "$ZPROFILE" "$BEST_TERMINAL_BREW_START" "$BEST_TERMINAL_BREW_END"
remove_block_from_file "$GHOSTTY_CONFIG_FILE" "$BEST_TERMINAL_GHOSTTY_START" "$BEST_TERMINAL_GHOSTTY_END"

if [[ "$KEEP_STARSHIP" == "0" && -f "$STARSHIP_CONFIG_FILE" && -n "$STARSHIP_MANAGED_SHA" ]]; then
  current_sha="$(sha256_file "$STARSHIP_CONFIG_FILE")"
  if [[ "$current_sha" == "$STARSHIP_MANAGED_SHA" ]]; then
    if [[ -n "$STARSHIP_RESTORE" && -f "$STARSHIP_RESTORE" ]]; then
      atomic_install "$STARSHIP_RESTORE" "$STARSHIP_CONFIG_FILE"
      success "Restored the pre-install Starship configuration"
    elif [[ "$STARSHIP_CREATED" == "1" ]]; then
      rm -f "$STARSHIP_CONFIG_FILE"
      success "Removed the project-created Starship configuration"
    fi
  else
    warn "Starship config was modified after installation; preserving it."
  fi
fi

rm -f "$MANAGED_DIR/zsh/init.zsh"
rm -f "$STATE_FILE"
rmdir "$MANAGED_DIR/zsh" "$MANAGED_DIR" "$STATE_DIR" 2>/dev/null || true

success "BestTerminal-managed configuration was removed"
printf 'Backup: %s\n' "$BACKUP_DIR"
