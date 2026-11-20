#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PY'
# Construct disposable Git objects/index directly. No staging, commits, or
# configuration changes are made to the user's repo (or through Git commands).
import hashlib
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zlib

root = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp)
    repo = base / 'fixture'
    metadata = repo / '.git'
    for directory in (metadata / 'objects', metadata / 'refs/heads', repo / 'scripts/hooks'):
        directory.mkdir(parents=True)
    (metadata / 'HEAD').write_text('ref: refs/heads/main\n')
    (metadata / 'config').write_text('[core]\nrepositoryformatversion = 0\nbare = false\n')
    (repo / 'scripts/hooks/snapshot.sh').write_bytes((root / 'scripts/hooks/snapshot.sh').read_bytes())
    def obj(kind, content):
        raw = kind + b' ' + str(len(content)).encode() + b'\0' + content
        oid = hashlib.sha1(raw).digest()
        path = metadata / 'objects' / oid.hex()[:2] / oid.hex()[2:]
        path.parent.mkdir(exist_ok=True)
        path.write_bytes(zlib.compress(raw))
        return oid
    def index(files):
        entries = []
        for name, (mode, content) in sorted(files.items()):
            path = os.fsencode(name)
            oid = obj(b'blob', content)
            entry = struct.pack('!10I20sH', 0, 0, 0, 0, 0, 0, int(mode, 8), 0, 0, len(content), oid, min(len(path), 0xfff)) + path + b'\0'
            entry += b'\0' * (-len(entry) % 8)
            entries.append(entry)
        data = b'DIRC' + struct.pack('!II', 2, len(entries)) + b''.join(entries)
        (metadata / 'index').write_bytes(data + hashlib.sha1(data).digest())
    runner = b'#!/bin/bash\nset -eu\ntest "$(cat payload)" = staged\ngit show :payload | cmp - payload\n'
    files = {'test.sh': ('100755', runner), 'payload': ('100644', b'staged'),
             'probe.sh': ('100755', b'#!/bin/bash\necho "unterminated\n'),
             'space \u00e9\nname': ('100644', b'odd path'), 'cache-link': ('120000', b'../missing-cache')}
    index(files)
    (repo / 'payload').write_text('unstaged')
    (repo / 'probe.sh').write_text('#!/bin/bash\necho fixed\n')
    (repo / 'test.sh').write_text('#!/bin/bash\nexit 99\n')
    hook = root / 'scripts/hooks/pre-commit'
    def run():
        before = (metadata / 'index').read_bytes()
        result = subprocess.run(['bash', str(hook)], cwd=repo, capture_output=True, text=True)
        assert (metadata / 'index').read_bytes() == before
        assert (repo / 'payload').read_text() == 'unstaged'
        return result
    result = run()
    assert result.returncode == 1 and 'SC1073' in result.stdout, result.stdout + result.stderr
    print('ok: staged syntax errors fail even when the working file is fixed')
    files['probe.sh'] = ('100755', b'#!/bin/bash\necho valid\n')
    index(files)
    (repo / 'probe.sh').write_text('#!/bin/bash\necho "broken unstaged\n')
    result = run()
    assert result.returncode == 0, result.stdout + result.stderr
    print('ok: lint and tests use staged content, with a private readable object store')
    # Match the repository-local environment supplied by a real Git hook.
    inherited = dict(os.environ, GIT_DIR=str(metadata), GIT_WORK_TREE=str(repo), GIT_INDEX_FILE=str(metadata / 'index'))
    result = subprocess.run(['bash', str(hook)], cwd=repo, env=inherited, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    print('ok: inherited Git variables cannot redirect checks to the original repository')
    snapshot = base / 'snapshot'
    snapshot.mkdir()
    subprocess.run(['bash', str(root / 'scripts/hooks/snapshot.sh'), str(repo), str(snapshot)], check=True)
    assert (snapshot / 'worktree/space \u00e9\nname').read_bytes() == b'odd path'
    assert os.readlink(snapshot / 'worktree/cache-link') == '../missing-cache'
    assert (snapshot / 'worktree/probe.sh').stat().st_mode & 0o111
    print('ok: snapshot preserves unusual filenames, symlinks, and executable bits')
    assert (repo / 'payload').read_text() == 'unstaged'
    print('ok: the real fixture worktree and index remain unchanged by checks')
PY
