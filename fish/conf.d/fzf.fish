# fzf key bindings, from fzf's own fish integration:
#   Ctrl+R  search command history
#   Ctrl+T  insert a file path at the cursor (previewed with bat)
#   Alt+C   cd into a subdirectory (previewed as a tree)
status is-interactive; or return
type -q fzf; or return

# --color=16 keeps fzf to the terminal's 16 colours, which ghostty takes from
# matugen, so it follows the wallpaper like bat and fastfetch.
set -gx FZF_DEFAULT_OPTS "--color=16 --height=40% --layout=reverse --border"

# fd is faster than find and skips what .gitignore skips.
if type -q fd
    set -gx FZF_DEFAULT_COMMAND "fd --type f --hidden --exclude .git"
    set -gx FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND
    set -gx FZF_ALT_C_COMMAND "fd --type d --hidden --exclude .git"
end
type -q bat; and set -gx FZF_CTRL_T_OPTS "--preview 'bat --color=always --style=numbers --line-range=:200 {}'"
type -q eza; and set -gx FZF_ALT_C_OPTS "--preview 'eza --tree --level=2 --color=always --icons {}'"

fzf --fish | source
