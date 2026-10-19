import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import * as model from '../model.mjs'

const fixture = name => readFileSync(new URL(`./fixtures/${name}.log`, import.meta.url), 'utf8')

// Fold a log 100 ms per line, starting at epoch 1000 s, and record every
// intermediate progress value so monotonicity can be checked.
function fold(name) {
    let state = model.initialState(1000)
    const seen = []
    fixture(name).split('\n').forEach((line, i) => {
        state = model.foldLine(state, line, 1000 * 1000 + i * 100)
        seen.push(state.progress)
    })
    return { state, snap: model.snapshot(state), seen }
}

// Every fixture: progress only moves forward and stays within [0, 1].
for (const name of ['routine', 'kernel', 'conflict', 'midfail', 'busy', 'sudo', 'nothing', 'flatpak', 'verbose', 'mirror', 'depfail', 'fetchfail', 'captured']) {
    const { seen } = fold(name)
    seen.forEach((p, i) => {
        assert.ok(p >= 0 && p <= 1, `${name}: progress ${p} out of range`)
        if (i) assert.ok(p >= seen[i - 1], `${name}: progress went back at line ${i + 1}`)
    })
}

// Routine run: done, full bar, counts from the Packages header.
{
    const { snap } = fold('routine')
    assert.equal(snap.status, 'done')
    assert.equal(snap.progress, 1)
    assert.equal(snap.total, 3)
    assert.equal(snap.done, 3)
    assert.equal(snap.totalBytes, 115867648)
    assert.equal(snap.errorKind, '')
}

// A real run captured on this machine (VerbosePkgLists header, both kernel
// flavours replaced, DKMS and initramfs hooks; machine-id zeroed): it must
// fold to a full bar and name the running flavour's new kernel.
{
    const { snap } = fold('captured')
    assert.equal(snap.status, 'restart')
    assert.equal(snap.restart, '7.2.9-1-cachyos')
    assert.equal(snap.progress, 1)
    assert.equal(snap.total, 6)
    assert.equal(snap.done, 6)
    assert.ok(snap.totalBytes > 400 * 1024 ** 2, `captured: download size ${snap.totalBytes}`)
}

// Phase weights at the boundaries the card relies on.
{
    let s = model.initialState(0)
    const step = line => { s = model.foldLine(s, line, 0); return s.progress }
    step(':: Synchronizing package databases...')
    assert.equal(step(':: Starting full system upgrade...'), 0.03)
    step('Total Download Size:    100.00 MiB')
    step(':: Retrieving packages...')
    assert.ok(Math.abs(step('@@bytes 52428800') - 0.24) < 1e-9, 'half the bytes is 3% + 21%')
    assert.equal(step('checking keyring...'), 0.45)
    step('Packages (4) a-1 b-1 c-1 d-1')
    assert.equal(step(':: Processing package changes...'), 0.47)
    assert.ok(Math.abs(step('upgrading a...') - (0.47 + 0.45 / 4)) < 1e-9)
    assert.equal(s.line, 'Installing a · 1 of 4')
    assert.equal(step(':: Running post-transaction hooks...'), 0.92)
    assert.ok(Math.abs(step('(1/2) Arming ConditionNeedsUpdate...') - 0.95) < 1e-9)
    assert.equal(s.line, 'Arming ConditionNeedsUpdate')
}

// The status line: download text carries sizes and a smoothed rate. The
// first sample at t=0 must count as a baseline.
{
    let s = model.initialState(0)
    s = model.foldLine(s, 'Total Download Size:    400.00 MiB', 0)
    s = model.foldLine(s, ':: Retrieving packages...', 0)
    s = model.foldLine(s, '@@bytes 0', 0)
    s = model.foldLine(s, '@@bytes 10485760', 1000)
    assert.equal(s.key, 'download')
    assert.equal(s.line, 'Downloading · 10 MiB of 400 MiB · 10.0 MiB/s')
}

// Pre-transaction hook lines show their description without moving the bar.
{
    let s = model.initialState(0)
    s = model.foldLine(s, 'checking for file conflicts...', 0)
    const before = s.progress
    s = model.foldLine(s, '(1/1) Performing snapper pre snapshots for the following configurations...', 0)
    assert.equal(s.progress, before)
    assert.equal(s.line, 'Performing snapper pre snapshots for the following configurations')
    assert.equal(s.key, 'pre1')
}

// Kernel replaced: restart, with the new module directory name.
{
    const { snap } = fold('kernel')
    assert.equal(snap.status, 'restart')
    assert.equal(snap.restart, '7.2.9-1-cachyos')
    assert.equal(model.result(snap).title, 'Restart to finish')
}

// Conflict before the transaction: attention, nothing changed, pacman's words.
{
    const { snap } = fold('conflict')
    assert.equal(snap.status, 'attention')
    assert.equal(snap.errorKind, 'pacman')
    assert.equal(snap.error, 'failed to commit transaction (conflicting files)')
    assert.match(snap.detail, /exists in filesystem/)
    const r = model.result(snap)
    assert.equal(r.subtitle, 'The update stopped before changing anything.')
    assert.equal(r.terminal, 'pacman')
}

// An unrecorded outcome is never described as "nothing changed".
{
    const r = model.result({ status: 'attention', errorKind: 'unknown', error: 'x', detail: '', startedAt: 0, finishedAt: 5, total: 0, done: 0 })
    assert.equal(r.title, 'Update status unknown')
    assert.match(r.subtitle, /progress was not recorded/)
    assert.doesNotMatch(r.subtitle, /before changing anything/)
    assert.equal(r.terminal, 'pacman')
}

// Failure inside the transaction never claims nothing changed.
{
    const { snap } = fold('midfail')
    assert.equal(snap.status, 'failed')
    assert.equal(snap.error, 'could not extract /usr/lib/libc.so.6 (Write failed)')
    assert.equal(model.result(snap).title, 'The update did not finish')
    assert.doesNotMatch(model.result(snap).subtitle, /before changing anything/)
}

// VerbosePkgLists header: the total is still learned, and the run ends done.
{
    const { snap } = fold('verbose')
    assert.equal(snap.status, 'done')
    assert.equal(snap.total, 2)
    assert.equal(snap.done, 2)
    assert.match(model.result(snap).subtitle, /^2 packages updated in /)
    // Even if the total were missed, the installed count still reads as updated.
    assert.match(model.result({ ...snap, total: 0 }).subtitle, /^2 packages updated in /)
}

// A failing mirror is not the error; the later real conflict is.
{
    const { snap } = fold('mirror')
    assert.equal(snap.error, 'failed to commit transaction (conflicting files)')
    assert.match(snap.detail, /exists in filesystem/)
}

// Dependency explanations arrive as "::" lines; they are the detail.
{
    const { snap } = fold('depfail')
    assert.equal(snap.status, 'attention')
    assert.equal(snap.error, 'failed to prepare transaction (could not satisfy dependencies)')
    assert.equal(snap.detail, "installing foo (2-1) breaks dependency 'foo=1' required by bar")
}

// When downloads truly fail, the last retrieval failure is the reason.
{
    const { snap } = fold('fetchfail')
    assert.equal(snap.error, 'failed to commit transaction (failed to retrieve some files)')
    assert.match(snap.detail, /^failed retrieving file 'b-1-1-any\.pkg\.tar\.zst'/)
}

// Detail never grabs a progress line, and loses pacman's "error: " prefix.
{
    assert.equal(fold('midfail').snap.detail, 'problem occurred while upgrading glibc')
    let s = model.initialState(0)
    s = model.foldLine(s, 'error: something odd', 0)
    s = model.foldLine(s, 'checking keyring...', 0)
    assert.equal(s.detail, '')
}

// A new kernel keeps its restart prompt when Flatpak fails too.
{
    let s = model.initialState(1000)
    for (const l of ['@@helper-exit 0', '@@restart 7.2.9-1-cachyos', '@@phase flatpak', 'error: no bus', '@@flatpak-exit 1'])
        s = model.foldLine(s, l, 0)
    assert.equal(model.snapshot(s).status, 'running')
    assert.equal(model.snapshot(s).errorKind, '')
    assert.equal(model.result(model.snapshot(s)), null)
    s = model.foldLine(s, '@@end', 5000)
    const snap = model.snapshot(s)
    assert.equal(snap.status, 'restart')
    assert.equal(snap.errorKind, 'flatpak')
    const r = model.result(snap)
    assert.match(r.subtitle, /Flatpak apps did not update\.$/)
    assert.equal(r.terminal, 'flatpak')
}

// Busy, sudo, flatpak and nothing-to-do outcomes.
assert.equal(fold('busy').snap.errorKind, 'busy')
assert.equal(model.result(fold('busy').snap).title, 'Already updating')
assert.equal(fold('sudo').snap.errorKind, 'sudo')
assert.equal(model.result(fold('sudo').snap).title, 'One-click updates are not set up')
assert.equal(fold('flatpak').snap.status, 'attention')
assert.equal(fold('flatpak').snap.errorKind, 'flatpak')
assert.equal(model.result(fold('flatpak').snap).terminal, 'flatpak')
assert.equal(fold('nothing').snap.status, 'done')
assert.equal(fold('nothing').snap.nothing, true)
assert.equal(model.result(fold('nothing').snap).subtitle, 'Nothing needed updating')

// A stream that ends without the helper's exit is not left running once the fold closes it.
{
    let s = model.initialState(0)
    s = model.foldLine(s, ':: Processing package changes...', 0)
    s = model.foldLine(s, '@@end', 5000)
    assert.equal(model.snapshot(s).status, 'failed')
}

// Done copy uses the run's duration.
{
    const snap = { ...fold('routine').snap, startedAt: 1000, finishedAt: 1102 }
    assert.equal(model.result(snap).subtitle, '3 packages updated in 1m 42s')
}

// Summary copy.
// A saved plan: fresh for ten minutes, and the line says how old it is.
{
    const plan = { repo: [], aur: [], bytes: 0, kernel: false, checkedAt: 10000 }
    assert.equal(model.planFresh(plan, 10000), true)
    assert.equal(model.planFresh(plan, 10000 + model.PLAN_FRESH_SECONDS - 1), true)
    assert.equal(model.planFresh(plan, 10000 + model.PLAN_FRESH_SECONDS), false)
    assert.equal(model.planFresh(plan, 9990), false, 'a plan from the future (clock change) is not trusted')
    assert.equal(model.planFresh({ ...plan, checkedAt: undefined }, 10000), false)
    assert.equal(model.planFresh(null, 10000), false)
    assert.equal(model.checkedLine(plan, 10059), 'Just now')
    assert.equal(model.checkedLine(plan, 10060), '1 min ago')
    assert.equal(model.checkedLine(plan, 10000 + 25 * 60 + 30), '25 min ago')
    assert.equal(model.checkedLine(plan, 10000 + 2 * 3600 + 5), '2 h ago')
    assert.equal(model.checkedLine(plan, 9000), 'Just now', 'a clock that went back reads as now')
    assert.equal(model.checkedLine(plan, 10600, true), 'Checking…')
    assert.equal(model.checkedLine(null, 10600, true), '', 'the first check has the header spinner only')
    assert.equal(model.checkedLine({ ...plan, checkedAt: undefined }, 10600), '')
}
assert.deepEqual(model.summary(null), { title: 'Checking for updates…', subtitle: 'Syncing package databases', count: 0, repo: 0, canUpdate: false, note: '', terminal: '', busy: true })
{
    const plan = { repo: [{ name: 'a' }, { name: 'b' }], aur: [{ name: 'c' }], bytes: 434110464, kernel: true }
    assert.deepEqual(model.summary(plan), {
        title: '3 updates', subtitle: '414 MiB to download · restart needed after',
        count: 3, repo: 2, canUpdate: true, note: '1 of them from the AUR', terminal: 'aur', busy: false,
    })
    assert.equal(model.summary({ ...plan, bytes: 0 }).subtitle, 'Already downloaded · restart needed after')
    assert.equal(model.summary({ repo: [], aur: [{ name: 'c' }], bytes: 0, kernel: false }).canUpdate, false)
    assert.equal(model.summary({ repo: [], aur: [], bytes: 0, kernel: false }).title, 'Up to date')
    assert.equal(model.summary(null, 'checkupdates failed').title, 'Could not check for updates')
    assert.equal(model.summary(null, 'x').busy, false)
    assert.equal(model.summary({ repo: [], aur: [], bytes: 0, kernel: false }).busy, false)
    assert.equal(model.summary(plan).busy, false)
}

// Version tail: only the changed part, backed up to the start of its token.
assert.deepEqual(model.versionTail('1:26.2.1-1', '1:26.2.2-1'), ['1:26.2.', '2-1'])
assert.deepEqual(model.versionTail('152.0-1', '152.0.1-1'), ['152.', '0.1-1'])
assert.deepEqual(model.versionTail('580.95.05-1', '580.105.08-1'), ['580.', '105.08-1'])
assert.deepEqual(model.versionTail('8.17.0-1', '8.17.0-2'), ['8.17.0-', '2'])
assert.equal(model.versionMarkup('1.0-1', '1.0-2', '#6097a1'), '1.0-<font color="#6097a1">2</font>')
assert.equal(model.versionMarkup('1<2', '1<3', '#fff'), '1&lt;<font color="#fff">3</font>')

// A warning between the error and its explanation does not swallow the explanation.
{
    let s = model.initialState(0)
    for (const line of ['error: failed to commit transaction (invalid or corrupted package)',
                        'warning: something', 'x.pkg is invalid or corrupted'])
        s = model.foldLine(s, line, 0)
    assert.equal(s.detail, 'x.pkg is invalid or corrupted')
}

// Sizes and durations.
assert.equal(model.mib(0), '0 MiB')
assert.equal(model.mib(512 * 1024), '512 KiB')
assert.equal(model.mib(434110464), '414 MiB')
assert.equal(model.mib(1.5 * 1024 ** 3), '1.5 GiB')
assert.equal(model.duration(42), '42s')
assert.equal(model.duration(102), '1m 42s')

// Glide: eases toward the target, never backward, snaps when close.
assert.equal(model.glide(0.5, 0.4, 0.016), 0.5)
assert.ok(model.glide(0, 1, 0.016) > 0 && model.glide(0, 1, 0.016) < 0.1)
assert.equal(model.glide(0.9996, 1, 0.016), 1)

// Summary counts Flatpak; only repo packages make the card's Update possible.
{
    const plan = { repo: [{ name: 'a' }], aur: [], bytes: 0, kernel: false, flatpak: 2 }
    assert.equal(model.summary(plan).count, 3)
    assert.equal(model.summary(plan).title, '3 updates')
    assert.equal(model.summary(plan).canUpdate, true)
    assert.equal(model.summary(Object.assign({}, plan, { repo: [] })).canUpdate, false)
}

// Every pending mix has a way to apply it: Update runs repo then Flatpak, the AUR
// link's update.sh runs the helper then Flatpak, and Flatpak alone gets its own link.
{
    const pkg = [{ name: 'a' }], none = []
    const link = (repo, aur, flatpak) => {
        const s = model.summary({ repo, aur, bytes: 0, kernel: false, flatpak })
        return [s.canUpdate, s.terminal, s.note]
    }
    assert.deepEqual(link(pkg, none, 0), [true, '', ''])
    assert.deepEqual(link(pkg, none, 2), [true, '', ''])
    assert.deepEqual(link(none, pkg, 0), [false, 'aur', '1 of them from the AUR'])
    assert.deepEqual(link(none, pkg, 2), [false, 'aur', '1 of them from the AUR'])
    assert.deepEqual(link(pkg, pkg, 2), [true, 'aur', '1 of them from the AUR'])
    assert.deepEqual(link(none, none, 1), [false, 'flatpak', '1 Flatpak app'])
    assert.deepEqual(link(none, none, 3), [false, 'flatpak', '3 Flatpak apps'])
    // The plan's byte count covers repo packages only, so it says nothing without them.
    assert.equal(model.summary({ repo: none, aur: none, bytes: 0, kernel: false, flatpak: 2 }).subtitle, 'Runs in a terminal')
    assert.equal(model.summary({ repo: none, aur: pkg, bytes: 0, kernel: false }).subtitle, 'Runs in a terminal')
    assert.equal(model.summary({ repo: pkg, aur: none, bytes: 0, kernel: false, flatpak: 2 }).subtitle, 'Already downloaded')
}

// Waybar tooltip (scripts/waybar/updates.sh through scripts/updates/tooltip.mjs).
{
    const dim = text => `<span alpha='55%'>${text}</span>`
    const restart = String.fromCodePoint(0xf0709)

    // Pending: rows for non-zero sources, size on the repo row, kernel line.
    const plan = { repo: [{ name: 'a' }, { name: 'b' }], aur: [{ name: 'c' }], bytes: 434110464, kernel: true, flatpak: 0 }
    assert.equal(model.tooltip({ state: 'pending', icon: 'U', plan, checked: '14:32' }), [
        'U  <b>3 updates</b>',
        '',
        '  Repo  2   414 MiB',
        '  AUR   1',
        '',
        `${restart}  Kernel · restart after`,
        '',
        dim('Checked 14:32'),
        dim('Click: review updates'),
        dim('Right-click: check now'),
    ].join('\n'))

    // Alignment across label and digit widths; nothing to download reads "cached".
    const lines = model.tooltip({ state: 'pending', icon: 'U',
        plan: { repo: [{ name: 'a' }], aur: [], bytes: 0, kernel: false, flatpak: 12 }, checked: '09:05' }).split('\n')
    assert.equal(lines[0], 'U  <b>13 updates</b>')
    assert.equal(lines[2], '  Repo      1   cached')
    assert.equal(lines[3], '  Flatpak  12')
    assert.ok(!lines.some(l => l.includes('Kernel')), 'no kernel line without a kernel update')
    assert.ok(!lines.some(l => l.includes('AUR')), 'a zero source has no row')
    assert.match(model.tooltip({ state: 'pending', icon: 'U',
        plan: { repo: [{ name: 'a' }], aur: [], bytes: 1, kernel: false }, checked: '' }), /<b>1 update<\/b>/)

    // Running: the bar's own glyph and percentage, and pacman's current step.
    assert.equal(model.tooltip({ state: 'running', icon: 'S', pct: 42, snap: { line: 'Installing (12/40)' } }),
        ['S  <b>Updating · 42%</b>', '', '  Installing (12/40)', '', dim('Click: show progress')].join('\n'))
    assert.match(model.tooltip({ state: 'running', icon: 'S', pct: 0, snap: null }), /  Starting…/)
    assert.match(model.tooltip({ state: 'running', icon: 'S', pct: 1, snap: { line: 'a < b & c' } }), /  a &lt; b &amp; c/)

    // Restart: the card's title, what was updated, which kernel boots next.
    const snap = { status: 'restart', restart: '7.2.9-1-cachyos', errorKind: '', error: '', detail: '',
                   total: 15, done: 15, startedAt: 1000, finishedAt: 1063 }
    assert.equal(model.tooltip({ state: 'restart', snap }), [
        `${restart}  <b>Restart to finish</b>`,
        '',
        '  15 packages updated in 1m 3s',
        '  Kernel 7.2.9-1-cachyos loads on next boot',
        '',
        dim('Click: open result'),
    ].join('\n'))
    assert.match(model.tooltip({ state: 'restart', snap: Object.assign({}, snap, { errorKind: 'flatpak' }) }),
        /\n  Flatpak apps did not update\n/)

    // Attention: the card's result copy, the first reason line escaped, and
    // what is still waiting when the plan has anything.
    const failed = { status: 'failed', errorKind: '', error: 'failed to commit transaction (a & <b>)',
                     detail: 'second line', startedAt: 0, finishedAt: 5, total: 0, done: 0 }
    const t = model.tooltip({ state: 'attention', icon: 'U', snap: failed, plan })
    assert.equal(t.split('\n').slice(0, 4).join('\n'), [
        'U  <b>The update did not finish</b>',
        '',
        '  pacman stopped partway through. Finish it in a terminal.',
        '  failed to commit transaction (a &amp; &lt;b&gt;)',
    ].join('\n'))
    assert.doesNotMatch(t, /second line/)
    assert.match(t, /\n\n  3 updates waiting\n  Repo  2   414 MiB\n  AUR   1\n/)
    assert.ok(t.endsWith(`\n\n${dim('Click: open details')}`))
    assert.doesNotMatch(model.tooltip({ state: 'attention', icon: 'U', snap: failed, plan: null }), /waiting/)

    // Blocked (planner exit 3): the planner's reason, escaped.
    assert.equal(model.tooltip({ state: 'blocked', icon: 'U', reason: 'pacman cannot resolve this upgrade; a & b' }),
        ['U  <b>Updates need a terminal</b>', '', '  pacman cannot resolve this upgrade; a &amp; b', '',
         dim('Click: details')].join('\n'))
}

console.log('model: ok')
