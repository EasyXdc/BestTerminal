#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

VERSION="2.0.0"
ASSUME_YES=0
DRY_RUN=0
MINIMAL=0
FORCE_CONFIG=0
INSTALL_PACKAGES=1
INSTALL_GHOSTTY=1
INSTALL_FONT=1
CREATE_BACKUP=1

usage() {
  cat <<'EOF'
BestTerminal installer

Usage: ./install.sh [options]

Options:
  -y, --yes             Run non-interactively and accept installation prompts
      --dry-run         Show detected changes without modifying the system
      --minimal         Install only Ghostty, Starship, and Maple Mono NF
      --config-only     Configure the shell and terminal without package installs
      --force-config    Replace Starship config even when the user modified it
      --skip-ghostty    Do not install or configure Ghostty
      --skip-font       Do not install Maple Mono NF
      --no-backup       Do not create a timestamped backup
  -h, --help            Show this help
      --version         Print the installer version

The default mode is incremental: existing packages and user-owned settings are
preserved, while missing packages and configuration keys are added.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      ASSUME_YES=1
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --minimal)
      MINIMAL=1
      ;;
    --config-only|--no-packages)
      INSTALL_PACKAGES=0
      ;;
    --force-config)
      FORCE_CONFIG=1
      ;;
    --skip-ghostty)
      INSTALL_GHOSTTY=0
      ;;
    --skip-font)
      INSTALL_FONT=0
      ;;
    --no-backup)
      CREATE_BACKUP=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --version)
      printf 'BestTerminal installer %s\n' "$VERSION"
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
  shift
done

[[ "$(uname -s)" == "Darwin" || "${BEST_TERMINAL_ALLOW_UNSUPPORTED:-0}" == "1" ]] || \
  fail "BestTerminal currently supports macOS only."

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
MANAGED_DIR="$CONFIG_HOME/best-terminal"
STATE_DIR="$STATE_HOME/best-terminal"
STATE_FILE="$STATE_DIR/state"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
ZPROFILE="${ZDOTDIR:-$HOME}/.zprofile"
STARSHIP_CONFIG_FILE="${STARSHIP_CONFIG:-$CONFIG_HOME/starship.toml}"
APPLICATIONS_DIR="${BEST_TERMINAL_APPLICATIONS_DIR:-/Applications}"
SYSTEM_FONT_DIR="${BEST_TERMINAL_SYSTEM_FONT_DIR:-/Library/Fonts}"

if [[ -n "${XDG_CONFIG_HOME:-}" || -e "$CONFIG_HOME/ghostty/config" ]]; then
  GHOSTTY_CONFIG_FILE="$CONFIG_HOME/ghostty/config"
elif [[ -e "$HOME/Library/Application Support/com.mitchellh.ghostty/config" ]]; then
  GHOSTTY_CONFIG_FILE="$HOME/Library/Application Support/com.mitchellh.ghostty/config"
else
  GHOSTTY_CONFIG_FILE="$CONFIG_HOME/ghostty/config"
fi

BREW_BIN=""
MISSING_FORMULAE=()
MISSING_CASKS=()
BACKUP_DIR=""
STARSHIP_MANAGED_SHA="$(state_value "$STATE_FILE" STARSHIP_MANAGED_SHA 2>/dev/null || true)"
STARSHIP_CREATED="$(state_value "$STATE_FILE" STARSHIP_CREATED 2>/dev/null || printf '0')"
STARSHIP_RESTORE="$(state_value "$STATE_FILE" STARSHIP_RESTORE 2>/dev/null || true)"

find_brew() {
  if [[ -n "${BEST_TERMINAL_BREW_BIN:-}" ]]; then
    [[ ! -x "$BEST_TERMINAL_BREW_BIN" ]] || BREW_BIN="$BEST_TERMINAL_BREW_BIN"
  elif command_exists brew; then
    BREW_BIN="$(command -v brew)"
  elif [[ -x /opt/homebrew/bin/brew ]]; then
    BREW_BIN=/opt/homebrew/bin/brew
  elif [[ -x /usr/local/bin/brew ]]; then
    BREW_BIN=/usr/local/bin/brew
  fi
}

brew_formula_installed() {
  local formula="$1"
  [[ -n "$BREW_BIN" ]] && "$BREW_BIN" list --formula "$formula" >/dev/null 2>&1
}

brew_cask_installed() {
  local cask="$1"
  [[ -n "$BREW_BIN" ]] && "$BREW_BIN" list --cask "$cask" >/dev/null 2>&1
}

plugin_file_exists() {
  local plugin="$1"
  local candidate
  for candidate in \
    "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin/$plugin.zsh" \
    "$HOME/.zsh/$plugin/$plugin.zsh" \
    "/opt/homebrew/share/$plugin/$plugin.zsh" \
    "/usr/local/share/$plugin/$plugin.zsh"; do
    [[ -r "$candidate" ]] && return 0
  done
  return 1
}

zsh_completions_present() {
  [[ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-completions" ]] ||
    [[ -d "$HOME/.zsh/zsh-completions" ]] ||
    brew_formula_installed zsh-completions
}

formula_present() {
  local formula="$1"
  case "$formula" in
    starship|fzf|zoxide|eza|bat|yazi)
      command_exists "$formula" || brew_formula_installed "$formula"
      ;;
    zsh-autosuggestions|zsh-syntax-highlighting)
      plugin_file_exists "$formula" || brew_formula_installed "$formula"
      ;;
    zsh-completions)
      zsh_completions_present
      ;;
    *)
      brew_formula_installed "$formula"
      ;;
  esac
}

ghostty_present() {
  [[ -d "$APPLICATIONS_DIR/Ghostty.app" ]] || [[ -d "$HOME/Applications/Ghostty.app" ]] ||
    command_exists ghostty || brew_cask_installed ghostty
}

font_present() {
  local candidate
  for candidate in \
    "$HOME"/Library/Fonts/MapleMono*NF* \
    "$SYSTEM_FONT_DIR"/MapleMono*NF*; do
    [[ -e "$candidate" ]] && return 0
  done
  brew_cask_installed font-maple-mono-nf
}

collect_missing_packages() {
  local formula
  local formulae=(starship)

  if [[ "$MINIMAL" == "0" ]]; then
    formulae+=(fzf zoxide eza bat yazi zsh-autosuggestions zsh-syntax-highlighting zsh-completions)
  fi

  for formula in "${formulae[@]}"; do
    formula_present "$formula" || MISSING_FORMULAE+=("$formula")
  done

  if [[ "$INSTALL_GHOSTTY" == "1" ]] && ! ghostty_present; then
    MISSING_CASKS+=(ghostty)
  fi
  if [[ "$INSTALL_FONT" == "1" ]] && ! font_present; then
    MISSING_CASKS+=(font-maple-mono-nf)
  fi
}

print_plan() {
  info "BestTerminal $VERSION installation plan"
  if [[ "$INSTALL_PACKAGES" == "0" ]]; then
    printf '  Packages: skipped (--config-only)\n'
  elif [[ ${#MISSING_FORMULAE[@]} -eq 0 && ${#MISSING_CASKS[@]} -eq 0 ]]; then
    printf '  Packages: all requested components already exist\n'
  else
    [[ ${#MISSING_FORMULAE[@]} -eq 0 ]] || printf '  Formulae: %s\n' "${MISSING_FORMULAE[*]}"
    [[ ${#MISSING_CASKS[@]} -eq 0 ]] || printf '  Casks:    %s\n' "${MISSING_CASKS[*]}"
    [[ -n "$BREW_BIN" ]] || printf '  Homebrew: install because it is missing\n'
  fi
  printf '  zsh:      manage one source block in %s\n' "$ZSHRC"
  printf '  Starship: preserve user changes unless --force-config is used\n'
  if [[ "$INSTALL_GHOSTTY" == "1" ]]; then
    printf '  Ghostty:  add only configuration keys not already defined\n'
  else
    printf '  Ghostty:  skipped\n'
  fi
}

install_homebrew() {
  if [[ -n "$BREW_BIN" ]]; then
    return
  fi

  info "Homebrew is missing; installing it first"
  command_exists curl || fail "curl is required to install Homebrew."
  if [[ "$ASSUME_YES" == "1" ]]; then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  find_brew
  [[ -n "$BREW_BIN" ]] || fail "Homebrew installation finished but brew was not found."
}

install_missing_packages() {
  local formula
  local cask

  [[ "$INSTALL_PACKAGES" == "1" ]] || return 0
  [[ ${#MISSING_FORMULAE[@]} -gt 0 || ${#MISSING_CASKS[@]} -gt 0 ]] || return 0

  install_homebrew
  eval "$("$BREW_BIN" shellenv)"

  if [[ ${#MISSING_FORMULAE[@]} -gt 0 ]]; then
    info "Installing missing formulae: ${MISSING_FORMULAE[*]}"
    if ! HOMEBREW_CURL_RETRIES=5 "$BREW_BIN" install "${MISSING_FORMULAE[@]}"; then
      warn "Batch installation failed; retrying each missing formula separately."
      for formula in "${MISSING_FORMULAE[@]}"; do
        formula_present "$formula" || HOMEBREW_CURL_RETRIES=5 "$BREW_BIN" install "$formula"
      done
    fi
  fi

  for cask in "${MISSING_CASKS[@]}"; do
    info "Installing missing cask: $cask"
    HOMEBREW_CURL_RETRIES=5 "$BREW_BIN" install --cask "$cask"
  done
}

create_backup() {
  local timestamp

  [[ "$CREATE_BACKUP" == "1" ]] || return 0
  timestamp="$(date +%Y%m%d_%H%M%S)"
  BACKUP_DIR="$STATE_DIR/backups/$timestamp"
  if [[ -e "$BACKUP_DIR" ]]; then
    local suffix=1
    while [[ -e "${BACKUP_DIR}_$suffix" ]]; do
      suffix=$((suffix + 1))
    done
    BACKUP_DIR="${BACKUP_DIR}_$suffix"
  fi
  mkdir -p "$BACKUP_DIR"
  backup_path "$ZSHRC" "$BACKUP_DIR" zshrc
  backup_path "$ZPROFILE" "$BACKUP_DIR" zprofile
  backup_path "$STARSHIP_CONFIG_FILE" "$BACKUP_DIR" starship.toml
  backup_path "$GHOSTTY_CONFIG_FILE" "$BACKUP_DIR" ghostty-config
  backup_path "$STATE_FILE" "$BACKUP_DIR" previous-state
  {
    printf 'created_at=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
    printf 'zshrc=%s\n' "$ZSHRC"
    printf 'starship=%s\n' "$STARSHIP_CONFIG_FILE"
    printf 'ghostty=%s\n' "$GHOSTTY_CONFIG_FILE"
  } >"$BACKUP_DIR/manifest"
  success "Backup created at $BACKUP_DIR"
}

remove_known_blocks() {
  local source_file="$1"
  local output_file="$2"
  local work_a="$TEMP_DIR/block-a"
  local work_b="$TEMP_DIR/block-b"

  cp "$source_file" "$work_a"
  strip_managed_block "$work_a" "$work_b" "$BEST_TERMINAL_ZSH_START" "$BEST_TERMINAL_ZSH_END"
  strip_managed_block "$work_b" "$work_a" "# >>> ghostty-terminal-config >>>" "# <<< ghostty-terminal-config <<<"
  strip_managed_block "$work_a" "$work_b" "# >>> ghostty-starship-tools >>>" "# <<< ghostty-starship-tools <<<"
  trim_trailing_blank_lines "$work_b" "$output_file"
}

configure_zsh() {
  local base="$TEMP_DIR/zshrc-base"
  local next="$TEMP_DIR/zshrc-next"

  mkdir -p "$MANAGED_DIR/zsh"
  atomic_install "$PROJECT_ROOT/config/zsh/init.zsh" "$MANAGED_DIR/zsh/init.zsh"

  if [[ -f "$ZSHRC" ]]; then
    remove_known_blocks "$ZSHRC" "$base"
  else
    : >"$base"
  fi

  cp "$base" "$next"
  [[ ! -s "$next" ]] || printf '\n' >>"$next"
  {
    printf '%s\n' "$BEST_TERMINAL_ZSH_START"
    # This is intentionally evaluated by zsh when it reads the generated file.
    # shellcheck disable=SC2016
    printf '[[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/best-terminal/zsh/init.zsh" ]] && source "${XDG_CONFIG_HOME:-$HOME/.config}/best-terminal/zsh/init.zsh"\n'
    printf '%s\n' "$BEST_TERMINAL_ZSH_END"
  } >>"$next"

  if [[ ! -f "$ZSHRC" ]] || ! cmp -s "$ZSHRC" "$next"; then
    atomic_install "$next" "$ZSHRC"
    success "Updated $ZSHRC"
  else
    success "$ZSHRC is already current"
  fi
}

configure_brew_shellenv() {
  local base="$TEMP_DIR/zprofile-base"
  local next="$TEMP_DIR/zprofile-next"

  [[ "$BREW_BIN" == /opt/homebrew/bin/brew ]] || return 0
  if [[ -f "$ZPROFILE" ]]; then
    strip_managed_block "$ZPROFILE" "$base" "$BEST_TERMINAL_BREW_START" "$BEST_TERMINAL_BREW_END"
  else
    : >"$base"
  fi
  if grep -Eq '/opt/homebrew/bin/brew[[:space:]]+shellenv|brew shellenv' "$base"; then
    return
  fi
  trim_trailing_blank_lines "$base" "$next"
  [[ ! -s "$next" ]] || printf '\n' >>"$next"
  {
    printf '%s\n' "$BEST_TERMINAL_BREW_START"
    # This is intentionally evaluated by the generated zprofile.
    # shellcheck disable=SC2016
    printf 'eval "$(/opt/homebrew/bin/brew shellenv)"\n'
    printf '%s\n' "$BEST_TERMINAL_BREW_END"
  } >>"$next"
  atomic_install "$next" "$ZPROFILE"
  success "Added Homebrew shell environment to $ZPROFILE"
}

configure_ghostty() {
  local base="$TEMP_DIR/ghostty-base"
  local next="$TEMP_DIR/ghostty-next"
  local template="$PROJECT_ROOT/config/ghostty/config"
  local line
  local key
  local added=0

  [[ "$INSTALL_GHOSTTY" == "1" ]] || return 0
  if [[ -f "$GHOSTTY_CONFIG_FILE" ]]; then
    strip_managed_block "$GHOSTTY_CONFIG_FILE" "$base" "$BEST_TERMINAL_GHOSTTY_START" "$BEST_TERMINAL_GHOSTTY_END"
  else
    : >"$base"
  fi
  trim_trailing_blank_lines "$base" "$next"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*([A-Za-z0-9_-]+)[[:space:]]*= ]]; then
      key="${BASH_REMATCH[1]}"
      if ! contains_assignment "$base" "$key"; then
        if [[ "$added" == "0" ]]; then
          [[ ! -s "$next" ]] || printf '\n' >>"$next"
          printf '%s\n' "$BEST_TERMINAL_GHOSTTY_START" >>"$next"
          added=1
        fi
        printf '%s\n' "$line" >>"$next"
      fi
    fi
  done <"$template"
  if [[ "$added" == "1" ]]; then
    printf '%s\n' "$BEST_TERMINAL_GHOSTTY_END" >>"$next"
  fi

  if [[ ! -f "$GHOSTTY_CONFIG_FILE" ]] || ! cmp -s "$GHOSTTY_CONFIG_FILE" "$next"; then
    atomic_install "$next" "$GHOSTTY_CONFIG_FILE"
    success "Merged missing defaults into $GHOSTTY_CONFIG_FILE"
  else
    success "Ghostty configuration already contains every requested key"
  fi
}

configure_starship() {
  local template="$PROJECT_ROOT/config/starship/starship.toml"
  local template_sha
  local current_sha=""
  local should_install=0

  template_sha="$(sha256_file "$template")"
  [[ ! -f "$STARSHIP_CONFIG_FILE" ]] || current_sha="$(sha256_file "$STARSHIP_CONFIG_FILE")"

  if [[ ! -f "$STARSHIP_CONFIG_FILE" ]]; then
    should_install=1
    STARSHIP_CREATED=1
  elif [[ "$FORCE_CONFIG" == "1" ]]; then
    should_install=1
    if [[ -z "$STARSHIP_RESTORE" && -n "$BACKUP_DIR" && -f "$BACKUP_DIR/starship.toml" ]]; then
      STARSHIP_RESTORE="$BACKUP_DIR/starship.toml"
    fi
  elif [[ "$current_sha" == "$template_sha" ]]; then
    STARSHIP_MANAGED_SHA="$template_sha"
    success "Starship configuration already matches the project template"
  elif [[ -n "$STARSHIP_MANAGED_SHA" && "$current_sha" == "$STARSHIP_MANAGED_SHA" ]]; then
    should_install=1
  else
    warn "Preserving user-owned Starship config: $STARSHIP_CONFIG_FILE"
    warn "Use --force-config to replace it with the BestTerminal theme."
  fi

  if [[ "$should_install" == "1" ]]; then
    atomic_install "$template" "$STARSHIP_CONFIG_FILE"
    STARSHIP_MANAGED_SHA="$template_sha"
    success "Installed Starship configuration at $STARSHIP_CONFIG_FILE"
  fi
}

write_state() {
  local next="$TEMP_DIR/state-next"

  mkdir -p "$STATE_DIR"
  {
    printf 'VERSION=%s\n' "$VERSION"
    printf 'STARSHIP_MANAGED_SHA=%s\n' "$STARSHIP_MANAGED_SHA"
    printf 'STARSHIP_CREATED=%s\n' "$STARSHIP_CREATED"
    printf 'STARSHIP_RESTORE=%s\n' "$STARSHIP_RESTORE"
    printf 'STARSHIP_TARGET=%s\n' "$STARSHIP_CONFIG_FILE"
    printf 'GHOSTTY_TARGET=%s\n' "$GHOSTTY_CONFIG_FILE"
    printf 'ZSHRC_TARGET=%s\n' "$ZSHRC"
  } >"$next"
  atomic_install "$next" "$STATE_FILE"
}

validate_installation() {
  local ghostty_bin=""

  /bin/zsh -n "$ZSHRC" || fail "zsh rejected $ZSHRC"

  if command_exists starship && [[ -f "$STARSHIP_CONFIG_FILE" ]]; then
    TERM=xterm-256color STARSHIP_CONFIG="$STARSHIP_CONFIG_FILE" starship prompt --status=0 >/dev/null
  fi

  if command_exists ghostty; then
    ghostty_bin="$(command -v ghostty)"
  elif [[ -x "$APPLICATIONS_DIR/Ghostty.app/Contents/MacOS/ghostty" ]]; then
    ghostty_bin="$APPLICATIONS_DIR/Ghostty.app/Contents/MacOS/ghostty"
  elif [[ -x "$HOME/Applications/Ghostty.app/Contents/MacOS/ghostty" ]]; then
    ghostty_bin="$HOME/Applications/Ghostty.app/Contents/MacOS/ghostty"
  fi
  if [[ -n "$ghostty_bin" && "$INSTALL_GHOSTTY" == "1" ]]; then
    "$ghostty_bin" +validate-config --config-file="$GHOSTTY_CONFIG_FILE"
  fi
  success "Configuration validation passed"
}

find_brew
if [[ "$INSTALL_PACKAGES" == "1" ]]; then
  collect_missing_packages
fi
print_plan

if [[ "$DRY_RUN" == "1" ]]; then
  success "Dry run complete; no files or packages were changed"
  exit 0
fi

confirm "Apply this installation plan?" || {
  info "Installation cancelled"
  exit 0
}

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/best-terminal-install.XXXXXX")"
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

install_missing_packages
find_brew
create_backup
configure_brew_shellenv
configure_zsh
configure_starship
configure_ghostty
write_state
validate_installation

printf '\n'
success "BestTerminal installation is complete"
printf 'Restart Ghostty or run: exec zsh\n'
[[ -z "$BACKUP_DIR" ]] || printf 'Backup: %s\n' "$BACKUP_DIR"
