#!/usr/bin/env bash
#
# Render options/font and options/font-gtk into the font includes
# (~/.local/state/{rofi,waybar,ghostty}), Alacritty, GTK and gsettings. Rofi and
# Ghostty reach theirs through tracked symlinks; waybar/style.css imports
# its by relative path (Waybar's watcher ignores a symlinked import).
# `--includes` renders only the three includes
# (scripts/state/derived.sh runs that after every sync). Tracked files are never
# edited. Run by the settings panel after either option changes; a nonzero exit
# makes the panel restore the previous option.
#
# Every rofi theme imports rofi/options/font.rasi, a symlink to the rendered
# include, so rofi needs one file rather than each theme. Other fonts named inside themes (the
# `feather` icon font, the cheatsheet's monospace) are deliberate and left alone.
#

config_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)

read_font() {
    local value
    value=$(head -n1 "$config_dir/options/$1" 2>/dev/null)
    value=${value#\"}
    printf '%s' "${value%\"}"
}

main_font=$(read_font font)
gtk_font=$(read_font font-gtk)
main_font=${main_font:-FiraCode Nerd Font}
gtk_font=${gtk_font:-Adwaita Sans}

# Every target quotes the name with double quotes, so one inside it cannot be
# written anywhere safely.
if [[ "$main_font$gtk_font" == *\"* ]]; then
    echo "Font names cannot contain double quotes" >&2
    exit 1
fi

# Escape the characters a sed replacement treats specially (| is the delimiter).
sed_escape() { printf '%s' "$1" | sed 's/[\\&|]/\\&/g'; }
main_sed=$(sed_escape "$main_font")
gtk_sed=$(sed_escape "$gtk_font")

failed=0

state_dir="$HOME/.local/state"

# write_if_changed <file> <content> — the include, rewritten only on change so
# Waybar's style watcher (which follows the relative import of this real file) fires for a real change and nothing else.
write_if_changed() {
    mkdir -p "$(dirname "$1")" || return 1
    [ -f "$1" ] && [ "$(cat "$1")" = "$2" ] && return 0
    printf '%s\n' "$2" > "$1.tmp" && mv -f "$1.tmp" "$1"
}

write_if_changed "$state_dir/rofi/font.rasi" "configuration { font: \"$main_font 10\"; }" || failed=1
write_if_changed "$state_dir/waybar/font.css" "$(printf '* {\n    font-family: "%s", "JetbrainsMono Nerd", "Hack Nerd", sans-serif;\n}' "$main_font")" || failed=1
write_if_changed "$state_dir/ghostty/font" "font-family = \"$main_font\"" || failed=1

if [ "${1:-}" = --includes ]; then
    [ "$failed" -eq 0 ] || { echo "Some font includes could not be written" >&2; exit 1; }
    exit 0
fi

echo "Main font: $main_font"
echo "GTK font:  $gtk_font"

# Alacritty (untracked, optional)
alacritty_conf="$config_dir/alacritty/alacritty.toml"
if [[ -f "$alacritty_conf" ]]; then
    sed -i "s|normal.family = \".*\"|normal.family = \"$main_sed\"|" "$alacritty_conf" || failed=1
fi

# GTK 3 and 4. Keep the size and any variable-font weight already configured:
# "Name 11" or "Name 11 @wght=500".
size=11 weight=""
for gtk_conf in "$config_dir/gtk-3.0/settings.ini" "$config_dir/gtk-4.0/settings.ini"; do
    [[ -f "$gtk_conf" ]] || continue
    current=$(sed -n 's/^gtk-font-name=//p' "$gtk_conf" | head -n1)
    if [[ "$current" =~ ([0-9]+)( @wght=[0-9]+)?$ ]]; then
        size=${BASH_REMATCH[1]}
        weight=${BASH_REMATCH[2]}
    fi
    if [[ -n "$current" ]]; then
        sed -i "s|^gtk-font-name=.*|gtk-font-name=$gtk_sed $size$weight|" "$gtk_conf" || failed=1
    else
        echo "gtk-font-name=$gtk_font $size$weight" >> "$gtk_conf" || failed=1
    fi
done

# The GTK files are rendered by the settings overlay; record the change as this
# machine's override. Absent only in isolated test fixtures.
overlay="$config_dir/scripts/state/overlay.sh"
if [[ -f "$overlay" ]]; then
    bash "$overlay" sync gtk-3.0/settings.ini gtk-4.0/settings.ini >/dev/null || failed=1
fi

# GTK 4, libadwaita and the settings portal read gsettings, not settings.ini.
if command -v gsettings >/dev/null; then
    gsettings set org.gnome.desktop.interface font-name "$gtk_font $size$weight" || failed=1
fi

if [[ "$failed" -ne 0 ]]; then
    echo "Some configs could not be updated" >&2
    exit 1
fi
echo "Fonts applied. Restart open applications to see the change."
