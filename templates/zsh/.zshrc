HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000
SAVEHIST=100000
setopt HIST_FCNTL_LOCK HIST_IGNORE_DUPS HIST_IGNORE_SPACE SHARE_HISTORY

command -v zoxide >/dev/null && eval "$(zoxide init zsh)"
command -v direnv >/dev/null && eval "$(direnv hook zsh)"
if [[ $options[zle] = on ]] && command -v fzf >/dev/null; then
  source <(fzf --zsh)
fi
if [[ $TERM != dumb ]] && command -v starship >/dev/null; then
  eval "$(starship init zsh)"
fi

for fragment in "$HOME/.config/keystone/shell.d"/*.zsh(N); do
  source "$fragment"
done

alias g=git
alias grep=rg
alias l='eza -1l'
alias ls='eza -1l'
alias y=yazi
alias zs='zesh connect'
alias ztab='zellij action rename-tab'

lg() {
  local new_directory_file="${XDG_STATE_HOME:-$HOME/.local/state}/lazygit/newdir"
  mkdir -p "${new_directory_file:h}"
  LAZYGIT_NEW_DIR_FILE="$new_directory_file" command lazygit "$@"
  if [[ -s "$new_directory_file" ]]; then
    cd "$(<"$new_directory_file")" || return
    rm -f "$new_directory_file"
  fi
}
