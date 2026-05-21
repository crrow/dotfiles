# ~/.zshrc — symlinked from crrow/dotfiles
# Order: PATH → oh-my-zsh → plugins → starship → mise → user aliases

# --- PATH ---------------------------------------------------------------------
typeset -U path PATH                     # dedupe
path=(
  $HOME/.local/bin
  /opt/homebrew/bin /opt/homebrew/sbin   # macOS arm64
  /usr/local/bin /usr/local/sbin         # macOS intel
  /home/linuxbrew/.linuxbrew/bin         # Linux
  $path
)

# --- oh-my-zsh ----------------------------------------------------------------
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""                              # disabled: starship owns the prompt
DISABLE_AUTO_UPDATE="true"
plugins=(
  git
  fzf
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-completions
)
[[ -f "$ZSH/oh-my-zsh.sh" ]] && source "$ZSH/oh-my-zsh.sh"

# --- prompt -------------------------------------------------------------------
command -v starship >/dev/null && eval "$(starship init zsh)"

# --- runtime version manager --------------------------------------------------
command -v mise >/dev/null && eval "$(mise activate zsh)"

# --- aliases ------------------------------------------------------------------
alias ll='ls -lah'
alias g='git'
alias zj='zellij'

# --- local overrides (not tracked) --------------------------------------------
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
