// The machine-state overlay: tracked defaults plus this machine's overrides
// make the live file every reader uses. Pure: no I/O; overlay-cli.mjs reads and
// writes. See docs/internals/state.md.
//
// A file is a Map of key -> value. ini keys are "section\tname" ("" before any
// header); json values are their JSON text; dir keys are file names.

const SEP = '\t'
const iniHeader = /^\s*\[([^\]]*)\]\s*$/
const iniSkip = /^\s*([#;].*)?$/
const iniPair = /^([^=]*?)\s*=\s*(.*?)\s*$/
const hyprHead = /^\$([A-Za-z_][A-Za-z0-9_]*)\s*=\s*/

// Hyprlang ends a value at the first '#' that is not half of '##' (an escaped
// '#', kept as written). tail is the trailing comment with its leading space.
function hyprVar(line) {
    const head = hyprHead.exec(line)
    if (!head) return null
    let end = line.length
    for (let i = head[0].length; i < line.length; i++) {
        if (line[i] !== '#') continue
        if (line[i + 1] === '#') { i++; continue }
        end = i
        break
    }
    const value = line.slice(head[0].length, end).trimEnd()
    return { name: head[1], value, tail: line.slice(head[0].length + value.length) }
}

export function formatFor(target) {
    if (target === 'options') return 'dir'
    if (target.endsWith('.json')) return 'json'
    if (/^hypr\/[^/]+\.conf$/.test(target)) return 'hyprvars'
    return 'ini'
}

const lines = text => text === '' ? [] : text.replace(/\r?\n$/, '').split(/\r?\n/)

export function parse(format, text) {
    const entries = new Map()
    if (format === 'json') {
        const value = JSON.parse(text)
        if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error('not a JSON object')
        for (const [key, item] of Object.entries(value)) entries.set(key, JSON.stringify(item))
    } else if (format === 'hyprvars') {
        for (const line of lines(text)) {
            const match = hyprVar(line)
            if (match) entries.set(match.name, match.value)
        }
    } else if (format === 'ini') {
        let section = ''
        lines(text).forEach((line, index) => {
            const header = iniHeader.exec(line)
            if (header) { section = header[1]; return }
            if (iniSkip.test(line)) return
            const pair = iniPair.exec(line)
            if (!pair || !pair[1]) throw new Error(`line ${index + 1} is not key=value`)
            entries.set(section + SEP + pair[1], pair[2])
        })
    } else throw new Error(`${format} has no text form`)
    return entries
}

// What changed in live since the engine last wrote it (with no record, since
// the defaults) becomes an override. A key gone from live becomes a removal, or
// for dir and hyprvars a reset. An override equal to its default is dropped, so
// it follows the next change to that default.
export function harvest(format, { defaults, last, live, overrides, removed }) {
    const next = new Map(overrides)
    const gone = new Set(removed)
    if (live) {
        const base = last ?? defaults
        for (const [key, value] of live) {
            if (base.get(key) === value) continue
            next.set(key, value)
            gone.delete(key)
        }
        for (const key of base.keys()) {
            if (live.has(key)) continue
            next.delete(key)
            if ((format === 'ini' || format === 'json') && defaults.has(key)) gone.add(key)
        }
    }
    for (const [key, value] of next) {
        if (defaults.get(key) === value) next.delete(key)
        else if (format === 'hyprvars' && !defaults.has(key)) next.delete(key)
    }
    for (const key of gone) if (!defaults.has(key) || next.has(key)) gone.delete(key)
    return { overrides: next, removed: gone }
}

export function effective(defaults, overrides, removed) {
    const out = new Map()
    for (const [key, value] of defaults) if (!removed.has(key)) out.set(key, overrides.has(key) ? overrides.get(key) : value)
    for (const [key, value] of overrides) if (!out.has(key)) out.set(key, value)
    return out
}

// Lays the effective entries out on the defaults text, keeping its comments,
// order and sections; changed values are replaced in place.
export function layout(format, defaultsText, entries) {
    if (format === 'json') {
        const object = {}
        for (const [key, value] of entries) object[key] = JSON.parse(value)
        return JSON.stringify(object, null, 2) + '\n'
    }
    if (format === 'hyprvars') {
        return lines(defaultsText).map(line => {
            const match = hyprVar(line)
            return match && entries.has(match.name) && entries.get(match.name) !== match.value ? `$${match.name} = ${entries.get(match.name)}${match.tail}` : line
        }).join('\n') + '\n'
    }
    const pending = new Map()
    for (const [key, value] of entries) {
        const [section, name] = key.split(SEP)
        if (!pending.has(section)) pending.set(section, new Map())
        pending.get(section).set(name, value)
    }
    const out = []
    let section = ''
    // Keys new to a section go after its last non-blank line.
    const flush = () => {
        const keys = pending.get(section)
        pending.delete(section)
        if (!keys?.size) return
        let at = out.length
        while (at > 0 && out[at - 1].trim() === '') at--
        out.splice(at, 0, ...[...keys].map(([name, value]) => `${name}=${value}`))
    }
    for (const line of lines(defaultsText)) {
        const header = iniHeader.exec(line)
        if (header) { flush(); section = header[1]; out.push(line); continue }
        const pair = iniSkip.test(line) ? null : iniPair.exec(line)
        if (!pair) { out.push(line); continue }
        const keys = pending.get(section)
        if (!keys?.has(pair[1])) continue // removed
        const value = keys.get(pair[1])
        keys.delete(pair[1])
        out.push(value === pair[2] ? line : `${pair[1]}=${value}`)
    }
    flush()
    for (const [name, keys] of pending) {
        if (out.length && out[out.length - 1] !== '') out.push('')
        out.push(`[${name}]`)
        for (const [key, value] of keys) out.push(`${key}=${value}`)
    }
    return out.length ? out.join('\n') + '\n' : ''
}

// The overrides file, in the target's own format ('' when there is nothing).
export function serialize(format, overrides) {
    if (!overrides.size) return ''
    if (format === 'hyprvars') return [...overrides].map(([key, value]) => `$${key} = ${value}\n`).join('')
    return layout(format, '', overrides)
}
