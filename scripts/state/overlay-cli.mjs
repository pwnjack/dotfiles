// I/O around overlay.mjs. Called by overlay.sh, which holds the lock.
//
//   overlay-cli.mjs sync <config dir> <state dir> [--replace <backup dir>] [--restore] [<live path>...]
//   overlay-cli.mjs check <config dir> <state dir>
//
// Targets are the files under <config dir>/defaults (options/ as one directory
// target). Each is synced independently: one failing never stops the others,
// and the exit status is 1 when any failed.
import fs from 'node:fs'
import path from 'node:path'
import { execSync } from 'node:child_process'
import * as overlay from './overlay.mjs'

const [command, config, state, ...rest] = process.argv.slice(2)

function readText(file) {
    try { return fs.readFileSync(file, 'utf8') }
    catch (error) { if (error.code === 'ENOENT') return null; throw error }
}
// Writes only when the content differs, through a rename, so a reader never
// sees a partial file and an unchanged sync touches nothing.
function writeAtomic(file, text) {
    if (readText(file) === text) return
    fs.mkdirSync(path.dirname(file), { recursive: true })
    const temp = path.join(path.dirname(file), `.${path.basename(file)}.overlay-tmp`)
    const fd = fs.openSync(temp, 'w')
    try { fs.writeSync(fd, text); fs.fsyncSync(fd) } finally { fs.closeSync(fd) }
    fs.renameSync(temp, file)
}
// Regular files only: options/wallpaper is a symlink and never a key. Dot-files
// and editor leftovers (`name~`, emacs `#name#`) are not keys either.
const isKeyName = name => !name.startsWith('.') && !name.endsWith('~') && !/^#.*#$/.test(name)
function readDir(dir) {
    let names
    try { names = fs.readdirSync(dir, { withFileTypes: true }) }
    catch (error) { if (error.code === 'ENOENT') return null; throw error }
    const entries = new Map()
    for (const entry of names) {
        if (entry.isFile() && isKeyName(entry.name)) entries.set(entry.name, fs.readFileSync(path.join(dir, entry.name), 'utf8'))
    }
    return entries
}
function writeDir(dir, entries) {
    fs.mkdirSync(dir, { recursive: true })
    for (const [name, value] of entries) writeAtomic(path.join(dir, name), value)
    for (const name of readDir(dir)?.keys() ?? []) if (!entries.has(name)) fs.rmSync(path.join(dir, name))
}

function discover() {
    const root = path.join(config, 'defaults')
    const found = []
    const walk = rel => {
        for (const entry of fs.readdirSync(path.join(root, rel), { withFileTypes: true })) {
            if (!isKeyName(entry.name)) continue
            const child = rel ? `${rel}/${entry.name}` : entry.name
            if (child === 'options') found.push(child)
            else if (entry.isDirectory()) walk(child)
            else if (entry.isFile()) found.push(child)
        }
    }
    walk('')
    return found.sort()
}

// A target named by its live path, absolute or relative; options/<key> is options.
function normalise(name, known) {
    let rel = path.isAbsolute(name) ? path.relative(config, name) : name
    if (rel.startsWith('options/')) rel = 'options'
    if (!known.includes(rel)) throw new Error(`${name} is not an overlay target`)
    return rel
}

function paths(target) {
    const overrides = path.join(state, 'overrides', target)
    return {
        defaults: path.join(config, 'defaults', target),
        live: path.join(config, target),
        overrides,
        removed: overrides + '.removed',
        last: path.join(state, 'last', target),
    }
}

// Copies what --replace is about to supersede into the backup directory. It
// never deletes: the render's own atomic rename replaces the file, so a target
// that fails to render keeps its live file byte-identical.
function sameLive(isDir, before, after) {
    if (!isDir) return before === after
    if (before === null || after === null) return before === after
    if (before.size !== after.size) return false
    for (const [name, value] of before) if (after.get(name) !== value) return false
    return true
}

function backupLive(target, live, backup, declared) {
    if (!backup) return
    if (overlay.formatFor(target) === 'dir') {
        for (const name of readDir(live)?.keys() ?? []) {
            if (!declared.has(name)) continue
            fs.mkdirSync(path.join(backup, target), { recursive: true })
            fs.copyFileSync(path.join(live, name), path.join(backup, target, name))
        }
        return
    }
    if (readText(live) === null) return
    fs.mkdirSync(path.dirname(path.join(backup, target)), { recursive: true })
    fs.copyFileSync(live, path.join(backup, target))
}

// Another writer (a panel, apply-font, `echo >`) may change a live file between
// our read and our write. Re-reading just before the write detects that, and the
// target is redone from the start.
class Raced extends Error {}
const MAX_ATTEMPTS = 3

function syncTarget(target, replace, restore) {
    for (let attempt = 1; ; attempt++) {
        try { return syncOnce(target, replace, restore) }
        catch (error) {
            if (!(error instanceof Raced)) throw error
            if (attempt >= MAX_ATTEMPTS) throw new Error(`${target} kept changing while it was synced; run the sync again`)
        }
    }
}

function syncOnce(target, replace, restore) {
    const format = overlay.formatFor(target)
    const p = paths(target)
    const isDir = format === 'dir'
    const load = file => {
        if (isDir) return readDir(file)
        const text = readText(file)
        return text === null ? null : overlay.parse(format, text)
    }
    // Everything that can throw is read and parsed before anything is changed.
    const defaultsText = isDir ? null : readText(p.defaults)
    const defaults = isDir ? readDir(p.defaults) : overlay.parse(format, defaultsText)
    const overrides = load(p.overrides) ?? new Map()
    const removed = new Set((readText(p.removed) ?? '').split('\n').filter(Boolean))
    const last = load(p.last)
    let live
    // What was read from the live file, to detect a change before writing it.
    const snapshot = isDir ? readDir(p.live) : readText(p.live)
    if (replace !== undefined && last === null) {
        // No render record: the live file predates the overlay. Back it up and
        // start from the defaults; options the defaults do not declare are
        // per-machine and stay live, to be adopted as overrides.
        backupLive(target, p.live, replace, defaults)
        // Declared keys carry their default, so harvest sees no change for them
        // and recorded overrides survive; null skips harvest for file targets.
        live = isDir ? new Map([...(readDir(p.live) ?? []), ...defaults]) : null
    } else {
        live = load(p.live) // throws on a malformed file: the target is skipped untouched
        if (restore && isDir) {
            // Git removed the old tracked option files while checking out a commit
            // without the overlay. A declared key missing from live is that, not a
            // reset: treat it as unchanged so its override survives.
            live = live ?? new Map()
            for (const [key, value] of defaults) if (!live.has(key)) live.set(key, last?.get(key) ?? value)
        }
    }
    const next = overlay.harvest(format, { defaults, last, live, overrides, removed })
    const entries = overlay.effective(defaults, next.overrides, next.removed)
    if (process.env.OVERLAY_TEST_BEFORE_WRITE) execSync(process.env.OVERLAY_TEST_BEFORE_WRITE, { stdio: 'inherit' })
    if (!sameLive(isDir, snapshot, isDir ? readDir(p.live) : readText(p.live))) throw new Raced()
    if (isDir) {
        writeDir(p.overrides, next.overrides)
        writeDir(p.live, entries)
        writeDir(p.last, entries)
        return
    }
    const saved = overlay.serialize(format, next.overrides)
    if (saved) writeAtomic(p.overrides, saved); else fs.rmSync(p.overrides, { force: true })
    if (next.removed.size) writeAtomic(p.removed, [...next.removed].join('\n') + '\n'); else fs.rmSync(p.removed, { force: true })
    const text = overlay.layout(format, defaultsText, entries)
    writeAtomic(p.live, text)
    writeAtomic(p.last, text)
}

let failed = false
const known = discover()
if (command === 'sync') {
    let replace
    let restore = false
    const names = []
    for (let i = 0; i < rest.length; i++) {
        if (rest[i] === '--replace') replace = rest[++i] ?? ''
        else if (rest[i] === '--restore') restore = true
        else names.push(rest[i])
    }
    let chosen = known
    try { if (names.length) chosen = [...new Set(names.map(name => normalise(name, known)))] }
    catch (error) { console.error(`overlay: ${error.message}`); process.exit(2) }
    for (const target of chosen) {
        try { syncTarget(target, replace, restore) }
        catch (error) { failed = true; console.error(`overlay: ${target}: ${error.message}`) }
    }
} else if (command === 'check') {
    for (const target of known) {
        const format = overlay.formatFor(target)
        if (format === 'dir') continue
        const text = readText(paths(target).overrides)
        if (text === null) continue
        try { overlay.parse(format, text) }
        catch (error) { failed = true; console.log(`${target}: ${error.message}`) }
    }
} else {
    console.error('usage: overlay-cli.mjs sync|check <config dir> <state dir> ...')
    process.exit(2)
}
process.exit(failed ? 1 : 0)
