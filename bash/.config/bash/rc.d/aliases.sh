#@ 25 aliases
# Aliases in the fast loop: edit, re-source, done. Settled ones can move to
# programs.bash.shellAliases in home.nix, where changing them costs a rebuild.

#: aliases               show every alias defined here
#>   aliases
#>   aliases | grep git    find one
#>
#>   git:      gs gb gco gcb ga gc gca gp gpl gd gl gst
#>   nix:      hm-build hm-switch hm-news
#>   dotfiles: dot
#>   system:   logs logsf
#>
#>   an alias only expands as the first word of a command; for anything
#>   that needs arguments in the middle, write a function instead
aliases() {
    grep -E '^alias ' "$DEV_RC_DIR/aliases.sh" | sed 's/^alias //'
}

# --- git --------------------------------------------------------------------
alias gs='git status --short --branch'
alias gb='git branch'
alias gco='git checkout'
alias gcb='git checkout -b'
alias ga='git add'
alias gc='git commit'
alias gca='git commit --amend'
alias gp='git push'
alias gpl='git pull --rebase'
alias gd='git diff'
alias gdc='git diff --cached'
alias gl='git log --oneline --graph --decorate -20'
alias gst='git stash'

# --- nix / home-manager -----------------------------------------------------
alias hm-build='home-manager build'
alias hm-switch='home-manager switch'
alias hm-news='home-manager news'

# --- dotfiles ---------------------------------------------------------------
alias dot='cd "$DEV_ENV" && git status --short'

# --- system -----------------------------------------------------------------
alias logs='journalctl -xe --no-pager'
alias logsf='journalctl -f'
