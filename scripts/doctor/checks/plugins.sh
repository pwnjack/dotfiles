#!/bin/bash
#
# Runtime dependencies that are not programs on PATH, so the binaries check
# cannot see them: the GObject introspection typelibs tracked JavaScript
# imports (gi://NM needs libnm), and the Qt style plugin each qt5ct/qt6ct
# configuration names (style=kvantum needs kvantum-qt5 for Qt 5, kvantum for
# Qt 6). Both have been missing on a machine whose every binary resolved.
#
# Targets are derived from tracked files: every gi://Name in the tree, outside
# docs/ and this doctor's own tree, and every defaults/qt*ct/qt*ct.conf. A
# style is read from the live file the overlay renders from that default, or
# from the default when nothing is rendered yet.
#
# Severity is WARN: a missing typelib breaks one panel page and a missing
# style falls back to Fusion; the session still starts.
#
# Accepted risk: a style is found by a case-insensitive *<style>*.so match in
# the Qt version's styles directory, because plugin file names follow no rule
# (libkvantum.so, breeze6.so). A style whose name is not in its file name
# reads as missing.

# _plg_typelib_present <namespace> -- host probe: a typelib for the namespace
# exists on GI_TYPELIB_PATH or in the system directories.
_plg_typelib_present() {
    local dir file
    local -a dirs
    IFS=: read -ra dirs <<< "${GI_TYPELIB_PATH:-}"
    for dir in "${dirs[@]}" /usr/lib/girepository-1.0 /usr/lib64/girepository-1.0; do
        [ -n "$dir" ] || continue
        # Only the version is a pattern: the quoted directory and namespace
        # match literally, so a path holding [ or * is still found.
        for file in "$dir/$1"-*.typelib; do
            [ -f "$file" ] && return 0
        done
    done
    return 1
}

# _plg_qt_style_present <major> <style> -- host probe: Qt's built-in styles
# need nothing, any other needs a plugin in that Qt version's styles directory.
# DOCTOR_QT_LIBDIR can point the lookup at a private fixture's qt/qt6 trees.
_plg_qt_style_present() {
    local dir
    case "${2,,}" in
        fusion|windows) return 0 ;;
    esac
    case "$1" in
        5) dir="${DOCTOR_QT_LIBDIR:-/usr/lib}/qt/plugins/styles" ;;
        *) dir="${DOCTOR_QT_LIBDIR:-/usr/lib}/qt$1/plugins/styles" ;;
    esac
    [ -n "$(find "$dir" -maxdepth 1 -iname "*$2*.so" -print -quit 2>/dev/null)" ]
}

# _plg_style <file> -> the style= value in [Appearance], or nothing.
_plg_style() {
    awk '
        /^[[:space:]]*\[/ { main = ($0 ~ /^[[:space:]]*\[Appearance\][[:space:]]*$/); next }
        main && /^[[:space:]]*style[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]\r]+$/, ""); print; exit
        }
    ' "$1"
}

check_plugins() {
    group "Typelibs and plugins"
    local ns file live style major before=$((DOCTOR_WARNINGS + DOCTOR_NOTICES))

    while IFS= read -r ns; do
        _plg_typelib_present "$ns" && continue
        warn "No typelib for gi://$ns, which tracked JavaScript imports" \
            "sudo pacman -Fy, then pacman -Fx 'girepository-1.0/$ns-[0-9.]+\\.typelib' names the package to install"
    done < <(git -C "$DOCTOR_ROOT" grep -IhoE 'gi://[A-Za-z][A-Za-z0-9]*' -- . ':!docs/' ':!scripts/doctor/' 2>/dev/null |
        sed 's|^gi://||' | sort -u)

    while IFS= read -r -d '' file; do
        case "$file" in
            defaults/qt[0-9]ct/qt[0-9]ct.conf) ;;
            *) continue ;;
        esac
        major="${file#defaults/qt}"
        major="${major%%ct/*}"
        live="$DOCTOR_ROOT/${file#defaults/}"
        [ -f "$live" ] || live="$DOCTOR_ROOT/$file"
        style="$(_plg_style "$live")"
        [ -n "$style" ] || continue
        _plg_qt_style_present "$major" "$style" && continue
        warn "Qt $major has no '$style' style plugin, which ${live#"$DOCTOR_ROOT"/} selects, so Qt $major apps fall back to Fusion" \
            "sudo pacman -Fy, then pacman -Fx 'qt$([ "$major" = 5 ] || echo "$major")/plugins/styles/.*$style.*\\.so' names the package to install"
    done < <(git -C "$DOCTOR_ROOT" ls-files -z -- 'defaults/' 2>/dev/null)

    if [ $((DOCTOR_WARNINGS + DOCTOR_NOTICES)) -eq "$before" ]; then
        ok "Every imported typelib and selected Qt style plugin is installed"
    fi
}
