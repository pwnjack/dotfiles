// Pure model shared by the update card (QML imports it) and the runner's fold
// (scripts/updates/fold.mjs runs it under node), so the bar's percentage and
// the card's can never disagree. No I/O and no clock: callers pass time in.
//
// Input is the runner's log: pacman's own output under LC_ALL=C, interleaved
// with @@ markers from the root helper (@@phase, @@bytes, @@busy) and the
// runner (@@helper-exit, @@phase flatpak, @@flatpak-exit, @@restart, @@end).
// Measured on pacman 7.1: without a terminal pacman prints one plain line per
// step ("upgrading mesa...") with no counter, which is why the package total
// comes from pacman's "Packages (N)" header (or "Package (N)" followed by a
// column-title row under VerbosePkgLists, which this machine sets).

const UNITS = { B: 1, KiB: 1024, MiB: 1024 ** 2, GiB: 1024 ** 3, TiB: 1024 ** 4 }
const ORDER = ['sync', 'download', 'checks', 'install', 'hooks', 'flatpak']
const TEXT = {
    sync: 'Syncing package databases',
    checks: 'Checking keys and file conflicts',
    install: 'Installing',
    hooks: 'Finishing up',
    flatpak: 'Updating Flatpak apps',
}
// Exit status the root helper uses when another update holds its lock.
export const BUSY_EXIT = 75

export function initialState(startedAt) {
    return {
        phase: 'sync', key: 'sync', line: TEXT.sync, progress: 0, started: false,
        bytes: 0, totalBytes: 0, rate: 0, sampleAt: -1, sampleBytes: 0,
        total: 0, done: 0, hookIndex: 0, hookTotal: 0,
        transaction: false, nothing: false, busy: false, sudo: false,
        error: '', detail: '', awaitingDetail: false, fetchFail: '',
        helperExit: null, flatpakExit: null, restart: '', ended: false,
        startedAt, finishedAt: 0,
    }
}

// Phases only move forward: pacman repeats "checking keyring..." and
// ":: Starting full system upgrade..." in the install pass.
function enter(s, phase, key, line) {
    if (ORDER.indexOf(phase) < ORDER.indexOf(s.phase)) return
    s.phase = phase
    s.key = key
    s.line = line
}

function downloadLine(s) {
    const rate = s.rate >= 0.05 * UNITS.MiB ? ` · ${(s.rate / UNITS.MiB).toFixed(1)} MiB/s` : ''
    return s.totalBytes ? `Downloading · ${mib(s.bytes)} of ${mib(s.totalBytes)}${rate}` : `Downloading${rate}`
}

// @@bytes: bytes added to the package cache so far, sampled every 0.5 s by
// the helper. The rate is smoothed so the status line does not flicker.
function foldBytes(s, bytes, nowMs) {
    if (s.sampleAt >= 0 && nowMs > s.sampleAt) {
        const instant = Math.max(0, (bytes - s.sampleBytes) / ((nowMs - s.sampleAt) / 1000))
        s.rate = s.rate ? s.rate * 0.7 + instant * 0.3 : instant
    }
    s.sampleAt = nowMs
    s.sampleBytes = bytes
    s.bytes = Math.max(s.bytes, s.totalBytes ? Math.min(bytes, s.totalBytes) : bytes)
    if (s.phase === 'download') s.line = downloadLine(s)
}

export function status(s) {
    if (!s.ended) return 'running'
    if (s.helperExit === 0) {
        // A new kernel outranks a Flatpak failure: the restart prompt must survive.
        if (s.restart) return 'restart'
        return s.flatpakExit ? 'attention' : 'done'
    }
    return s.transaction ? 'failed' : 'attention'
}

export function errorKind(s) {
    if (!s.ended) return ''
    if (s.helperExit === 0) return s.flatpakExit ? 'flatpak' : ''
    if (s.busy || s.helperExit === BUSY_EXIT) return 'busy'
    if (s.sudo) return 'sudo'
    return s.transaction ? 'transaction' : 'pacman'
}

// Weighted target: sync 0-3%, download 3-45% by bytes, checks 45%,
// install 47-92% by package count, hooks 92-98%, flatpak 98%, success 100%.
export function target(s) {
    const outcome = status(s)
    if (outcome === 'done' || outcome === 'restart') return 1
    switch (s.phase) {
    case 'sync': return s.started ? 0.03 : 0.01
    case 'download': return 0.03 + 0.42 * (s.totalBytes ? Math.min(1, s.bytes / s.totalBytes) : 0)
    case 'checks': return 0.45
    case 'install': return 0.47 + 0.45 * (s.total ? Math.min(s.done, s.total) / s.total : 0)
    case 'hooks': return 0.92 + 0.06 * (s.hookTotal ? s.hookIndex / s.hookTotal : 0)
    case 'flatpak': return 0.98
    }
    return 0
}

// Lines that are progress, not an explanation of an error.
function isProgressLine(line) {
    return line.startsWith('@@') || line.startsWith('warning: ')
        || /^:: (Synchronizing package databases|Starting full system upgrade|Retrieving packages|Processing package changes|Running (pre|post)-transaction hooks|Proceed with )/.test(line)
        || /^checking /.test(line)
        || /^(upgrading|installing|reinstalling|downgrading|removing) /.test(line)
        || /^\(\d+\/\d+\) /.test(line)
        || /^error: failed retrieving file /.test(line)
}

export function foldLine(prev, raw, nowMs = 0) {
    // Object.assign, not object spread: Qt's V4 engine (the card imports this
    // file) rejects `{ ...prev }` as a syntax error.
    const s = Object.assign({}, prev)
    const line = String(raw).replace(/\r$/, '')
    let m
    // The line after pacman's first "error:" says why (the conflicting file,
    // the broken dependency); keep it for the card's reason box. A progress
    // line means there was no explanation line.
    if (s.awaitingDetail && line.trim() && !line.startsWith('warning: ')) {
        if (isProgressLine(line)) s.awaitingDetail = false
        else {
            if (!line.startsWith('Errors occurred')) s.detail = line.trim().replace(/^(error:|::) /, '')
            s.awaitingDetail = false
        }
    }
    if ((m = /^@@bytes (-?\d+)$/.exec(line))) foldBytes(s, Math.max(0, Number(m[1])), nowMs)
    else if (line === '@@phase install') enter(s, 'checks', 'checks', TEXT.checks)
    else if (line === '@@phase flatpak') enter(s, 'flatpak', 'flatpak', TEXT.flatpak)
    else if (line === '@@busy') s.busy = true
    else if ((m = /^@@helper-exit (\d+)$/.exec(line))) s.helperExit = Number(m[1])
    else if ((m = /^@@flatpak-exit (\d+)$/.exec(line))) s.flatpakExit = Number(m[1])
    else if ((m = /^@@restart (.+)$/.exec(line))) s.restart = m[1]
    else if (line === '@@end') { s.ended = true; s.finishedAt = Math.floor(nowMs / 1000) }
    else if (line.startsWith(':: Synchronizing package databases')) enter(s, 'sync', 'sync', TEXT.sync)
    else if (line.startsWith(':: Starting full system upgrade')) s.started = true
    else if ((m = /^Packages? \((\d+)\)/.exec(line))) { if (!s.total) s.total = Number(m[1]) }
    else if ((m = /^Total Download Size:\s+([\d.]+) (B|KiB|MiB|GiB|TiB)\s*$/.exec(line))) {
        if (!s.totalBytes) s.totalBytes = Math.round(Number(m[1]) * UNITS[m[2]])
    }
    else if (line.startsWith(':: Retrieving packages')) { enter(s, 'download', 'download', ''); s.line = downloadLine(s) }
    else if (/^checking (keyring|package integrity|for file conflicts|available disk space)/.test(line)
             || line.startsWith(':: Running pre-transaction hooks')) enter(s, 'checks', 'checks', TEXT.checks)
    else if (line.startsWith(':: Processing package changes')) {
        s.transaction = true
        enter(s, 'install', 'install', s.total ? `Installing · 0 of ${s.total}` : TEXT.install)
    }
    else if ((m = /^(upgrading|installing|reinstalling|downgrading|removing) (\S+)\.\.\.$/.exec(line))) {
        s.done += 1
        const verb = m[1] === 'removing' ? 'Removing' : 'Installing'
        const count = s.total ? ` · ${Math.min(s.done, s.total)} of ${s.total}` : ''
        enter(s, 'install', 'install', `${verb} ${m[2]}${count}`)
    }
    else if (line.startsWith(':: Running post-transaction hooks')) enter(s, 'hooks', 'hooks', TEXT.hooks)
    else if ((m = /^\((\d+)\/(\d+)\) (.+?)(?:\.\.\.)?$/.exec(line))) {
        if (s.phase === 'hooks') {
            s.hookIndex = Number(m[1])
            s.hookTotal = Number(m[2])
            s.key = `hook${m[1]}`
            s.line = m[3]
        } else if (s.phase === 'checks') {
            s.key = `pre${m[1]}`
            s.line = m[3]
        }
    }
    else if (line.trim() === 'there is nothing to do') s.nothing = true
    // One failing mirror followed by a working one is not an error; real
    // download failure ends in "failed to commit transaction (failed to retrieve ...)".
    // It is kept as the fallback reason in case downloads truly fail.
    else if (/^error: failed retrieving file /.test(line)) s.fetchFail = line.slice('error: '.length)
    else if ((m = /^error: (.+)$/.exec(line))) {
        if (!s.error) { s.error = m[1]; s.awaitingDetail = true }
    }
    else if ((m = /^sudo: (.+)$/.exec(line))) { s.sudo = true; if (!s.error) s.error = m[1] }
    s.progress = Math.max(prev.progress, target(s))
    return s
}

// The JSON written to state.json and read by the card and the bar.
export function snapshot(s) {
    return {
        status: status(s), phase: s.phase, key: s.key, line: s.line,
        progress: Math.round(s.progress * 10000) / 10000,
        done: s.total ? Math.min(s.done, s.total) : s.done, total: s.total,
        bytes: s.bytes, totalBytes: s.totalBytes,
        error: s.error, detail: s.detail || (s.error ? s.fetchFail : ''), errorKind: errorKind(s),
        restart: s.restart, nothing: s.nothing,
        startedAt: s.startedAt, finishedAt: s.finishedAt,
    }
}

export function mib(bytes) {
    if (bytes <= 0) return '0 MiB'
    if (bytes < UNITS.MiB) return `${Math.max(1, Math.round(bytes / UNITS.KiB))} KiB`
    if (bytes < UNITS.GiB) return `${Math.round(bytes / UNITS.MiB)} MiB`
    return `${(bytes / UNITS.GiB).toFixed(1)} GiB`
}

export function duration(seconds) {
    const s = Math.max(0, Math.round(seconds))
    return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${s % 60}s`
}

// ① Summary copy. `plan` is updates-plan.sh's JSON, null while it loads.
// `terminal` names the terminal.sh path the card links to when Update cannot
// cover everything: AUR (update.sh also runs Flatpak), or Flatpak on its own.
export function summary(plan, error = '') {
    const idle = (title, subtitle, busy = false) => ({ title, subtitle, count: 0, repo: 0, canUpdate: false, note: '', terminal: '', busy })
    if (error) return idle('Could not check for updates', error)
    if (!plan) return idle('Checking for updates…', 'Syncing package databases', true)
    const repo = plan.repo.length, aur = plan.aur.length, flatpak = plan.flatpak || 0
    const count = repo + aur + flatpak
    if (!count) return idle('Up to date', 'Nothing to install')
    // plan.bytes is the repo download only; AUR and Flatpak sizes are unknown here.
    const size = !repo ? 'Runs in a terminal' : plan.bytes ? `${mib(plan.bytes)} to download` : 'Already downloaded'
    let note = '', terminal = ''
    if (aur) { note = `${aur} of them from the AUR`; terminal = 'aur' }
    else if (!repo) { note = `${flatpak} Flatpak app${flatpak === 1 ? '' : 's'}`; terminal = 'flatpak' }
    return {
        title: `${count} update${count === 1 ? '' : 's'}`,
        subtitle: size + (plan.kernel ? ' · restart needed after' : ''),
        count, repo, canUpdate: repo > 0, note, terminal, busy: false,
    }
}

// A saved plan (updates-plan.sh --cached) younger than this opens the card
// without a new check; an older one is shown while a new check runs.
export const PLAN_FRESH_SECONDS = 600

export function planFresh(plan, nowSeconds) {
    return !!plan && typeof plan.checkedAt === 'number'
        && nowSeconds - plan.checkedAt >= 0 && nowSeconds - plan.checkedAt < PLAN_FRESH_SECONDS
}

// The summary's freshness line, after a clock glyph beside the buttons: how
// long ago the shown plan was checked, or that a newer check is under way.
// Short, because it shares the row with Later and Update. Empty while there
// is no plan to date.
export function checkedLine(plan, nowSeconds, refreshing = false) {
    if (!plan) return ''
    if (refreshing) return 'Checking…'
    if (typeof plan.checkedAt !== 'number') return ''
    const age = Math.max(0, nowSeconds - plan.checkedAt)
    if (age < 60) return 'Just now'
    if (age < 3600) return `${Math.floor(age / 60)} min ago`
    return `${Math.floor(age / 3600)} h ago`
}

// ② Running copy. `run` is a state.json snapshot, null until the runner reports.
export function runningSubtitle(run) {
    return run && run.total ? `${run.total} packages · you can close this` : 'You can close this'
}
export function runningLine(run) { return run ? run.line : 'Starting…' }
export function runningKey(run) { return run ? run.key : 'start' }

function reasonText(s) { return [s.error, s.detail].filter(Boolean).join('\n') }

// "15 packages updated in 1m 3s": the card's result and the bar's tooltip.
function updatedText(snap) {
    const took = duration(Math.max(0, snap.finishedAt - snap.startedAt))
    const count = snap.total || snap.done
    return count
        ? `${count} package${count === 1 ? '' : 's'} updated in ${took}`
        : 'Nothing needed updating'
}

// ③ Result copy for a finished snapshot; null while the run is still going.
export function result(snap) {
    if (snap.status === 'running') return null
    const updated = updatedText(snap)
    switch (snap.status) {
    case 'done':
        return { kind: 'done', tone: 'ok', title: 'Up to date', subtitle: updated, reason: '', terminal: '' }
    case 'restart': {
        const flatpak = snap.errorKind === 'flatpak'
        return { kind: 'restart', tone: 'info', title: 'Restart to finish',
                 subtitle: `${updated}. The new kernel (${snap.restart}) loads on the next boot.`
                     + (flatpak ? ' Flatpak apps did not update.' : ''),
                 reason: flatpak ? reasonText(snap) : '', terminal: flatpak ? 'flatpak' : '' }
    }
    case 'failed':
        return { kind: 'failed', tone: 'warn', title: 'The update did not finish',
                 subtitle: 'pacman stopped partway through. Finish it in a terminal.', reason: reasonText(snap), terminal: 'pacman' }
    }
    switch (snap.errorKind) {
    case 'busy':
        return { kind: 'attention', tone: 'warn', title: 'Already updating',
                 subtitle: 'Another update holds the package database. Try again when it finishes.', reason: '', terminal: '' }
    case 'sudo':
        return { kind: 'attention', tone: 'warn', title: 'One-click updates are not set up',
                 subtitle: 'Run updates/setup-sudo.sh once, or update in a terminal.', reason: snap.error, terminal: 'pacman' }
    case 'flatpak':
        return { kind: 'attention', tone: 'warn', title: 'Flatpak apps did not update',
                 subtitle: 'System packages are up to date.', reason: reasonText(snap), terminal: 'flatpak' }
    case 'unknown':
        return { kind: 'attention', tone: 'warn', title: 'Update status unknown',
                 subtitle: 'The update ran, but its progress was not recorded. Check run.log or a terminal.',
                 reason: reasonText(snap), terminal: 'pacman' }
    }
    return { kind: 'attention', tone: 'warn', title: 'Needs your attention',
             subtitle: 'The update stopped before changing anything.', reason: reasonText(snap), terminal: 'pacman' }
}

// Only the changed tail of a version, backed up to the start of its token so
// "152.0-1 -> 152.0.1-1" highlights "0.1-1", not ".1-1".
export function versionTail(oldVersion, newVersion) {
    let i = 0
    while (i < oldVersion.length && i < newVersion.length && oldVersion[i] === newVersion[i]) i++
    while (i > 0 && /[0-9A-Za-z]/.test(newVersion[i - 1])) i--
    return [newVersion.slice(0, i), newVersion.slice(i)]
}

function escapeHtml(text) {
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

// Text.StyledText markup for a package row's version.
export function versionMarkup(oldVersion, newVersion, color) {
    const [head, tail] = versionTail(oldVersion, newVersion)
    return `${escapeHtml(head)}<font color="${color}">${escapeHtml(tail)}</font>`
}

// The displayed bar value: an exponential ease (~280 ms) toward the target
// that never moves backward and snaps when within 0.05%.
export function glide(shown, targetValue, dtSeconds) {
    if (targetValue <= shown) return shown
    if (targetValue - shown < 0.0005) return targetValue
    return shown + (targetValue - shown) * (1 - Math.exp(-dtSeconds / 0.28))
}

// ④ Waybar tooltip for custom/updates (scripts/waybar/updates.sh runs it
// through scripts/updates/tooltip.mjs). Pango markup, one string. `input`:
//   state    pending | running | restart | attention | blocked
//   icon     the glyph the bar shows, so the header matches it
//   plan     updates-plan.sh's JSON (pending, attention when it has one)
//   snap     state.json (running may be null; restart and attention)
//   pct      the bar's percentage (running)
//   checked  "HH:MM" of the check, formatted by the caller (pending)
//   reason   the planner's stderr line (blocked)
// No destructuring defaults and no spread: QML's V4 engine imports this file.
const RESTART_GLYPH = String.fromCodePoint(0xf0709)

function dim(text) { return `<span alpha='55%'>${text}</span>` }
function heading(glyph, title) { return `${glyph}  <b>${escapeHtml(title)}</b>` }
function plural(n, word) { return `${n} ${word}${n === 1 ? '' : 's'}` }
function planCount(plan) { return plan.repo.length + plan.aur.length + (plan.flatpak || 0) }

// One row per non-zero source: labels padded to the longest, counts
// right-aligned, the download size on the repo row only. The bar font is
// monospaced, so spaces align.
function planRows(plan) {
    const rows = [['Repo', plan.repo.length], ['AUR', plan.aur.length], ['Flatpak', plan.flatpak || 0]]
        .filter(row => row[1] > 0)
    const label = Math.max.apply(null, rows.map(row => row[0].length))
    const digits = Math.max.apply(null, rows.map(row => String(row[1]).length))
    return rows.map(row => {
        const line = `  ${row[0].padEnd(label)}  ${String(row[1]).padStart(digits)}`
        return row[0] === 'Repo' ? `${line}   ${plan.bytes ? mib(plan.bytes) : 'cached'}` : line
    })
}

export function tooltip(input) {
    const icon = input.icon || ''
    const plan = input.plan || null
    const snap = input.snap || null
    let lines
    switch (input.state) {
    case 'running':
        lines = [heading(icon, `Updating · ${input.pct || 0}%`), '',
                 `  ${escapeHtml(runningLine(snap))}`, '', dim('Click: show progress')]
        break
    case 'restart':
        lines = [heading(RESTART_GLYPH, result(snap).title), '', `  ${updatedText(snap)}`,
                 `  Kernel ${escapeHtml(snap.restart || '')} loads on next boot`]
        if (snap.errorKind === 'flatpak') lines.push('  Flatpak apps did not update')
        lines.push('', dim('Click: open result'))
        break
    case 'attention': {
        const r = result(snap)
        lines = [heading(icon, r.title), '', `  ${escapeHtml(r.subtitle)}`]
        const why = r.reason.split('\n')[0]
        if (why) lines.push(`  ${escapeHtml(why)}`)
        if (plan && planCount(plan)) lines = lines.concat(['', `  ${plural(planCount(plan), 'update')} waiting`], planRows(plan))
        lines.push('', dim('Click: open details'))
        break
    }
    case 'blocked':
        lines = [heading(icon, 'Updates need a terminal'), '', `  ${escapeHtml(input.reason || '')}`, '', dim('Click: details')]
        break
    default:
        lines = [heading(icon, plural(planCount(plan), 'update')), ''].concat(planRows(plan))
        if (plan.kernel) lines.push('', `${RESTART_GLYPH}  Kernel · restart after`)
        lines.push('', dim(`Checked ${escapeHtml(input.checked || '')}`), dim('Click: review updates'), dim('Right-click: check now'))
    }
    return lines.join('\n')
}
