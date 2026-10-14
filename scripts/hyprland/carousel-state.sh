#!/bin/bash
# Read established configuration afresh on every open; emit data, never shell code.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
command -v python3 >/dev/null || { echo 'python3 is required' >&2; exit 1; }
# shellcheck source=scripts/theming/palette.sh
source "$script_dir/../theming/palette.sh"
# shellcheck source=scripts/lib/wallpaper.sh
source "$script_dir/../lib/wallpaper.sh"
wal=()
wal_load
# shellcheck disable=SC2034  # read by role_load, wal_role and wal_render
declare -A role=()
role_load
# awww is the visible state; the palette symlink can still be catching up.
shown=""
if query=$(timeout 2 awww query 2>/dev/null); then
    shown=$(wallpaper_from_query "$query")
fi
python3 - "${wal[0]}" "$(wal_readable_on "${wal[0]}")" "$(wal_role primary)" "$shown" <<'PY'
import configparser
import json
import os
from pathlib import Path
import subprocess
import sys

config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
cache = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache'))
data = dict(entries=[], current='', folders=[], error='', background=sys.argv[1],
            foreground=sys.argv[2], accent=sys.argv[3], reducedMotion=False)
try:
    ini = configparser.ConfigParser(interpolation=None)
    with (config / 'waypaper/config.ini').open() as stream:
        ini.read_file(stream)
    settings = ini['Settings']
    if settings.getboolean('use_xdg_state', fallback=False):
        raise ValueError('Separate Waypaper state is not supported. Use Waypaper directly.')
    folders = [Path(p).expanduser().absolute() for p in settings.get('folder', '').splitlines() if p.strip()]
    data['folders'] = [str(p) for p in folders]
    recursive = settings.getboolean('subfolders', fallback=False) or settings.getboolean('all_subfolders', fallback=False)
    hidden = settings.getboolean('show_hidden', fallback=False)
    extensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.avif', '.jxl', '.heif'}
    if settings.getboolean('show_gifs_only', fallback=False):
        extensions = {'.gif'}
    files = {}
    errors = []
    def scan_error(error):
        errors.append(str(error))
    for folder in folders:
        if not folder.is_dir() or not os.access(folder, os.R_OK | os.X_OK):
            errors.append(f'Cannot read {folder}')
            continue
        for directory, dirs, names in os.walk(folder, onerror=scan_error):
            dirs[:] = [d for d in dirs if hidden or not d.startswith('.')]
            for name in names:
                path = Path(directory) / name
                if (hidden or not name.startswith('.')) and path.suffix.lower() in extensions:
                    try:
                        if path.is_file() and os.access(path, os.R_OK):
                            files[str(path)] = (path, path.stat().st_mtime)
                    except OSError:
                        pass  # A file can disappear during the scan.
            if not recursive:
                break
    values = list(files.values())
    order = settings.get('sort', 'name').lower()
    values.sort(key=(lambda item: item[1]) if order == 'date' else (lambda item: str(item[0]).casefold()))
    data['entries'] = [dict(path=str(p), url=p.as_uri(), name=p.name) for p, _ in values]
    data['error'] = '; '.join(errors)
    data['current'] = str(Path(settings.get('wallpaper', '')).expanduser())
    # sys.argv[4]: what awww shows now (scripts/lib/wallpaper.sh), empty when
    # awww could not be queried.
    if sys.argv[4]:
        data['current'] = sys.argv[4]
    elif not data['current'] and (cache / 'current_wallpaper').exists():
        data['current'] = str((cache / 'current_wallpaper').resolve())
    try:
        option = json.loads(subprocess.run(['hyprctl', 'getoption', 'animations:enabled', '-j'],
                            capture_output=True, text=True, timeout=2, check=True).stdout)
        data['reducedMotion'] = not option.get('bool', option.get('int', True))
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
except (OSError, ValueError, configparser.Error, KeyError) as error:
    data['error'] = str(error)
print(json.dumps(data))
PY
