// The rules systemd-xdg-autostart-generator applies, over file contents handed
// in by the backend. Pure, so the whole Startup page logic runs under Node.

export function parseEntry(text) {
    const entry = {}
    let main = false
    for (const raw of text.split("\n")) {
        const line = raw.trim()
        if (line.startsWith("[")) { main = line === "[Desktop Entry]"; continue }
        if (!main || !line || line.startsWith("#")) continue
        const eq = line.indexOf("=")
        if (eq < 0) continue
        const key = line.slice(0, eq).trim()
        const value = line.slice(eq + 1).trim()
        // systemd discards a show-in list with a bad escape and accepts a later one.
        if ((key === "OnlyShowIn" || key === "NotShowIn") && hasBadEscape(value)) continue
        if (!(key in entry) || key === "Hidden" || key === "X-systemd-skip") entry[key] = value
    }
    return entry
}
const trueValues = ["1", "yes", "y", "true", "t", "on"]
const list = value => (value || "").split(";").map(s => s.trim()).filter(Boolean)
// Desktop-entry string escapes the generator accepts (xdg_unescape_string); any
// other backslash sequence fails the parse and systemd then hides the entry.
const escapes = { s: " ", n: "\n", t: "\t", r: "\r", "\\": "\\", ";": ";" }
const unescape = value => (value || "").replace(/\\(.)/g, (_, char) => escapes[char] ?? char)
// A bad escape in these fails the whole file. In OnlyShowIn/NotShowIn systemd only
// discards that list and still starts the entry (see scopeOf).
const parsedStringKeys = ["Name", "Exec", "TryExec", "Type", "Path", "AutostartCondition", "X-KDE-autostart-condition", "X-GNOME-Autostart-Phase"]
const booleanKeys = ["Hidden", "X-systemd-skip"]
const falseValues = ["0", "no", "n", "false", "f", "off"]
// Escapes are read in pairs: a backslash consumes the character after it.
function hasBadEscape(value) {
    for (let index = 0; index < value.length; ++index) {
        if (value[index] !== "\\") continue
        if (!Object.prototype.hasOwnProperty.call(escapes, value[index + 1] ?? "")) return true
        ++index
    }
    return false
}
// Why systemd would refuse to parse this file (it then treats the entry as hidden), or "".
export function entryProblem(text) {
    let main = false
    const seen = new Set()
    for (const raw of text.split(/\r?\n/)) {
        const line = raw.trim()
        if (line.startsWith("[")) { main = line === "[Desktop Entry]"; continue }
        if (!main || !line || line.startsWith("#")) continue
        const eq = line.indexOf("=")
        if (eq < 0) continue
        const key = line.slice(0, eq).trim(), value = line.slice(eq + 1).trim()
        if (booleanKeys.includes(key) && !trueValues.includes(value.toLowerCase()) && !falseValues.includes(value.toLowerCase())) return `${key}=${value} is not a boolean`
        if (parsedStringKeys.includes(key) && !seen.has(key)) {
            seen.add(key)
            if (hasBadEscape(value)) return `${key} has an escape systemd rejects`
        }
    }
    return ""
}
function firstExecWord(command) {
    let word = "", quote = "", started = false
    for (let index = 0; index < command.length; ++index) {
        const char = command[index]
        if (char === "\\" && index + 1 < command.length) { word += command[++index]; started = true; continue }
        if (quote) {
            if (char === quote) quote = ""
            else word += char
        } else if (char === "'" || char === '"') { quote = char; started = true }
        else if (/\s/.test(char)) { if (started) break }
        else { word += char; started = true }
    }
    return word
}
function isTrue(value) { return trueValues.includes((value || "").toLowerCase()) }
function scopeOf(entry, desktops) {
    if (entry.Type !== "Application") return "Not an application entry"
    if (!firstExecWord(unescape(entry.Exec))) return "No command to run"
    if (isTrue(entry["X-systemd-skip"])) return "Skipped by systemd"
    const only = list(entry.OnlyShowIn), not = list(entry.NotShowIn)
    if (only.length && !only.some(d => desktops.includes(d))) return `Only for ${only.join(", ")}`
    const excluded = not.filter(d => desktops.includes(d))
    if (excluded.length) return `Not for ${excluded.join(", ")}`
    return ""
}
// The scope shown for a user file systemd sees but this page cannot read (dangling link, permissions).
export const unreadableScope = "Unreadable file in ~/.config/autostart"
// `user` files may carry `link` (a symbolic link, never written through) and an
// undefined `text` (unreadable or dangling): systemd still sees such a file, so it
// still masks the system entry of the same id.
export function autostartEntries({ system, user, desktops, onPath }) {
    const sys = new Map(system.map(f => [f.id, f.text]))
    const usr = new Map(user.map(f => [f.id, f]))
    return [...new Set([...sys.keys(), ...usr.keys()])].map(id => {
        const file = usr.get(id), base = sys.get(id)
        const own = file ? file.text : undefined
        const origin = base === undefined ? "user" : file === undefined ? "system" : "override"
        const link = Boolean(file && file.link)
        if (file && own === undefined) {
            const masked = base === undefined ? {} : parseEntry(base)
            return {
                id, name: masked.Name || id.replace(/\.desktop$/, ""), origin, enabled: false, invalid: "", ignoredGnomeFlag: false,
                scope: unreadableScope, binary: firstExecWord(unescape(masked.Exec)), installed: false, unit: unitName(id),
                // Deletable only when nothing else is at stake: an unreadable override may be a
                // hand-made file the page cannot even show, so it is left for the user to handle.
                link, staleOverride: false, removable: origin === "user",
            }
        }
        const effective = parseEntry(own ?? base)
        // A minimal override carries no Exec of its own: describe the file it masks,
        // even when a vendor rename left its Name behind (then it is stale).
        const shaped = own !== undefined && base !== undefined && isMinimalShape(own)
        const exact = shaped && isMinimalOverride(own, overrideName(id, base))
        const described = shaped ? parseEntry(base) : effective
        const problem = entryProblem(own ?? base)
        // TryExec is looked up verbatim (after unescaping), never split like a command line.
        const tryBinary = described.TryExec ? unescape(described.TryExec) : ""
        const commandBinary = firstExecWord(unescape(described.Exec))
        const binary = tryBinary && !onPath(tryBinary) ? tryBinary : commandBinary || tryBinary
        // When the user's own file is what makes the entry unusable, say which file.
        const fileNote = own !== undefined && !shaped ? `~/.config/autostart/${id}: ` : ""
        const baseScope = problem ? `Ignored by systemd: ${problem}` : scopeOf(described, desktops)
        return {
            id, name: described.Name || id.replace(/\.desktop$/, ""), origin,
            enabled: !problem && !isTrue(effective.Hidden),
            invalid: problem,
            ignoredGnomeFlag: (effective["X-GNOME-Autostart-enabled"] || "").toLowerCase() === "false",
            scope: baseScope ? fileNote + baseScope : "", binary,
            installed: Boolean(commandBinary) && (!tryBinary || onPath(tryBinary)) && onPath(commandBinary), unit: unitName(id),
            link, staleOverride: shaped && !exact,
            // Remove deletes only a file that adds an app, or a stale Hidden stub. A customised
            // override (its own Exec, Name, …) is the user's work and is never offered for deletion.
            removable: origin === "user" || (origin === "override" && shaped && !exact),
        }
    }).sort((a, b) => (b.enabled && !b.scope) - (a.enabled && !a.scope) || a.name.localeCompare(b.name))
}
// Why a desktop entry (fields as the generator would read them) would not start at login, or "".
export function appScope(fields, desktops) { return scopeOf(Object.assign({ Type: "Application" }, fields), desktops) }

// `show-environment` prints values that need it as $'...'. Undo the escapes the
// PATH and XDG_CURRENT_DESKTOP lookups could meet.
const shellEscapes = { n: "\n", t: "\t", r: "\r", a: "\x07", b: "\b", f: "\f", v: "\v", "\\": "\\", "'": "'", '"': '"' }
function unquoteShell(value) {
    if (value.length < 3 || !value.startsWith("$'") || !value.endsWith("'")) return value
    const body = value.slice(2, -1)
    let out = "", pending = ""
    const flush = () => {
        if (!pending) return
        try { out += decodeURIComponent(pending) } catch (_) { out += pending.replace(/%([0-9A-Fa-f]{2})/g, (_, hex) => String.fromCharCode(parseInt(hex, 16))) }
        pending = ""
    }
    for (let index = 0; index < body.length; ++index) {
        const char = body[index]
        if (char !== "\\" || index + 1 >= body.length) { flush(); out += char; continue }
        const next = body[++index]
        const hex = next === "x" ? /^[0-9A-Fa-f]{1,2}/.exec(body.slice(index + 1)) : null
        if (hex) { pending += "%" + hex[0].padStart(2, "0"); index += hex[0].length; continue }
        flush()
        out += Object.prototype.hasOwnProperty.call(shellEscapes, next) ? shellEscapes[next] : next
    }
    flush()
    return out
}
export function parseEnvironment(text) {
    const values = {}
    for (const line of text.split("\n")) {
        const eq = line.indexOf("=")
        if (eq > 0) values[line.slice(0, eq)] = unquoteShell(line.slice(eq + 1))
    }
    return values
}

function utf8Bytes(text) {
    const bytes = []
    for (const char of text) {
        const code = char.codePointAt(0)
        if (code < 0x80) bytes.push(code)
        else if (code < 0x800) bytes.push(0xc0 | code >> 6, 0x80 | code & 0x3f)
        else if (code < 0x10000) bytes.push(0xe0 | code >> 12, 0x80 | code >> 6 & 0x3f, 0x80 | code & 0x3f)
        else bytes.push(0xf0 | code >> 18, 0x80 | code >> 12 & 0x3f, 0x80 | code >> 6 & 0x3f, 0x80 | code & 0x3f)
    }
    return bytes
}

// systemd unit-name escaping: keep [A-Za-z0-9:_.] except a leading dot.
export function unitName(id) {
    const escaped = utf8Bytes(id.replace(/\.desktop$/, ""))
        .map((byte, index) => byte === 46 && index === 0 ? "\\x2e"
            : /[A-Za-z0-9:_.]/.test(String.fromCharCode(byte)) ? String.fromCharCode(byte) : "\\x" + byte.toString(16).padStart(2, "0")).join("")
    return `app-${escaped}@autostart.service`
}
export function isAutostartFileName(name) {
    // Backup suffixes also fail the required .desktop ending.
    return name.endsWith(".desktop") && !name.startsWith(".")
}
export function withStatus(entries, units) {
    const byUnit = new Map(units.map(u => [u.unit, u]))
    return entries.map(entry => {
        const unit = byUnit.get(entry.unit)
        let status
        if (entry.scope) status = { state: "none", label: "" }
        else if (!entry.installed) status = { state: "missing", label: `Not installed: ${entry.binary}` }
        else if (!unit) status = { state: "none", label: entry.enabled && !entry.scope ? "Not started this session" : "" }
        else if (unit.active === "failed") status = { state: "failed", label: "Failed" }
        else if (unit.active === "active" || unit.active === "activating") status = { state: "running", label: "Running" }
        else status = { state: "finished", label: "Finished" }
        // A stale override hides an entry nothing else describes: say where the file is.
        if (entry.staleOverride) status.label = [status.label, `Hidden by ~/.config/autostart/${entry.id}`].filter(Boolean).join(" · ")
        return Object.assign({}, entry, { status })
    })
}

export const minimalOverride = name => `[Desktop Entry]\nType=Application\nName=${name.replace(/[\r\n]+/g, " ")}\nHidden=true\n`
// The Name minimalOverride writes for an entry: the masked file's Name, else its id.
export function overrideName(id, systemText) { return parseEntry(systemText).Name || id.replace(/\.desktop$/, "") }
// The Name in a file shaped exactly like minimalOverride writes it (comments and blank
// lines aside), or null for anything else; that was written by hand and must never be
// deleted as "ours".
function minimalNameOf(text) {
    const lines = text.split(/\r?\n/).map(l => l.trim()).filter(l => l && !l.startsWith("#"))
    return lines.length === 4 && lines[0] === "[Desktop Entry]" && lines[1] === "Type=Application"
        && lines[2].startsWith("Name=") && lines[3] === "Hidden=true" ? lines[2] : null
}
export function isMinimalShape(text) { return minimalNameOf(text) !== null }
export function isMinimalOverride(text, name) {
    if (typeof name !== "string") throw new Error("isMinimalOverride needs the expected name")
    return minimalNameOf(text) === "Name=" + name.replace(/[\r\n]+/g, " ")
}
// Only [Desktop Entry]'s Hidden (and on enable the GNOME flag) changes; every other line is kept.
export function setHidden(text, hidden) {
    // Each line keeps its own ending, so files with mixed CRLF/LF survive untouched.
    const parts = text.split(/(\r?\n)/)
    const lines = []
    for (let index = 0; index < parts.length; index += 2) lines.push({ text: parts[index], end: parts[index + 1] ?? "" })
    const out = []
    let main = false, foundMain = false, lastMain = -1
    for (const line of lines) {
        const trimmed = line.text.trim()
        if (trimmed.startsWith("[")) { main = trimmed === "[Desktop Entry]"; out.push(line); if (main) { foundMain = true; lastMain = out.length - 1 } continue }
        if (main && /^Hidden\s*=/.test(trimmed)) continue
        if (main && !hidden && /^X-GNOME-Autostart-enabled\s*=\s*false$/i.test(trimmed)) continue
        out.push(line)
        if (main && trimmed) lastMain = out.length - 1
    }
    if (!foundMain) throw new Error("Not a desktop entry")
    if (hidden) {
        const anchor = out[lastMain]
        const end = anchor.end || (text.includes("\r\n") ? "\r\n" : "\n")
        if (!anchor.end) anchor.end = end
        out.splice(lastMain + 1, 0, { text: "Hidden=true", end })
    }
    return out.map(line => line.text + line.end).join("")
}

export function sessionCommands(lua) {
    const withoutBlocks = lua.replace(/--\[\[[\s\S]*?\]\]/g, "")
    const code = withoutBlocks.split("\n").map(line => {
        let quote = ""
        for (let index = 0; index < line.length; ++index) {
            const char = line[index]
            if (quote) {
                if (char === "\\") ++index
                else if (char === quote) quote = ""
            } else if (char === "'" || char === '"') quote = char
            else if (char === "-" && line[index + 1] === "-") return line.slice(0, index)
        }
        return line
    }).join("\n")
    const commands = [], pattern = /hl\.exec_cmd\(\s*"((?:[^"\\]|\\.)*)"(\s*\.\.)?/g
    let match
    while ((match = pattern.exec(code)) !== null)
        commands.push(match[1].replace(/\\(.)/g, "$1").replace(/\s+$/, "") + (match[2] ? " …" : ""))
    return commands
}
