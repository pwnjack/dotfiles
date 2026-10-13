// I/O around overlay.mjs. Called by overlay.sh, which holds the lock.
//
//   overlay-cli.mjs sync <config dir> <state dir> [--replace <backup dir>] [<live path>...]
//   overlay-cli.mjs check <config dir> <state dir>
//
// Targets are the files under <config dir>/defaults (options/ as one directory
// target). Each is synced independently: one failing never stops the others,
// and the exit status is 1 when any failed.
import fs from 'node:fs'
import path from 'node:path'
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
    fs.writeFileSync(temp, text)
    fs.renameSync(temp, file)
}
// Regular, non-hidden files only: options/wallpaper is a symlink and never a key.
function readDir(dir) {
    let names
    try { names = fs.readdirSync(dir, { withFileTypes: true }) }
    catch (error) { if (error.code === 'ENOENT') return null; throw error }
    const entries = new Map()
    for (const entry of names) {
        if (entry.isFile() && !entry.name.startsWith('.')) entries.set(entry.name, fs.readFileSync(path.join(dir, entry.name), 'utf8'))
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

// Moves a live file (or the options directory's regular files) aside.
function replaceLive(target, live, backup) {
    if (overlay.formatFor(target) === 'dir') {
        for (const name of readDir(live)?.keys() ?? []) {
            if (backup) { fs.mkdirSync(path.join(backup, target), { recursive: true }); fs.copyFileSync(path.join(live, name), path.join(backup, target, name)) }
            fs.rmSync(path.join(live, name))
        }
        return
    }
    if (readText(live) === null) return
    if (backup) { fs.mkdirSync(path.dirname(path.join(backup, target)), { recursive: true }); fs.copyFileSync(live, path.join(backup, target)) }
    fs.rmSync(live)
}

function syncTarget(target, replace) {
    const format = overlay.formatFor(target)
    const p = paths(target)
    const isDir = format === 'dir'
    const load = file => {
        if (isDir) return readDir(file)
        const text = readText(file)
        return text === null ? null : overlay.parse(format, text)
    }
    const defaultsText = isDir ? null : readText(p.defaults)
    const defaults = isDir ? readDir(p.defaults) : overlay.parse(format, defaultsText)
    const last = load(p.last)
    if (replace !== undefined && last === null) replaceLive(target, p.live, replace)
    const live = load(p.live) // throws on a malformed file: the target is skipped untouched
    const overrides = load(p.overrides) ?? new Map()
    const removed = new Set((readText(p.removed) ?? '').split('\n').filter(Boolean))
    const next = overlay.harvest(format, { defaults, last, live, overrides, removed })
    const entries = overlay.effective(defaults, next.overrides, next.removed)
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
    const names = []
    for (let i = 0; i < rest.length; i++) {
        if (rest[i] === '--replace') replace = rest[++i] ?? ''
        else names.push(rest[i])
    }
    let chosen = known
    try { if (names.length) chosen = [...new Set(names.map(name => normalise(name, known)))] }
    catch (error) { console.error(`overlay: ${error.message}`); process.exit(2) }
    for (const target of chosen) {
        try { syncTarget(target, replace) }
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
