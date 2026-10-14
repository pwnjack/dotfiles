# CachyOS defaults (skipped on vanilla Arch)
if test -f /usr/share/cachyos-fish-config/cachyos-config.fish
    source /usr/share/cachyos-fish-config/cachyos-config.fish
end

# Load KEY=value lines from .env. Parsed here rather than through xargs, which
# splits values on spaces and strips quotes unpredictably.
if test -f ~/.config/.env
    for line in (string match -rv '^\s*(#|$)' < ~/.config/.env)
        set -l pair (string split -m1 = -- (string replace -r '^\s*export\s+' '' -- $line))
        test (count $pair) -eq 2; or continue
        set -gx (string trim -- $pair[1]) (string trim -- $pair[2] | string trim -c '"\'')
    end
end

# Load aliases
source ~/.config/fish/aliases.fish

# Keep GnuPG pinentry attached to the terminal that invoked it. The system
# pinentry wrapper prefers a graphical dialog under Wayland and falls back to
# this TTY when a graphical backend is unavailable.
if status is-interactive
    set -gx GPG_TTY (tty)
    gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
end

if type -q zoxide
    zoxide init fish | source
end

# Starship prompt. Without this the CachyOS vendor fish_prompt stays in charge
# and starship.toml is never read. Must come after the cachyos-config source
# above, since that is what defines the prompt being replaced.
# starship.toml is a symlink to the palette-rendered copy in ~/.cache, so the
# prompt follows the wallpaper — see starship/apply_wal_colors.sh.
if type -q starship
    starship init fish | source
end
