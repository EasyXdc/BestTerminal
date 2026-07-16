#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_FILE="$STATE_HOME/best-terminal/state"
ZSHRC="$(state_value "$STATE_FILE" ZSHRC_TARGET 2>/dev/null || printf '%s/.zshrc' "${ZDOTDIR:-$HOME}")"
STARSHIP_CONFIG_FILE="$(state_value "$STATE_FILE" STARSHIP_TARGET 2>/dev/null || printf '%s/starship.toml' "$CONFIG_HOME")"
GHOSTTY_CONFIG_FILE="$(state_value "$STATE_FILE" GHOSTTY_TARGET 2>/dev/null || printf '%s/ghostty/config' "$CONFIG_HOME")"
FAILURES=0
WARNINGS=0

check_command() {
  local name="$1"
  local required="${2:-0}"
  if command_exists "$name"; then
    success "$name: $(command -v "$name")"
  elif [[ "$required" == "1" ]]; then
    warn "$name is missing"
    FAILURES=$((FAILURES + 1))
  else
    warn "$name is not installed (optional)"
    WARNINGS=$((WARNINGS + 1))
  fi
}

info "Core components"
if [[ -d /Applications/Ghostty.app || -d "$HOME/Applications/Ghostty.app" ]] || command_exists ghostty; then
  success "Ghostty is installed"
else
  warn "Ghostty is missing"
  FAILURES=$((FAILURES + 1))
fi
check_command starship 1
check_command zsh 1

font_found=0
for font_file in "$HOME"/Library/Fonts/MapleMono*NF* /Library/Fonts/MapleMono*NF*; do
  if [[ -e "$font_file" ]]; then
    font_found=1
    break
  fi
done
if [[ "$font_found" == "1" ]]; then
  success "Maple Mono Nerd Font is installed"
else
  warn "Maple Mono Nerd Font is missing"
  FAILURES=$((FAILURES + 1))
fi
unset font_file font_found

info "Optional tools"
for tool in fzf zoxide eza bat yazi; do
  check_command "$tool"
done

info "Configuration"
if [[ -f "$ZSHRC" ]] && grep -Fq "$BEST_TERMINAL_ZSH_START" "$ZSHRC"; then
  success "zsh integration is installed"
  if ! /bin/zsh -n "$ZSHRC"; then
    warn "$ZSHRC has a syntax error"
    FAILURES=$((FAILURES + 1))
  fi
else
  warn "BestTerminal block is missing from $ZSHRC"
  FAILURES=$((FAILURES + 1))
fi

if [[ -f "$STARSHIP_CONFIG_FILE" ]]; then
  if command_exists starship && ! TERM=xterm-256color STARSHIP_CONFIG="$STARSHIP_CONFIG_FILE" starship prompt --status=0 >/dev/null; then
    warn "Starship cannot parse $STARSHIP_CONFIG_FILE"
    FAILURES=$((FAILURES + 1))
  else
    success "Starship configuration is valid"
  fi
else
  warn "Starship configuration is missing: $STARSHIP_CONFIG_FILE"
  FAILURES=$((FAILURES + 1))
fi

if [[ -f "$GHOSTTY_CONFIG_FILE" ]]; then
  ghostty_bin=""
  if command_exists ghostty; then
    ghostty_bin="$(command -v ghostty)"
  elif [[ -x /Applications/Ghostty.app/Contents/MacOS/ghostty ]]; then
    ghostty_bin=/Applications/Ghostty.app/Contents/MacOS/ghostty
  fi
  if [[ -n "$ghostty_bin" ]] && ! "$ghostty_bin" +validate-config --config-file="$GHOSTTY_CONFIG_FILE"; then
    warn "Ghostty cannot parse $GHOSTTY_CONFIG_FILE"
    FAILURES=$((FAILURES + 1))
  else
    success "Ghostty configuration is present and valid"
  fi
else
  warn "Ghostty configuration is missing: $GHOSTTY_CONFIG_FILE"
  FAILURES=$((FAILURES + 1))
fi

printf '\nFailures: %d, optional warnings: %d\n' "$FAILURES" "$WARNINGS"
[[ "$FAILURES" -eq 0 ]]
