#!/bin/bash
# Exercise the real pipeline with isolated caches and command stubs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

root = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp)
    config, cache, bins = (base / n for n in ('config', 'cache', 'bin'))
    for path in (config / 'options', config / 'scripts/theming', cache, bins):
        path.mkdir(parents=True, exist_ok=True)
    (config / 'options/mainmonitor').write_text('')
    selected, events = base / 'selected', base / 'events'
    first, second = base / 'first.jpg', base / 'second.jpg'
    first.touch(); second.touch()
    selected.write_text(str(first))
    events.write_text('')
    def executable(path, text):
        path.write_text('#!/bin/bash\nset -eu\n' + text)
        path.chmod(0o755)
    executable(bins / 'awww', 'printf ": DP-1: image: %s\\n" "$(cat "$FIXTURE/selected")"\n')
    # The generator stages both palette files; the driver logs publication.
    executable(config / 'scripts/theming/generate-palette.sh', '''
img=$1
stage=$2
stamp() { echo "$1 $(date +%s%N)" >> "$FIXTURE/times"; }
mkdir "$FIXTURE/busy" || { echo overlap >> "$FIXTURE/events"; exit 1; }
trap 'rmdir "$FIXTURE/busy"' EXIT
echo "start $img" >> "$FIXTURE/events"
sleep 0.2
[ "${FAIL_WAL:-0}" = 0 ] || { echo 'generate-palette: matugen failed' >&2; exit 1; }
mkdir -p "$stage"
printf '%s\\n' "$img" > "$stage/colors"
printf '%s\\n' "$img" > "$stage/roles"
echo "end $img" >> "$FIXTURE/events"
stamp staged
''')
    executable(bins / 'notify-send', 'printf "%s\\n" "$*" >> "$FIXTURE/notices"\n')
    driver = config / 'scripts/theming/apply-wal.sh'
    apply_stub = '''
echo "apply $(cat "$XDG_CACHE_HOME/wal/colors")" >> "$FIXTURE/events"
cmp -s "$XDG_CACHE_HOME/wal/colors" "$XDG_CACHE_HOME/wal/roles"
echo "published $(date +%s%N)" >> "$FIXTURE/times"
exit "${FAIL_APPLY:-0}"
'''
    executable(driver, apply_stub)
    env = dict(os.environ, HOME=str(base), XDG_CONFIG_HOME=str(config), XDG_CACHE_HOME=str(cache),
               PATH=str(bins) + ':' + os.environ['PATH'], FIXTURE=str(base))
    command = ['bash', str(root / 'scripts/hyprland/wall.sh')]
    def run(**extra):
        return subprocess.run(command, env=dict(env, **extra), capture_output=True, timeout=10)
    result = run(FAIL_WAL='1')
    assert result.returncode == 1
    assert 'generate-palette: matugen failed' in result.stderr.decode(), result.stderr
    assert not (cache / 'current_wallpaper').exists()
    assert not (cache / 'wal/colors').exists()
    assert not (cache / 'wal/roles').exists()
    assert 'apply' not in events.read_text()
    assert 'Could not generate colors from first.jpg' in (base / 'notices').read_text()
    assert 'Wallpaper Applied' not in (base / 'notices').read_text()
    print('ok: generation failure does not publish state, reload, or announce success')
    (base / 'notices').write_text('')
    assert run(FAIL_APPLY='1').returncode == 1
    assert 'Wallpaper Applied' not in (base / 'notices').read_text()
    assert 'some components failed' in (base / 'notices').read_text()
    print('ok: partial component failure reaches the caller and notification')
    # A failed replacement preserves the published pair and wallpaper state.
    before = {name: (cache / 'wal' / name).read_bytes()
              for name in ('colors', 'roles', 'rofi-wallpaper.rasi')}
    events.write_text('')
    selected.write_text(str(second))
    assert run(FAIL_WAL='1').returncode == 1
    assert all((cache / 'wal' / name).read_bytes() == data for name, data in before.items())
    assert (cache / 'current_wallpaper').resolve() == first
    assert events.read_text().splitlines() == [f'start {second}']
    selected.write_text(str(first))
    print('ok: failed generation preserves existing colors, roles, and wallpaper state')
    executable(driver, '''
echo "apply $(cat "$XDG_CACHE_HOME/wal/colors")" >> "$FIXTURE/events"
[ ! -e /proc/$$/fd/9 ] || { echo 'driver inherited fd 9' >&2; exit 1; }
printf '%s\\n' 'component diagnostic' 'apply-wal: spicetify/apply_wal_colors.sh failed' \\
    'another diagnostic' 'apply-wal: swaync/apply_wal_colors.sh failed' \\
    'apply-wal: 2 component(s) failed' >&2
exit 1
''')
    (base / 'notices').write_text('')
    result = run()
    assert result.returncode == 1
    message = 'Colors were generated, but these components failed to update: spicetify, swaync.'
    assert message in (base / 'notices').read_text()
    expected = ('component diagnostic\napply-wal: spicetify/apply_wal_colors.sh failed\n'
                'another diagnostic\napply-wal: swaync/apply_wal_colors.sh failed\n'
                'apply-wal: 2 component(s) failed\n')
    assert result.stderr.decode() == expected + f'wallpaper: {message}\n', result.stderr
    assert not list((cache / 'wal').glob('apply-errors.*'))
    print('ok: failure toast names components, preserves ordered stderr, closes fd 9, and removes capture')
    executable(driver, apply_stub)
    events.write_text('')
    one = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    deadline = time.monotonic() + 5
    while 'start' not in events.read_text():
        assert time.monotonic() < deadline
        time.sleep(.01)
    selected.write_text(str(second))
    two = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    for process in (one, two):
        process.communicate(timeout=10)
        assert process.returncode == 0
    lines = events.read_text().splitlines()
    assert lines == [f'start {first}', f'end {first}', f'apply {first}',
                     f'start {second}', f'end {second}', f'apply {second}'], lines
    assert (cache / 'current_wallpaper').resolve() == second
    assert (cache / 'wal/colors').read_text() == (cache / 'wal/roles').read_text() == f'{second}\n'
    assert not list((cache / 'wal').glob('.publish.*'))
    print('ok: overlapping changes serialize and the latest wallpaper wins')
    # Waypaper drives a 2 s awww transition: the palette is staged at once and
    # published 60% of the way through it (1.2 s).
    (config / 'waypaper').mkdir()
    ini = config / 'waypaper/config.ini'
    def waypaper(kind, duration):
        ini.write_text(f'[Settings]\nbackend = awww\nswww_transition_type = {kind}\n'
                       f'swww_transition_duration = {duration}\n')
    def times():
        return {k: int(v) for k, v in (l.split() for l in (base / 'times').read_text().splitlines())}
    waypaper('wipe', 2)
    events.write_text(''); (base / 'times').write_text('')
    began = time.time_ns()
    assert run().returncode == 0
    stamps = times()
    assert stamps['staged'] - began < 600_000_000, stamps
    assert 1_150_000_000 <= stamps['published'] - began < 1_900_000_000, stamps
    assert events.read_text().splitlines()[-1:] == [f'apply {second}']
    print('ok: the palette is staged at once and published part-way through the transition')
    # A change during the wait is staged in turn, and its own transition is
    # waited out (Waypaper saves its config as each transition starts).
    events.write_text(''); (base / 'times').write_text('')
    selected.write_text(str(first))
    one = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    deadline = time.monotonic() + 5
    while 'end' not in events.read_text():
        assert time.monotonic() < deadline
        time.sleep(.01)
    time.sleep(.3)
    selected.write_text(str(second))
    waypaper('wipe', 2)
    changed = time.time_ns()
    one.communicate(timeout=10)
    assert one.returncode == 0
    lines = events.read_text().splitlines()
    assert lines == [f'start {first}', f'end {first}', f'start {second}', f'end {second}',
                     f'apply {second}'], lines
    assert times()['published'] - changed >= 1_150_000_000, (times(), changed, lines)
    print('ok: a wallpaper replaced during the wait is not published; the new one is, on its own schedule')
    for kind in ('none', 'simple'):
        waypaper(kind, 2)
        began = time.time_ns()
        assert run().returncode == 0
        assert time.time_ns() - began < 1_000_000_000, kind
    print('ok: an instant or step-driven transition is not waited for')
    # A run queued behind one that already published the same wallpaper stages
    # it, finds it published, and repeats no reload or notification.
    events.write_text(''); (base / 'notices').write_text('')
    one = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    deadline = time.monotonic() + 5
    while 'start' not in events.read_text():
        assert time.monotonic() < deadline
        time.sleep(.01)
    two = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    for process in (one, two):
        process.communicate(timeout=10)
        assert process.returncode == 0
    lines = events.read_text().splitlines()
    assert lines == [f'start {second}', f'end {second}', f'apply {second}',
                     f'start {second}', f'end {second}'], lines
    assert (base / 'notices').read_text() == ''
    print('ok: a queued run does not republish what the run before it published')
    print('ok: a successful change posts no notification')
    # Selecting the same wallpaper again, unqueued, still re-applies it.
    events.write_text('')
    assert run().returncode == 0
    assert events.read_text().splitlines()[-1:] == [f'apply {second}']
    print('ok: an unqueued run re-applies the current wallpaper')
    assert not (base / 'ui-starts').exists()
    print('ok: wallpaper changes do not start or reload a resident UI')
    # The real driver attempts later components even if an earlier one fails.
    for name, code in [('a', 1), ('b', 0)]:
        directory = config / name
        directory.mkdir()
        executable(directory / 'apply_wal_colors.sh', f'echo {name} >> "$FIXTURE/components"\nexit {code}\n')
    result = subprocess.run(['bash', str(root / 'scripts/theming/apply-wal.sh')], env=env, capture_output=True)
    assert result.returncode == 1
    assert (base / 'components').read_text() == 'a\nb\n'
    print('ok: driver attempts all components and preserves failure status')
PY
