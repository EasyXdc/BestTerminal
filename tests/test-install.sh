#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/best-terminal-tests.XXXXXX")"
PASSED=0

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT INT TERM

fail_test() {
  printf 'FAIL %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail_test "expected file: $1"
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail_test "expected '$2' in $1"
}

assert_not_contains() {
  if grep -Fq -- "$2" "$1"; then
    fail_test "did not expect '$2' in $1"
  fi
}

assert_count() {
  local actual
  actual="$(grep -Fc -- "$2" "$1" || true)"
  [[ "$actual" == "$3" ]] || fail_test "expected $3 copies of '$2' in $1, found $actual"
}

new_home() {
  local name="$1"
  local home="$TEST_ROOT/$name"
  mkdir -p "$home"
  printf '%s\n' "$home"
}

run_install() {
  local home="$1"
  shift
  HOME="$home" \
    XDG_CONFIG_HOME="$home/.config" \
    XDG_STATE_HOME="$home/.local/state" \
    BEST_TERMINAL_ALLOW_UNSUPPORTED=1 \
    /bin/bash "$PROJECT_ROOT/scripts/install.sh" --yes --config-only --no-backup "$@"
}

run_uninstall() {
  local home="$1"
  shift
  HOME="$home" \
    XDG_CONFIG_HOME="$home/.config" \
    XDG_STATE_HOME="$home/.local/state" \
    /bin/bash "$PROJECT_ROOT/scripts/uninstall.sh" --yes "$@"
}

test_fresh_install() {
  local home
  home="$(new_home fresh)"

  run_install "$home" >/dev/null

  assert_file "$home/.zshrc"
  assert_file "$home/.config/starship.toml"
  assert_file "$home/.config/ghostty/config"
  assert_file "$home/.config/best-terminal/zsh/init.zsh"
  assert_count "$home/.zshrc" "# >>> BestTerminal >>>" 1
  assert_contains "$home/.config/ghostty/config" "font-family = \"Maple Mono NF\""
  assert_contains "$home/.config/ghostty/config" "# >>> BestTerminal managed defaults >>>"
  /bin/zsh -n "$home/.zshrc"
}

test_incremental_install() {
  local home
  home="$(new_home incremental)"
  mkdir -p "$home/.config/ghostty" "$home/.config"
  cat >"$home/.zshrc" <<'EOF'
ZSH_THEME="robbyrussell"
# >>> ghostty-terminal-config >>>
eval "$(starship init zsh)"
# <<< ghostty-terminal-config <<<
EOF
  printf 'font-size = 17\nbackground-opacity = 1\n' >"$home/.config/ghostty/config"
  # Literal Starship variables are test fixture content.
  # shellcheck disable=SC2016
  printf 'format = "$directory$character"\n' >"$home/.config/starship.toml"

  run_install "$home" >/dev/null 2>&1

  assert_contains "$home/.zshrc" 'ZSH_THEME="robbyrussell"'
  assert_not_contains "$home/.zshrc" "# >>> ghostty-terminal-config >>>"
  assert_count "$home/.zshrc" "# >>> BestTerminal >>>" 1
  assert_count "$home/.config/ghostty/config" "font-size = 17" 1
  assert_not_contains "$home/.config/ghostty/config" "font-size = 13"
  assert_count "$home/.config/ghostty/config" "background-opacity = 1" 1
  # shellcheck disable=SC2016
  assert_contains "$home/.config/starship.toml" 'format = "$directory$character"'
}

test_idempotent_rerun() {
  local home
  local first_hashes
  local second_hashes
  home="$(new_home idempotent)"

  run_install "$home" >/dev/null
  first_hashes="$(shasum -a 256 "$home/.zshrc" "$home/.config/ghostty/config" "$home/.config/starship.toml" "$home/.local/state/best-terminal/state")"
  run_install "$home" >/dev/null
  second_hashes="$(shasum -a 256 "$home/.zshrc" "$home/.config/ghostty/config" "$home/.config/starship.toml" "$home/.local/state/best-terminal/state")"

  [[ "$first_hashes" == "$second_hashes" ]] || fail_test "a second install changed managed output"
  assert_count "$home/.zshrc" "# >>> BestTerminal >>>" 1
  assert_count "$home/.config/ghostty/config" "# >>> BestTerminal managed defaults >>>" 1
}

test_force_and_uninstall_restore() {
  local home
  home="$(new_home restore)"
  mkdir -p "$home/.config"
  printf '# personal shell config\n' >"$home/.zshrc"
  printf 'format = "CUSTOM"\n' >"$home/.config/starship.toml"

  HOME="$home" \
    XDG_CONFIG_HOME="$home/.config" \
    XDG_STATE_HOME="$home/.local/state" \
    BEST_TERMINAL_ALLOW_UNSUPPORTED=1 \
    /bin/bash "$PROJECT_ROOT/scripts/install.sh" --yes --config-only --force-config >/dev/null
  assert_not_contains "$home/.config/starship.toml" 'format = "CUSTOM"'

  run_uninstall "$home" >/dev/null
  assert_contains "$home/.config/starship.toml" 'format = "CUSTOM"'
  assert_contains "$home/.zshrc" "# personal shell config"
  assert_not_contains "$home/.zshrc" "# >>> BestTerminal >>>"
}

test_unclosed_block_fails_safely() {
  local home
  local before
  home="$(new_home malformed)"
  printf '# >>> BestTerminal >>>\nsource something\n' >"$home/.zshrc"
  before="$(sha256_file_for_test "$home/.zshrc")"

  if run_install "$home" >/dev/null 2>&1; then
    fail_test "installer accepted an unclosed managed block"
  fi
  [[ "$before" == "$(sha256_file_for_test "$home/.zshrc")" ]] || fail_test "malformed zshrc was modified"
}

test_symlinked_zshrc_is_preserved() {
  local home
  home="$(new_home symlink)"
  mkdir -p "$home/dotfiles"
  printf '# managed by a dotfiles repository\n' >"$home/dotfiles/zshrc"
  ln -s dotfiles/zshrc "$home/.zshrc"

  run_install "$home" >/dev/null

  [[ -L "$home/.zshrc" ]] || fail_test "installer replaced a zshrc symbolic link"
  assert_contains "$home/dotfiles/zshrc" "# >>> BestTerminal >>>"

  run_uninstall "$home" >/dev/null
  [[ -L "$home/.zshrc" ]] || fail_test "uninstaller replaced a zshrc symbolic link"
  assert_not_contains "$home/dotfiles/zshrc" "# >>> BestTerminal >>>"
}

test_bootstraps_homebrew_and_installs_missing_packages() {
  local home
  local fake_bin
  local fake_brew_source
  local fake_brew_target
  local brew_log
  home="$(new_home bootstrap)"
  fake_bin="$home/fake-bin"
  fake_brew_source="$home/fake-brew-source"
  fake_brew_target="$home/homebrew/bin/brew"
  brew_log="$home/brew.log"
  mkdir -p "$fake_bin" "$home/empty-applications" "$home/empty-system-fonts"

  cat >"$fake_brew_source" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  shellenv)
    exit 0
    ;;
  list)
    exit 1
    ;;
  install)
    shift
    printf '%s\n' "$*" >>"$BREW_LOG"
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "$fake_brew_source"

  cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
cat <<'INSTALL_HOMEBREW'
mkdir -p "$(dirname "$FAKE_BREW_TARGET")"
cp "$FAKE_BREW_SOURCE" "$FAKE_BREW_TARGET"
chmod +x "$FAKE_BREW_TARGET"
INSTALL_HOMEBREW
EOF
  chmod +x "$fake_bin/curl"

  HOME="$home" \
    PATH="$fake_bin:/usr/bin:/bin" \
    XDG_CONFIG_HOME="$home/.config" \
    XDG_STATE_HOME="$home/.local/state" \
    BEST_TERMINAL_ALLOW_UNSUPPORTED=1 \
    BEST_TERMINAL_APPLICATIONS_DIR="$home/empty-applications" \
    BEST_TERMINAL_SYSTEM_FONT_DIR="$home/empty-system-fonts" \
    BEST_TERMINAL_BREW_BIN="$fake_brew_target" \
    FAKE_BREW_SOURCE="$fake_brew_source" \
    FAKE_BREW_TARGET="$fake_brew_target" \
    BREW_LOG="$brew_log" \
    /bin/bash "$PROJECT_ROOT/scripts/install.sh" --yes --no-backup >/dev/null

  [[ -x "$fake_brew_target" ]] || fail_test "Homebrew bootstrap did not create brew"
  assert_contains "$brew_log" "starship fzf zoxide eza bat yazi zsh-autosuggestions zsh-syntax-highlighting zsh-completions"
  assert_contains "$brew_log" "--cask ghostty"
  assert_contains "$brew_log" "--cask font-maple-mono-nf"
}

sha256_file_for_test() {
  shasum -a 256 "$1" | awk '{print $1}'
}

run_test() {
  local name="$1"
  "$name"
  PASSED=$((PASSED + 1))
  printf 'PASS %s\n' "$name"
}

run_test test_fresh_install
run_test test_incremental_install
run_test test_idempotent_rerun
run_test test_force_and_uninstall_restore
run_test test_unclosed_block_fails_safely
run_test test_symlinked_zshrc_is_preserved
run_test test_bootstraps_homebrew_and_installs_missing_packages

printf '\n%d tests passed\n' "$PASSED"
