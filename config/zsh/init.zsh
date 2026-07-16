# BestTerminal shell integration. This file is managed by the installer.

if [[ -x /opt/homebrew/bin/brew ]]; then
  path=(/opt/homebrew/bin /opt/homebrew/sbin $path)
elif [[ -x /usr/local/bin/brew ]]; then
  path=(/usr/local/bin /usr/local/sbin $path)
fi
typeset -U path PATH

typeset -i best_terminal_completion_path_added=0
for completion_dir in \
  /opt/homebrew/share/zsh/site-functions \
  /opt/homebrew/share/zsh-completions \
  /usr/local/share/zsh/site-functions \
  /usr/local/share/zsh-completions; do
  if [[ -d "$completion_dir" && ${fpath[(Ie)$completion_dir]} -eq 0 ]]; then
    fpath=("$completion_dir" $fpath)
    best_terminal_completion_path_added=1
  fi
done
unset completion_dir

if (( $+functions[compdef] == 0 || best_terminal_completion_path_added )); then
  autoload -Uz compinit
  compinit -i
fi
unset best_terminal_completion_path_added

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh)
fi

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

if command -v yazi >/dev/null 2>&1; then
  function y() {
    local tmp cwd
    tmp="$(mktemp -t "yazi-cwd.XXXXXX")" || return
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp" 2>/dev/null)" && [[ -n "$cwd" && "$cwd" != "$PWD" ]]; then
      builtin cd -- "$cwd"
    fi
    command rm -f -- "$tmp"
  }
fi

if (( $+functions[_zsh_autosuggest_start] == 0 )); then
  for plugin_file in \
    "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" \
    "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" \
    /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
    /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh; do
    if [[ -r "$plugin_file" ]]; then
      source "$plugin_file"
      break
    fi
  done
  unset plugin_file
fi

if (( $+widgets[autosuggest-accept] )); then
  bindkey '^F' autosuggest-accept
fi

if command -v eza >/dev/null 2>&1; then
  alias ls='eza --icons --group-directories-first'
  alias ll='eza -l --icons --sort=name'
  alias lt='eza --tree --icons --level=2'
fi

if command -v bat >/dev/null 2>&1; then
  alias cat='bat --paging=never --style=plain'
fi

USER_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/best-terminal/user.zsh"
[[ -r "$USER_CONFIG" ]] && source "$USER_CONFIG"
unset USER_CONFIG

if (( $+functions[_zsh_highlight] == 0 )); then
  for plugin_file in \
    "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    "$HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
    /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
    if [[ -r "$plugin_file" ]]; then
      source "$plugin_file"
      break
    fi
  done
  unset plugin_file
fi
