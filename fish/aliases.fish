# Simple aliases
alias vi=nvim
alias ff=fastfetch

# cmatrix and tty-clock draw in ANSI green, which stays green on every
# palette; the wrapper gives their own terminal the wallpaper accent instead.
alias cmatrix='~/.config/scripts/theming/accent-run.sh cmatrix'
alias tty-clock='~/.config/scripts/theming/accent-run.sh tty-clock'
alias v=nvim

# Arch packages the Fabric AI CLI as `fabric-ai` to avoid colliding with
# Python Fabric. Upstream's documentation and examples use `fabric`. Fabric
# mistakes the valid C.UTF-8 locale for a translation name, so give only this
# command the generated English locale instead of changing the whole session.
alias fabric='env LC_ALL=en_US.UTF-8 fabric-ai'
