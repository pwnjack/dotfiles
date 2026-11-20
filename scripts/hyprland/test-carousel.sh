#!/bin/bash
# Exercise the real helpers with isolated config, cache, and process stubs.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import configparser
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

root = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp)
    config, cache, bins, images = (base / name for name in ('config', 'cache', 'bin', 'images'))
    for folder in (config / 'waypaper', config / 'options', config / 'scripts/hyprland', config / 'scripts/theming', cache, bins, images):
        folder.mkdir(parents=True, exist_ok=True)
    (config / 'scripts/theming/palette.sh').symlink_to(root / 'scripts/theming/palette.sh')
    special = images / '雪 100 "quote" \'single\' $(touch INJECTED) `id` #1.jpg'
    special.touch()
    second = images / 'second.png'
    second.touch()
    (images / '.hidden.jpg').touch()
    unreadable = images / 'unreadable.jpg'
    unreadable.touch()
    unreadable.chmod(0)
    (images / 'broken.jpg').symlink_to(images / 'absent.jpg')
    (images / 'nested').mkdir()
    (images / 'nested/child.jpg').touch()
    (config / 'options/mainmonitor').write_text('')
    ini = configparser.ConfigParser(interpolation=None)
    ini['Settings'] = dict(folder=str(images), wallpaper=str(special), backend='awww',
                           subfolders='False', show_hidden='False')
    def save():
        with (config / 'waypaper/config.ini').open('w') as stream:
            ini.write(stream)
    save()
    (base / 'selected').write_text(str(special))
    def executable(path, body, language='bash'):
        path.write_text(f'#!/usr/bin/env {language}\n' + body)
        path.chmod(0o755)
    executable(bins / 'awww', '''
if [[ ${QUERY_FAIL:-0} == 1 ]]; then exit 1; fi
printf ': FIXTURE-A: image: %s\n' "$(cat "$FIXTURE/selected")"
printf ': FIXTURE-B: image: %s\n' "$(cat "$FIXTURE/selected")"
''')
    executable(bins / 'hyprctl', 'echo \'{"bool":false,"set":true}\'\n')
    executable(bins / 'notify-send', 'printf "%s\\n" "$*" >> "$FIXTURE/notices"\n')
    executable(bins / 'waypaper', '''
import configparser, json, os, pathlib, sys, time
base = pathlib.Path(os.environ['FIXTURE'])
with (base / 'arguments').open('a') as stream:
    stream.write(json.dumps(sys.argv[1:]) + '\\n')
if os.environ.get('APPLY_FAIL') == '1': sys.exit(1)
if os.environ.get('BACKEND_FAIL') != '1':
    (base / 'selected').write_text(sys.argv[-1])
if os.environ.get('SAVE_FAIL') != '1':
    file = pathlib.Path(os.environ['XDG_CONFIG_HOME']) / 'waypaper/config.ini'
    ini = configparser.ConfigParser()
    ini.read(file)
    ini.set('Settings', 'wallpaper', sys.argv[-1])
    with file.open('w') as stream: ini.write(stream)
time.sleep(float(os.environ.get('DELAY', '0')))
''', 'python3')
    executable(config / 'scripts/hyprland/wall.sh', '''
echo theme >> "$FIXTURE/events"
exit "${THEME_FAIL:-0}"
''')
    env = dict(os.environ, FIXTURE=str(base), XDG_CONFIG_HOME=str(config),
               XDG_CACHE_HOME=str(cache), PATH=str(bins) + ':' + os.environ['PATH'])
    def run(helper, *args, **extra):
        return subprocess.run(['bash', str(root / 'scripts/hyprland' / helper), *map(str, args)],
                              env=dict(env, **extra), capture_output=True, text=True, timeout=15)
    def state():
        result = run('carousel-state.sh')
        assert result.returncode == 0, result.stderr
        return json.loads(result.stdout)
    data = state()
    assert len(data['entries']) == 2, data
    assert str(unreadable) not in [e['path'] for e in data['entries']]
    assert data['current'] == str(special)
    assert data['reducedMotion'] is True  # 'set' means configured, not enabled.
    entry = next(e for e in data['entries'] if e['path'] == str(special))
    assert '%23' in entry['url'] and '%24' in entry['url']
    assert not (base / 'arguments').exists() and not (base / 'events').exists()
    print('ok: browse/cancel reads only; filenames and URLs survive; disabled animations respected')
    ini['Settings']['subfolders'] = 'True'
    ini['Settings']['show_hidden'] = 'True'
    save()
    assert len(state()['entries']) == 4
    ini['Settings']['folder'] = str(base / 'missing')
    save()
    assert state()['entries'] == [] and state()['error']
    empty = base / 'empty'
    empty.mkdir()
    ini['Settings']['folder'] = str(empty)
    save()
    assert state()['entries'] == [] and not state()['error']
    ini['Settings']['folder'] = str(images)
    save()
    print('ok: runtime folders, recursion, hidden/unreadable files, empty and missing folders')
    result = run('carousel-apply.sh', special)
    assert result.returncode == 0, result.stderr
    args = json.loads((base / 'arguments').read_text().splitlines()[-1])
    assert args == ['--backend', 'awww', '--monitor', 'All', '--no-post-command', '--wallpaper', str(special)], args
    assert (base / 'events').read_text() == 'theme\n'
    assert not (root / 'INJECTED').exists()
    print('ok: argument boundaries preserved, all monitors selected, theme invoked exactly once')
    (base / 'events').write_text('')
    for extra in ({'APPLY_FAIL':'1'}, {'BACKEND_FAIL':'1'}, {'QUERY_FAIL':'1'}, {'SAVE_FAIL':'1'}):
        save()
        result = run('carousel-apply.sh', second, **extra)
        assert result.returncode != 0
        assert (base / 'events').read_text() == ''
    result = run('carousel-apply.sh', special, THEME_FAIL='1')
    assert result.returncode == 1 and (base / 'events').read_text() == 'theme\n'
    print('ok: command, swallowed backend, query and theme failures propagate truthfully')
    before = (base / 'arguments').read_text()
    second.unlink()
    assert run('carousel-apply.sh', second).returncode == 1
    newline = images / 'line\nbreak.jpg'
    newline.touch()
    assert run('carousel-apply.sh', newline).returncode == 1
    percent = images / '100%.jpg'
    percent.touch()
    assert run('carousel-apply.sh', percent).returncode == 1
    assert (base / 'arguments').read_text() == before
    print('ok: removed images and unsupported line breaks rejected before backend submission')
    first = subprocess.Popen(['bash', str(root / 'scripts/hyprland/carousel-apply.sh'), str(special)],
                             env=dict(env, DELAY='0.4'), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    deadline = time.monotonic() + 5
    while (base / 'arguments').read_text() == before:
        assert time.monotonic() < deadline
        time.sleep(0.01)
    duplicate = run('carousel-apply.sh', special)
    assert duplicate.returncode == 1 and 'still being applied' in duplicate.stderr
    first.communicate(timeout=5)
    assert first.returncode == 0
    print('ok: overlapping confirmations rejected while the original submission completes')
    # Real launcher against a stub IPC server: each close tears down the instance.
    executable(bins / 'qs', '''
if [[ $* == *--daemonize* ]]; then
    echo launch >> "$FIXTURE/launches"
    echo "$CAROUSEL_BACKGROUND" >> "$FIXTURE/backgrounds"
    sleep 0.1
    touch "$FIXTURE/ready"
elif [[ $* == *'ipc call carousel ping'* ]]; then
    test -f "$FIXTURE/ready"
elif [[ $* == *'ipc call carousel toggle'* ]]; then
    test -f "$FIXTURE/ready" || exit 1
    echo toggle >> "$FIXTURE/toggles"
    rm -f "$FIXTURE/ready"
else
    exit 1
fi
''')
    processes = [subprocess.Popen(['bash', str(root / 'scripts/hyprland/wallpaper-carousel.sh')],
                 env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(8)]
    for process in processes:
        process.communicate(timeout=10)
        assert process.returncode == 0
    assert len((base / 'launches').read_text().splitlines()) == 4
    assert len((base / 'toggles').read_text().splitlines()) == 4
    assert not (base / 'ready').exists()
    assert all(line.startswith('#') for line in (base / 'backgrounds').read_text().splitlines()), 'palette reaches qs'
    assert run('wallpaper-carousel.sh', 'start').returncode == 2
    print('ok: simultaneous toggles serialize into four launches and four process exits')
PY
