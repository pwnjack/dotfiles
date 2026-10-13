import GLib from "gi://GLib"
import Gio from "gi://Gio"
import GioUnix from "gi://GioUnix"
import { execAsync, execInput } from "./process.js"
import { checkedHyprctl } from "./hyprctl.js"
import * as persist from "./persist.js"
import { pulseState, pulseValue, pulseEnumerators, setPulse } from "./pulse.js"
import * as displays from "./displays.mjs"
import * as about from "./about.mjs"
import { callSystem, getProperty } from "./dbus.js"
import { nmSnapshot, setWifiEnabled, requestScan, activate, addAndActivate, deactivate, removeConnections } from "./nm.js"
import * as network from "./network.mjs"
import * as autostart from "./autostart.mjs"
import { regionValue, regionEnumerators, setRegion } from "./region.js"
import * as calendar from "./calendar.mjs"

const configDir = GLib.get_home_dir() + "/.config"
const catalog = JSON.parse(read(configDir + "/quickshell/settings-panel/catalog.json"))
const byId = new Map(catalog.rows.map(row => [row.id, row]))
const optionPath = key => `${configDir}/options/${key}`
const idlePath = configDir + "/hypr/hypridle.conf"
// hypridle.conf sources this fixed path (hyprlang cannot expand XDG_STATE_HOME).
const idleStatePath = `${GLib.get_home_dir()}/.local/state/hypr/hypridle.conf`
const sunsetPath = configDir + "/hypr/hyprsunset.conf"
const swayPath = configDir + "/swaync/config.json"
const kvantumPath = configDir + "/Kvantum/kvantum.kvconfig"
const kvantumDirs = [configDir + "/Kvantum", "/usr/share/Kvantum"]
const stateHome = GLib.getenv("XDG_STATE_HOME") || `${GLib.get_home_dir()}/.local/state`
const displayStatePath = `${stateHome}/hypr/monitors.lua`
const pendingPath = `${GLib.get_user_runtime_dir()}/settings-panel/display-pending.json`
const guardUnit = "settings-display-revert"

function read(path) {
    const [ok, data] = Gio.File.new_for_path(path).load_contents(null)
    if (!ok) throw new Error(`Cannot read ${path}`)
    return new TextDecoder().decode(data)
}
function readBytes(path) {
    const [ok, data] = Gio.File.new_for_path(path).load_contents(null)
    if (!ok) throw new Error(`Cannot read ${path}`)
    return data
}
function writeBytes(path, data) {
    const [ok] = Gio.File.new_for_path(path).replace_contents(data, null, false, Gio.FileCreateFlags.NONE, null)
    if (!ok) throw new Error(`Cannot save ${path}`)
}
function write(path, text) {
    writeBytes(path, new TextEncoder().encode(text))
}
function makeParent(path) {
    const dir = path.slice(0, path.lastIndexOf("/"))
    if (!exists(dir)) Gio.File.new_for_path(dir).make_directory_with_parents(null)
}
const remove = path => Gio.File.new_for_path(path).delete(null)
const exists = path => Gio.File.new_for_path(path).query_exists(null)
function children(path) {
    let enumerator
    try { enumerator = Gio.File.new_for_path(path).enumerate_children("standard::name", Gio.FileQueryInfoFlags.NONE, null) }
    catch (_) { return [] } // A missing search directory is normal.
    const names = []
    for (let info; (info = enumerator.next_file(null));) names.push(info.get_name())
    enumerator.close(null)
    return names
}
const autostartUser = `${configDir}/autostart`
const autostartSystem = "/etc/xdg/autostart"
const noFollow = Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS
// The file itself, never its target: null when nothing (not even a dangling link) is there.
function lstat(path) {
    try { return Gio.File.new_for_path(path).query_info("standard::type,standard::is-symlink", noFollow, null) } catch (_) { return null }
}
// Gio's replace follows links (a live one rewrites its target, a dangling one creates
// it), so the page never writes to a link and refuses instead.
const lexists = path => lstat(path) !== null
// A file that is really executable, as the generator's TryExec/Exec lookup requires.
function isExecutableFile(path) {
    try {
        const info = Gio.File.new_for_path(path).query_info("standard::type,access::can-execute", Gio.FileQueryInfoFlags.NONE, null)
        return info.get_file_type() === Gio.FileType.REGULAR && info.get_attribute_boolean("access::can-execute")
    } catch (_) { return false }
}
// Creates the file only if nothing (file or link) is there; `taken` is the refusal otherwise.
// The bytes go to a hidden temporary file first (the generator ignores dotfiles), which is
// then published with a hard link: link(2) never overwrites, so publishing stays exclusive,
// and a crash leaves at most the ignored temporary file, never a partial entry.
async function createNew(path, bytes, taken) {
    if (lexists(path)) throw new Error(taken)
    const dir = path.slice(0, path.lastIndexOf("/"))
    const temp = `${dir}/.${path.slice(dir.length + 1)}.${Math.random().toString(36).slice(2)}.tmp`
    let stream
    try {
        stream = Gio.File.new_for_path(temp).create(Gio.FileCreateFlags.PRIVATE, null)
        stream.write_all(bytes, null)
        stream.close(null)
        stream = null
        try { await execAsync(["env", "LC_ALL=C", "ln", "--", temp, path]) }
        catch (error) {
            // EEXIST: something appeared at the destination after the check above.
            if (lexists(path) || /File exists/.test(error.message)) throw new Error(taken)
            throw error
        }
    } finally {
        if (stream) { try { stream.close(null) } catch (_) {} }
        try { remove(temp) } catch (_) {}
    }
}
// The generator skips dotfiles and backups. A system file it cannot read is skipped
// like systemd would; a user file it cannot read still masks the system entry, so it
// is kept (text undefined). A dangling user link is ignored like systemd ignores it
// ("stat() failed, ignoring"): the system entry of the same id still starts. Writes stay
// safe regardless, because new files are created exclusively and refuse any link there.
function desktopFiles(dir, keepUnreadable) {
    const files = []
    for (const id of children(dir)) {
        if (!autostart.isAutostartFileName(id) || /[\r\n/]/.test(id)) continue
        const path = `${dir}/${id}`
        const info = keepUnreadable ? lstat(path) : null
        const link = Boolean(info && info.get_is_symlink())
        if (keepUnreadable && !link && (!info || info.get_file_type() !== Gio.FileType.REGULAR)) continue
        if (link && !exists(path)) continue
        try { files.push({ id, text: read(path), link }) } catch (_) {
            if (keepUnreadable) files.push({ id, text: undefined, link })
        }
    }
    return files
}
// Editing in place must never alter bytes it does not mean to: strict UTF-8, BOM kept.
function readEditable(path, shown) {
    const bytes = readBytes(path)
    const bom = bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf
    try { return (bom ? "\ufeff" : "") + new TextDecoder("utf-8", { fatal: true }).decode(bom ? bytes.subarray(3) : bytes) }
    catch (_) { throw new Error(`${shown} is not UTF-8; edit it by hand`) }
}
// The generator runs inside the systemd user manager, so its environment decides
// which desktop applies and where a binary is found, not this helper's.
async function userManagerEnvironment() {
    let values = {}
    try { values = autostart.parseEnvironment(await execAsync(["systemctl", "--user", "show-environment"])) } catch (_) { /* Fall back to this process's own values. */ }
    return {
        desktops: (values.XDG_CURRENT_DESKTOP || GLib.getenv("XDG_CURRENT_DESKTOP") || "Hyprland").split(":"),
        path: (values.PATH || GLib.getenv("PATH") || "/usr/bin").split(":").filter(Boolean),
    }
}
const onPathIn = path => binary => binary.startsWith("/") ? isExecutableFile(binary) : path.some(dir => isExecutableFile(`${dir}/${binary}`))
// What the generator would read from an installed application's desktop file.
const appFields = app => typeof app.get_string === "function"
    ? { Exec: app.get_string("Exec") || "", OnlyShowIn: app.get_string("OnlyShowIn") || "", NotShowIn: app.get_string("NotShowIn") || "" }
    : { Exec: "" }

async function startupEntries() {
    const { desktops, path } = await userManagerEnvironment()
    const system = desktopFiles(autostartSystem, false), user = desktopFiles(autostartUser, true)
    return { desktops, entries: autostart.autostartEntries({ system, user, desktops, onPath: onPathIn(path) }) }
}
async function startupState() {
    const { desktops, entries } = await startupEntries()
    let units = []
    // Unit state is informative only; a systemd hiccup must not blank the page.
    try { units = JSON.parse(await execAsync(["systemctl", "--user", "list-units", "--all", "--output=json", "app-*@autostart.service"])) } catch (_) {}
    const present = new Set(entries.map(e => e.id))
    return {
        session: autostart.sessionCommands(read(configDir + "/hypr/config/setup/autostart.lua")),
        apps: autostart.withStatus(entries, units),
        available: Gio.AppInfo.get_all().filter(app => !present.has(app.get_id()) && app.should_show() && !autostart.appScope(appFields(app), desktops))
            .map(app => ({ id: app.get_id(), name: app.get_name() })).sort((a, b) => a.name.localeCompare(b.name)),
    }
}
async function autostartChange(request) {
    if (!["enable", "disable", "remove"].includes(request.action)) throw new Error("Unknown startup action")
    const entry = (await startupEntries()).entries.find(app => app.id === request.id)
    if (!entry) throw new Error("That startup app no longer exists")
    const path = `${autostartUser}/${entry.id}`, shown = `~/.config/autostart/${entry.id}`
    if (entry.link) throw new Error(`${shown} is a link; edit it by hand`)
    if (request.action === "remove") {
        if (!entry.removable) throw new Error(entry.origin === "override" ? `~/.config/autostart/${entry.id} is your own version of this entry; edit or delete it there` : "Only apps you added can be removed")
        return remove(path)
    }
    if (entry.scope) throw new Error(`${entry.name} cannot be changed: ${entry.scope}`)
    const systemPath = `${autostartSystem}/${entry.id}`
    if (request.action === "disable") {
        if (entry.origin === "system") {
            makeParent(path)
            return createNew(path, new TextEncoder().encode(autostart.minimalOverride(entry.name)), `${shown} already exists`)
        }
        return write(path, autostart.setHidden(readEditable(path, shown), true))
    }
    if (entry.origin === "system") {
        if (entry.enabled) return
        // The system file itself is hidden: a user override without Hidden says otherwise.
        makeParent(path)
        return createNew(path, new TextEncoder().encode(autostart.setHidden(readEditable(systemPath, systemPath), false)), `${shown} already exists`)
    }
    const text = readEditable(path, shown)
    if (entry.origin === "override") {
        // Only the exact file disable wrote is ours to delete; a lone user file is edited in place.
        if (autostart.isMinimalOverride(text, autostart.overrideName(entry.id, read(systemPath)))) return remove(path)
        if (autostart.isMinimalShape(text)) throw new Error(`${shown} was written by hand; remove it there to restore the system entry`)
    }
    // Accepted: enabling also drops X-GNOME-Autostart-enabled=false (systemd ignores the key),
    // and deleting a minimal override drops any comments it carried.
    return write(path, autostart.setHidden(text, false))
}
async function autostartAdd(request) {
    const app = Gio.AppInfo.get_all().find(candidate => candidate.get_id() === request.app)
    if (!app || !app.get_filename()) throw new Error("That application is not installed")
    const id = app.get_id(), path = `${autostartUser}/${id}`
    if (lexists(path) || exists(`${autostartSystem}/${id}`)) throw new Error("Already in startup apps")
    if (!app.should_show()) throw new Error("Not shown in menus")
    const scope = autostart.appScope(appFields(app), (await userManagerEnvironment()).desktops)
    if (scope) throw new Error(`Would not start at login: ${scope}`)
    const bytes = readBytes(app.get_filename())
    makeParent(path)
    await createNew(path, bytes, `~/.config/autostart/${id} already exists`)
}
const home = GLib.get_home_dir()
const themeDirs = kind => [`${home}/.local/share/${kind}`, `${home}/.${kind}`, `/usr/share/${kind}`]
function themeNames(dirs, isTheme, builtins = []) {
    const names = new Set(builtins)
    for (const dir of dirs) for (const name of children(dir))
        if (!/[\r\n]/.test(name) && isTheme(`${dir}/${name}`)) names.add(name)
    return [...names].sort((a, b) => a.localeCompare(b)).map(name => ({ label: name, value: name }))
}
const hasIcons = dir => { try { return /^Directories=/m.test(read(`${dir}/index.theme`)) } catch (_) { return false } }
const mimeDefault = async mime => (await execAsync(["xdg-mime", "query", "default", mime])).trim()
// Each enumerator returns what the system has now, so validation and the
// dropdown can never disagree. GTK's built-ins have no theme directories:
// they are libgtk-3 resources (`gresource list libgtk-3.so.0`, minus win32).
const enumerators = {
    "gtk-themes": () => themeNames(themeDirs("themes"), dir => exists(`${dir}/gtk-3.0/gtk.css`), ["Adwaita", "HighContrast", "HighContrastInverse"]),
    "icon-themes": () => themeNames(themeDirs("icons"), hasIcons),
    "cursor-themes": () => themeNames(themeDirs("icons"), dir => exists(`${dir}/cursors`)),
    "kvantum-themes": () => themeNames(kvantumDirs, dir => exists(`${dir}/${dir.split("/").pop()}.kvconfig`)),
    applications: async (row, knownCurrent) => {
        const apps = Gio.AppInfo.get_all_for_type(row.mimes[0]).map(app => ({ label: app.get_name(), value: app.get_id() }))
        const current = knownCurrent === undefined ? await mimeDefault(row.mimes[0]) : knownCurrent
        if (current && !apps.some(app => app.value === current)) apps.push({ label: current.replace(/\.desktop$/, ""), value: current })
        return apps
    },
    monitors: async (row, knownCurrent, once) => {
        const outputs = await once("bar-monitors", async () => JSON.parse(await execAsync(["hyprctl", "monitors", "-j"])))
        const choices = [{ label: "All monitors", value: "" }, ...outputs.map(output => ({
            label: [output.name, [output.make, output.model].filter(Boolean).join(" ")].filter(Boolean).join(" — "), value: output.name,
        }))]
        const current = knownCurrent === undefined ? (exists(optionPath(row.key)) ? readOption(row.key) : "") : knownCurrent
        if (current && !choices.some(item => item.value === current)) choices.push({ label: `${current} (disconnected)`, value: current })
        return choices
    },
    "power-profiles": async () => (await execAsync(["powerprofilesctl", "list"])).split("\n")
        .map(line => line.match(/^\*?\s*([\w-]+):$/)).filter(Boolean)
        .map(([, name]) => ({ label: name.replace(/(^|-)(\w)/g, (_, dash, c) => (dash ? " " : "") + c.toUpperCase()), value: name })),
    calendars: async () => {
        // cal.sh exits 1 with {"ok":false} when it cannot list; that leaves the row with no choices.
        let calendars = []
        try { calendars = JSON.parse(await execAsync(["bash", configDir + "/scripts/calendar/cal.sh", "calendars"])) } catch (_) {}
        return Array.isArray(calendars) ? calendars.filter(c => c.writable).map(c => ({ label: c.name, value: c.name })) : []
    },
    ...pulseEnumerators,
    ...regionEnumerators,
}
async function choicesFor(row, current, once = onceCache()) {
    if (row.items) return row.items
    if (!Object.hasOwn(enumerators, row.choices)) throw new Error("This setting has no choices")
    return enumerators[row.choices](row, current, once)
}
function readOption(key) { return read(optionPath(key)).trim() }
function networkValue(key, snap) {
    if (!snap.running) throw new Error("NetworkManager is not running")
    if (key !== "wifi") throw new Error("Unknown network setting")
    if (!snap.wifiDevices.length) throw new Error("No Wi-Fi device")
    return snap.wifiEnabled
}
const networkPage = snap => network.networkView(snap, { protonApp: !!GLib.find_program_in_path("protonvpn-app") })
function requiredSnapshot() {
    const snap = nmSnapshot()
    if (!snap.running) throw new Error("NetworkManager is not running")
    return snap
}
const hyprVarLine = name => new RegExp(`^\\$${name}[ \\t]*=[ \\t]*(\\S*)[ \\t]*$`, "m")
function hyprVar(text, name) { return (hyprVarLine(name).exec(text) || [])[1] }
// Sets a variable line in the state text, or removes it when the value is the
// tracked default, so the state file only ever holds this machine's changes.
function withVar(text, name, value, fallback) {
    const line = `$${name} = ${value}`
    const pattern = new RegExp(`^\\$${name}\\s*=.*\\n?`, "m")
    if (String(value) === fallback) return text.replace(pattern, "")
    if (pattern.test(text)) return text.replace(pattern, () => line + "\n")
    const vars = text.match(/^(\$\w+\s*=.*\n)*/)[0]
    return vars + line + "\n" + text.slice(vars.length)
}
const idleVars = { lock: "lock_timeout", dpms: "dpms_timeout" }
function idleValues(tracked, state) {
    const values = {}
    for (const [key, name] of Object.entries(idleVars)) {
        const raw = hyprVar(state, name) ?? hyprVar(tracked, name)
        if (!/^\d+$/.test(raw ?? "")) throw new Error("Cannot identify idle timeout variables")
        values[key] = Number(raw)
    }
    const suspend = /# Suspend after inactivity\nlistener\s*\{[^}]*?\btimeout\s*=\s*(\d+)/.exec(state)
    values.suspend = suspend ? Number(suspend[1]) : 0
    return values
}
function readIdleState() { return exists(idleStatePath) ? read(idleStatePath) : "" }
// The panel owns only the listener it wrote, found by its marker comment.
// It always appends that block as a fixed "\n\n" + marker suffix (never
// collapsing whatever newlines the file already ended with), so removal can
// strip exactly that fixed suffix and restore the original bytes regardless
// of how many trailing newlines the file had before the block existed.
const suspendMarker = seconds => `# Suspend after inactivity\nlistener {\n    timeout = ${seconds}\n    on-timeout = systemctl suspend\n}\n`
const suspendBlock = /\n\n# Suspend after inactivity\nlistener\s*\{[^}]*systemctl suspend[^}]*\}\n$/
function withSuspend(text, seconds) {
    const marked = (text.match(/# Suspend after inactivity\nlistener\s*\{[^}]*systemctl suspend[^}]*\}/) || [])[0]
    const suspends = (text.match(/listener\s*\{[^}]*\}/g) || []).filter(block => block.includes("systemctl suspend"))
    // A hand-written suspend listener is never retimed or removed.
    if (suspends.length > (marked ? 1 : 0)) throw new Error("hypridle.conf has a custom suspend listener; change it by hand")
    if (marked && seconds) return text.replace(marked, () => marked.replace(/(\btimeout\s*=\s*)\d+/, `$1${seconds}`))
    if (marked) {
        if (!suspendBlock.test(text)) throw new Error("The panel's suspend listener was moved; remove it by hand")
        return text.replace(suspendBlock, "")
    }
    if (!seconds) return text
    return text + "\n\n" + suspendMarker(seconds)
}
const sunsetVars = { dayMinutes: "day_time", nightMinutes: "night_time", nightTemp: "night_temp" }
function sunsetValues(text) {
    const minutes = name => {
        const match = /^(\d{1,2}):(\d{2})$/.exec(hyprVar(text, name) ?? "")
        if (!match) throw new Error("Cannot read the night light schedule")
        return Number(match[1]) * 60 + Number(match[2])
    }
    const nightTemp = Number(hyprVar(text, "night_temp"))
    if (!Number.isInteger(nightTemp) || nightTemp <= 0) throw new Error("Cannot read the night light schedule")
    return { dayMinutes: minutes("day_time"), nightMinutes: minutes("night_time"), nightTemp }
}
const clock = minutes => `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`

function detached(args) {
    if (!GLib.find_program_in_path(args[0])) throw new Error(`${args[0]} is not installed`)
    GLib.spawn_async(null, args, null, GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.STDOUT_TO_DEV_NULL | GLib.SpawnFlags.STDERR_TO_DEV_NULL, null)
}
const delay = milliseconds => new Promise(resolve => GLib.timeout_add(GLib.PRIORITY_DEFAULT, milliseconds, () => { resolve(); return GLib.SOURCE_REMOVE }))
// Files the machine-state overlay renders are written live, then synced, which
// records the change as this machine's override (scripts/state/overlay.sh).
const overlaySources = new Set(["option", "gtk", "mime", "swaync", "sunset"])
const syncOverlay = () => execAsync(["bash", configDir + "/scripts/state/overlay.sh", "sync"])
async function restart(name) {
    if (!GLib.find_program_in_path(name)) throw new Error(`${name} is not installed`)
    try { await execAsync(["pkill", "-x", name]) } catch (_) { /* It may not be running. */ }
    // Wait for the old daemon to exit before starting the replacement.
    for (let attempt = 0; attempt < 30; attempt++) {
        try { await execAsync(["pgrep", "-x", name]) } catch (_) { break }
        if (attempt === 29) throw new Error(`${name} did not stop`)
        await delay(50)
    }
    detached([name])
    await delay(150)
    if (name === "hyprsunset") {
        const status = await execAsync(["bash", configDir + "/scripts/hyprland/nightlight.sh", "status"])
        if (status === "unavailable") throw new Error("Night light did not restart")
    }
    else await execAsync(["pgrep", "-x", name])
}
// A select or switch whose unset file reads as a default (bar-agenda, calendar-alert,
// calendar-duration, calendar-declined) or as the first writable calendar (calendar-default).
// Other rows keep reporting a missing file, so a save never recreates a file it has not read.
const unsetReadsDefault = row => row.source === "option" && (row.kind === "select" || row.kind === "toggle")
    && (row.default !== undefined || row.choices === "calendars")
// The file did not exist: a rollback removes it again, so the row reads its default afterwards.
async function saveNew(path, text, apply) {
    write(path, text)
    try { await apply() }
    catch (error) {
        try { remove(path); await apply() }
        catch (rollback) { throw new Error(`${error.message}. Restoring the previous settings also failed: ${rollback.message}`) }
        throw new Error(`${error.message}. Previous settings restored.`)
    }
}
// Like saveAndApply, but an empty text removes the file; a failure restores the
// previous bytes, or no file when there was none.
async function saveOrRemove(path, text, apply) {
    const before = exists(path) ? read(path) : null
    if (text === "") { if (before !== null) remove(path) }
    else write(path, text)
    try { await apply() }
    catch (error) {
        try {
            if (before === null) { if (exists(path)) remove(path) }
            else write(path, before)
            await apply()
        } catch (rollback) { throw new Error(`${error.message}. Restoring the previous settings also failed: ${rollback.message}`) }
        throw new Error(`${error.message}. Previous settings restored.`)
    }
}
async function saveAndApply(path, text, apply, createMissing = false) {
    if (createMissing && !exists(path)) return saveNew(path, text, apply)
    const before = read(path)
    write(path, text)
    try { await apply() }
    catch (error) {
        try { write(path, before); await apply() }
        catch (rollback) { throw new Error(`${error.message}. Restoring the previous settings also failed: ${rollback.message}`) }
        throw new Error(`${error.message}. Previous settings restored.`)
    }
}

// hyprctl getoption names the value field after the option's type. `set` only
// says whether the config assigns the option, so it is never a value.
function keywordValue(data) {
    for (const field of ["bool", "int", "float", "str", "css", "custom"]) {
        if (data[field] === undefined) continue
        return field === "str" && data[field] === "[[EMPTY]]" ? "" : data[field]
    }
    throw new Error("Hyprland did not return a value")
}

const gtkIniPaths = ["gtk-3.0", "gtk-4.0"].map(dir => `${configDir}/${dir}/settings.ini`)
const gsettingsArgs = key => ["org.gnome.desktop.interface", key]
function gvariantValue(text) {
    const quoted = text.trim().match(/^'(.*)'$/)
    return quoted ? quoted[1] : Number(text)
}
const gvariantLiteral = value => typeof value === "number" ? String(value) : `'${String(value).replace(/[\\']/g, "\\$&")}'`
const regexEscape = text => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
function iniSection(text, name) {
    const header = new RegExp(`^(\\[${regexEscape(name)}\\])(\\r\\n|\\n|\\r|$)`, "m").exec(text)
    if (!header) return null
    const start = header.index + header[0].length
    const next = /^\[[^\r\n]*\](?=\r?$)/m.exec(text.slice(start))
    return { header, start, end: next ? start + next.index : text.length }
}
function iniValue(text, key, sectionName = "Settings") {
    const section = iniSection(text, sectionName)
    if (!section) return ""
    const pattern = new RegExp(`^${regexEscape(key)}=([^\\r\\n]*)(?=\\r?$)`, "m")
    return (pattern.exec(text.slice(section.start, section.end)) || [, ""])[1]
}
function iniSet(path, text, key, value, sectionName = "Settings") {
    if (/[\r\n]/.test(value)) throw new Error(`Cannot write a multiline value to ${path}`)
    const section = iniSection(text, sectionName)
    if (!section) throw new Error(`${path} has no [${sectionName}] section`)
    const line = `${key}=${value}`
    const body = text.slice(section.start, section.end)
    const pattern = new RegExp(`^${regexEscape(key)}=[^\\r\\n]*(?=\\r?$)`, "m")
    if (pattern.test(body))
        return text.slice(0, section.start) + body.replace(pattern, () => line) + text.slice(section.end)
    const ending = section.header[2]
    const insertion = ending ? `${line}${ending}` : `\n${line}\n`
    return text.slice(0, section.start) + insertion + text.slice(section.start)
}
// GTK 3 on Wayland reads some keys from gsettings and others from settings.ini,
// so both are written; the ini files are rendered by the overlay, and the dispatch sync records the change, keeping every other line.
function writeGtkIni(entries) {
    for (const path of gtkIniPaths) {
        if (!exists(path)) continue
        let text = read(path)
        for (const [key, value] of entries) text = iniSet(path, text, key, value)
        write(path, text)
    }
}
async function setGtk(row, value) {
    if (/[\r\n]/.test(String(value))) throw new Error("Cannot write a multiline GTK value")
    const before = gvariantValue(await execAsync(["gsettings", "get", ...gsettingsArgs(row.key)]))
    const saved = gtkIniPaths.filter(exists).map(path => [path, read(path)])
    try {
        if (row.ini) writeGtkIni([[row.ini.key, row.ini.values ? row.ini.values[value] : String(value)]])
        await execAsync(["gsettings", "set", ...gsettingsArgs(row.key), gvariantLiteral(value)])
    } catch (error) {
        for (const [path, text] of saved) write(path, text)
        try { await execAsync(["gsettings", "set", ...gsettingsArgs(row.key), gvariantLiteral(before)]) }
        catch (rollback) { throw new Error(`${error.message}. Restoring the previous gsettings value also failed: ${rollback.message}`) }
        throw new Error(`${error.message}. Previous settings restored.`)
    }
}

// One cache per request: rows that share a source share its reads.
function onceCache() {
    const cached = new Map()
    return (key, fn) => {
        if (!cached.has(key)) cached.set(key, Promise.resolve().then(fn))
        return cached.get(key)
    }
}
// Every source is optional. Reading machine information must never break settings.
async function optionalRead(readValue) {
    try { return await readValue() } catch (_) { return null }
}
const aboutText = path => optionalRead(() => read(path).trim() || null)
const pacmanLog = "/var/log/pacman.log"
function pacmanChunk(tail) {
    let stream
    try {
        const file = Gio.File.new_for_path(pacmanLog)
        stream = file.read(null)
        if (!tail) {
            // The timestamp starts the first line; no other part of that line is needed.
            return new TextDecoder().decode(stream.read_bytes(256, null).get_data()).split("\n")[0]
        }
        // Seek rather than loading a log that can be many years old.
        const size = file.query_info("standard::size", Gio.FileQueryInfoFlags.NONE, null).get_size()
        const offset = Math.max(0, size - 256 * 1024)
        stream.seek(offset, GLib.SeekType.SET, null)
        let content = new TextDecoder().decode(stream.read_bytes(256 * 1024, null).get_data())
        if (offset > 0) content = content.slice(content.indexOf("\n") + 1)
        return content
    } finally {
        if (stream) stream.close(null)
    }
}
async function pacmanDates() {
    // A failed tail read must not erase a readable installation timestamp.
    return {
        installed: await optionalRead(() => about.installedFromPacmanLog(pacmanChunk(false))),
        lastUpgrade: await optionalRead(() => about.lastFullUpgrade(pacmanChunk(true))),
    }
}
async function accountAvatar(user) {
    const face = GLib.get_home_dir() + "/.face"
    const paths = [face]
    if (user) paths.push("/var/lib/AccountsService/icons/" + user)
    for (const path of paths) {
        const readable = await optionalRead(() => Gio.File.new_for_path(path)
            .query_info("access::can-read", Gio.FileQueryInfoFlags.NONE, null)
            .get_attribute_boolean("access::can-read"))
        if (readable) return path
    }
    return ""
}
async function aboutState(mode) {
    const result = {}
    result.user = await optionalRead(() => GLib.get_user_name())
    result.realName = await optionalRead(() => {
        const name = GLib.get_real_name()
        return name && name !== "Unknown" ? name : null
    })
    result.host = await optionalRead(() => GLib.get_host_name())
    result.os = await optionalRead(async () => about.osName(await aboutText("/etc/os-release")) || null)
    result.kernel = await aboutText("/proc/sys/kernel/osrelease")
    result.hyprland = await optionalRead(async () => {
        const version = JSON.parse(await execAsync(["hyprctl", "version", "-j"]))
        const value = version.tag || version.version
        return typeof value === "string" ? value.replace(/^v/, "") || null : null
    })
    result.uptimeSeconds = await optionalRead(async () => {
        const raw = await aboutText("/proc/uptime")
        const number = raw === null ? NaN : Number(raw.split(/\s+/)[0])
        return Number.isFinite(number) && number >= 0 ? number : null
    })
    result.avatar = await accountAvatar(result.user)
    if (mode !== "full") return result
    result.session = await optionalRead(() => about.sessionName(GLib.getenv("XDG_CURRENT_DESKTOP"), GLib.getenv("XDG_SESSION_TYPE")) || null)
    const dates = await optionalRead(pacmanDates)
    result.installed = dates?.installed || await optionalRead(() => {
        const info = Gio.File.new_for_path("/").query_info("time::created", Gio.FileQueryInfoFlags.NONE, null)
        const seconds = info.get_attribute_uint64("time::created")
        return seconds > 0 ? new Date(seconds * 1000).toISOString() : null
    })
    result.lastUpgrade = dates?.lastUpgrade || null
    result.cpu = await optionalRead(async () => {
        const input = await aboutText("/proc/cpuinfo")
        return input ? about.cpuInfo(input) : null
    })
    result.memoryGB = await optionalRead(async () => about.memoryGB(await aboutText("/proc/meminfo")))
    result.gpus = await optionalRead(async () => GLib.find_program_in_path("lspci") ? about.gpus(await execAsync(["lspci", "-mm"])) : null)
    result.storage = await optionalRead(() => {
        const info = Gio.File.new_for_path("/").query_filesystem_info("filesystem::size,filesystem::used", null)
        return about.storageGB(info.get_attribute_uint64("filesystem::size"), info.get_attribute_uint64("filesystem::used"))
    })
    result.machine = await optionalRead(async () => about.machine({
        sysVendor: await aboutText("/sys/class/dmi/id/sys_vendor"), productName: await aboutText("/sys/class/dmi/id/product_name"),
        productVersion: await aboutText("/sys/class/dmi/id/product_version"),
        boardVendor: await aboutText("/sys/class/dmi/id/board_vendor"), boardName: await aboutText("/sys/class/dmi/id/board_name"),
    }))
    return result
}

async function snapshot(ids, includeMonitors, views = {}) {
    const once = onceCache()
    const values = {}
    await Promise.all(ids.map(async id => {
        const row = byId.get(id)
        if (!row) throw new Error("Unknown setting")
        try {
            let value, reset = false, note
            switch (row.source) {
            case "keyword": {
                const data = JSON.parse(await execAsync(["hyprctl", "getoption", row.key, "-j"]))
                value = keywordValue(data)
                if (row.kind === "toggle") value = value === true || value === 1
                else if (row.kind === "slider") value = Number(String(value).trim().split(/\s+/)[0])
                else value = String(value)
                reset = persist.hasOverride(row.key)
                break
            }
            case "animation": {
                const raw = await once("animations", async () => JSON.parse(await execAsync(["hyprctl", "animations", "-j"])))
                const tree = Array.isArray(raw[0]) ? raw[0] : raw
                const animation = tree.find(item => item.name === row.key)
                if (!animation) throw new Error("Animation is unavailable")
                value = animation.speed
                reset = persist.hasAnimationOverride(row.key)
                break
            }
            case "option":
                // A select with a default (bar-agenda, calendar-alert, calendar-duration) and the calendar
                // choice read a missing file as what their scripts use. Other rows still report it as missing,
                // so a save never recreates a file it has not read.
                // A switch's default is a boolean; its file holds "enabled" or "disabled".
                if (unsetReadsDefault(row)) value = exists(optionPath(row.key)) ? readOption(row.key)
                    : row.kind === "toggle" ? (row.default ? "enabled" : "disabled") : (row.default ?? "")
                else value = readOption(row.key)
                if (row.kind === "slider") {
                    // Read the way scripts/waybar/bar-modes.sh does: plain digits in
                    // range, anything else is the default the bar actually uses.
                    const number = /^\d+$/.test(value) ? Number(value) : NaN
                    value = number >= row.min && number <= row.max ? number : (row.default ?? row.min)
                }
                // Bar toggles default on (bar-border): bar-modes.sh treats anything but
                // "disabled" as enabled, so the row reads the same way.
                else if (row.kind === "toggle") value = row.key.startsWith("bar-") ? value !== "disabled" : value === "enabled"
                // The Bar page's renderers treat an unknown mode as the row's first
                // choice (scripts/waybar/bar-modes.sh and the module scripts), so the
                // row shows that choice instead of the raw file text.
                else if (row.key.startsWith("bar-") && row.items && !row.items.some(item => item.value === value)) value = row.items[0].value
                break
            case "cursor": value = Number(await execAsync(["gsettings", "get", ...gsettingsArgs("cursor-size")])); break
            case "gtk": value = gvariantValue(await execAsync(["gsettings", "get", ...gsettingsArgs(row.key)])); break
            case "idle": value = (await once("idle", () => idleValues(read(idlePath), readIdleState())))[row.key]; break
            case "sunset": value = (await once("sunset", () => sunsetValues(read(sunsetPath))))[row.key]; break
            case "swaync": value = (await once("swaync", () => JSON.parse(read(swayPath))))[row.key] ?? row.default; break
            case "kvantum": value = exists(kvantumPath) ? iniValue(read(kvantumPath), "theme", "General") : ""; break
            case "powerprofile": value = (await execAsync(["powerprofilesctl", "get"])).trim(); break
            case "mime": value = await mimeDefault(row.mimes[0]); break
            case "pulse": value = pulseValue(row.key, await once("pulse", pulseState)); break
            case "network": value = networkValue(row.key, await once("nm", nmSnapshot)); break
            case "region": ({ value, note } = await regionValue(row.key, read, exists)); break
            }
            if (row.default !== undefined) reset = value !== row.default
            const extra = note ? { note } : {}
            if (!row.choices) values[id] = { value, reset, ...extra }
            else {
                const choices = await choicesFor(row, value, once)
                // An unset or vanished calendar-default is the first writable calendar, which is what the card uses.
                if (row.choices === "calendars" && !choices.some(item => item.value === value)) value = choices[0]?.value ?? ""
                values[id] = { value, reset, ...extra, choices }
            }
        } catch (error) { values[id] = { error: error.message } }
    }))
    const result = { values }
    if (includeMonitors) {
        result.monitors = await displaysSnapshot()
        result.mainMonitor = readOption("mainmonitor")
        result.displayPending = exists(pendingPath) && await guardArmed() ? JSON.parse(read(pendingPath)) : null
    }
    if (views.network) result.network = networkPage(await once("nm", nmSnapshot))
    // A broken startup source must not blank the other pages' values.
    if (views.startup) {
        try { result.startup = await startupState() } catch (error) { result.startup = { error: error.message } }
    }
    if (views.about) {
        try { result.about = await aboutState(views.about) } catch (_) { result.about = null }
    }
    return result
}

const xkbLists = new Map()
function xkbList(...args) {
    const key = args.join(" ")
    if (!xkbLists.has(key)) xkbLists.set(key, execAsync(["localectl", ...args]).then(text => text.split("\n").filter(Boolean)))
    return xkbLists.get(key)
}
async function currentKeyword(key) {
    return String(keywordValue(JSON.parse(await execAsync(["hyprctl", "getoption", key, "-j"]))))
}
async function checkVariants(value, layouts) {
    if (!value) return
    const variants = value.split(",")
    if (variants.length > layouts.length) throw new Error("There are more variants than layouts")
    for (const [index, variant] of variants.entries()) {
        if (variant && !(await xkbList("list-x11-keymap-variants", layouts[index])).includes(variant))
            throw new Error(`${layouts[index]} has no variant ${variant}`)
    }
}
// A rejected keymap leaves Hyprland on its old one with only a log line, so
// every XKB name is checked before it is applied.
const checks = {
    "xkb-layout": async value => {
        const known = await xkbList("list-x11-keymap-layouts")
        const layouts = value.split(",")
        for (const layout of layouts) if (!known.includes(layout)) throw new Error(`Unknown keyboard layout ${layout}`)
        await checkVariants(await currentKeyword("input:kb_variant"), layouts)
    },
    "xkb-variant": async value => checkVariants(value, (await currentKeyword("input:kb_layout")).split(",")),
    "xkb-options": async value => {
        if (!value) return
        const known = await xkbList("list-x11-keymap-options")
        for (const option of value.split(",")) if (!known.includes(option)) throw new Error(`Unknown keyboard option ${option}`)
    },
    font: async value => {
        const families = (await execAsync(["fc-list", ":", "family"])).split("\n").flatMap(line => line.split(",")).map(name => name.trim())
        if (!families.includes(value)) throw new Error(`No installed font is named ${value}`)
    },
    command: value => {
        const program = value.split(/\s+/)[0]
        if (!GLib.find_program_in_path(program)) throw new Error(`${program} is not installed`)
    },
}
async function validate(row, value, once = onceCache()) {
    if (row.kind === "toggle" && typeof value !== "boolean") throw new Error("Expected an on/off value")
    if (row.kind === "slider" && (typeof value !== "number" || !Number.isFinite(value) || value < row.min || value > row.max)) throw new Error("Value is outside this setting's range")
    if (row.kind === "slider" && row.step >= 1 && !Number.isInteger(value)) throw new Error("Expected a whole number")
    if (row.kind === "select" && !(await choicesFor(row, undefined, once)).some(item => item.value === value)) throw new Error("Unknown choice")
    if (row.kind === "text") {
        if (typeof value !== "string" || /[\n\r\0]/.test(value) || value.length > 512) throw new Error("Enter a single-line value")
        if (!value.trim() && !row.optional) throw new Error("Enter a nonempty single-line value")
        if (row.check) await checks[row.check](value.trim())
    }
}
async function cursor(theme, size) {
    await execAsync(["gsettings", "set", ...gsettingsArgs("cursor-theme"), theme])
    await execAsync(["gsettings", "set", ...gsettingsArgs("cursor-size"), String(size)])
    writeGtkIni([["gtk-cursor-theme-name", theme], ["gtk-cursor-theme-size", String(size)]])
    await checkedHyprctl(["setcursor", theme, String(size)])
}
async function change(request) {
    const row = byId.get(request.id)
    if (!row) throw new Error("Unknown setting")
    if (request.op === "reset") {
        if (row.source === "keyword") {
            if (row.check === "xkb-layout" && persist.hasOverride("input:kb_variant")) throw new Error("Reset Layout Variant first; it may not exist for the default layout")
            return persist.resetSetting(row.key)
        }
        if (row.source === "animation") return persist.resetAnimation(row.key)
        if (row.default === undefined) throw new Error("This setting has no reset")
    }
    const value = request.op === "reset" ? row.default : request.value
    const once = onceCache()
    await validate(row, value, once)
    switch (row.source) {
    case "keyword": return persist.setPersistent(row.key, row.kind === "text" ? value.trim() : value)
    case "animation": {
        const raw = JSON.parse(await execAsync(["hyprctl", "animations", "-j"]))
        const animation = (Array.isArray(raw[0]) ? raw[0] : raw).find(item => item.name === row.key)
        if (!animation) throw new Error("Animation is unavailable")
        return persist.setAnimationPersistent(row.key, [row.key, animation.enabled ? 1 : 0, value, animation.bezier || "default", animation.style || ""].join(","))
    }
    case "option": {
        const text = row.kind === "toggle" ? (value ? "enabled" : "disabled") : row.kind === "slider" ? String(value) : value.trim()
        return saveAndApply(optionPath(row.key), text + "\n", async () => {
            if (row.key === "font" || row.key === "font-gtk") await execAsync(["bash", configDir + "/scripts/fonts/apply-font.sh"])
            if (row.key === "clock" || row.key === "clock-seconds") await execAsync(["bash", configDir + "/scripts/waybar/clock-format.sh"])
            if (row.key.startsWith("bar-")) await execAsync(["bash", configDir + "/scripts/waybar/bar-modes.sh"])
            if (row.key === "bar-agenda" || row.key.startsWith("calendar-")) await execAsync(["bash", configDir + "/scripts/calendar/sync.sh", "--render"])
            // Every app's "Show in folder" asks D-Bus, which this points at the new choice.
            if (row.key === "filemanager") await execAsync(["bash", configDir + "/scripts/settings/file-manager.sh"])
            // Desktop entries with Terminal=true open through xdg-terminal-exec, which this points at the new choice.
            if (row.key === "terminal") await execAsync(["bash", configDir + "/scripts/settings/terminal.sh"])
            // The Lua configuration reads these options at parse time.
            if (row.reload) await persistReload()
            if (row.key === "cursortheme") await cursor(readOption(row.key), Number(await execAsync(["gsettings", "get", ...gsettingsArgs("cursor-size")])))
        }, unsetReadsDefault(row))
    }
    case "cursor": {
        const size = Number(await execAsync(["gsettings", "get", ...gsettingsArgs("cursor-size")]))
        const theme = readOption("cursortheme")
        try { await cursor(theme, value) }
        catch (error) {
            try { await cursor(theme, size) }
            catch (rollback) { throw new Error(`${error.message}. Restoring the previous cursor also failed: ${rollback.message}`) }
            throw error
        }
        return
    }
    case "idle": {
        const tracked = read(idlePath)
        const before = readIdleState()
        idleValues(tracked, before)
        // A suspend listener written by hand in the tracked file is never retimed.
        if (/listener\s*\{[^}]*systemctl suspend/.test(tracked)) throw new Error("hypridle.conf has a custom suspend listener; change it by hand")
        const text = row.key === "suspend" ? withSuspend(before, value)
            : withVar(before, idleVars[row.key], value, hyprVar(tracked, idleVars[row.key]))
        makeParent(idleStatePath)
        return saveOrRemove(idleStatePath, text, () => restart("hypridle"))
    }
    case "sunset": {
        const before = read(sunsetPath)
        const schedule = sunsetValues(before)
        const updated = { ...schedule, [row.key]: value }
        if (updated.dayMinutes === updated.nightMinutes) throw new Error("Day and evening must start at different times")
        const text = before.replace(hyprVarLine(sunsetVars[row.key]), () => `$${sunsetVars[row.key]} = ${row.key === "nightTemp" ? value : clock(value)}`)
        return saveAndApply(sunsetPath, text, async () => { await syncOverlay(); await restart("hyprsunset") })
    }
    case "swaync": {
        const config = JSON.parse(read(swayPath))
        config[row.key] = value
        return saveAndApply(swayPath, JSON.stringify(config, null, 2) + "\n", () => execAsync(["swaync-client", "-rs"]))
    }
    case "kvantum": {
        const text = exists(kvantumPath) ? read(kvantumPath) : "[General]\n"
        const updated = iniSet(kvantumPath, text, "theme", value, "General")
        if (!exists(kvantumDirs[0])) Gio.File.new_for_path(kvantumDirs[0]).make_directory_with_parents(null)
        return write(kvantumPath, updated)
    }
    case "gtk": return setGtk(row, value)
    case "powerprofile": return execAsync(["powerprofilesctl", "set", value])
    case "pulse": return setPulse(row.key, value, await once("pulse", pulseState))
    case "network": requiredSnapshot(); return setWifiEnabled(value)
    case "region": return setRegion(row.key, value)
    case "mime": {
        const app = GioUnix.DesktopAppInfo.new(value)
        const declared = new Set(app?.get_supported_types() || [])
        // Every type is_a application/octet-stream, so that parent would claim the whole row.
        const parents = [...declared].filter(type => type !== "application/octet-stream")
        const mimes = row.mimes.filter(mime => declared.has(mime) || parents.some(type => Gio.content_type_is_a(mime, type)))
        if (!mimes.length) mimes.push(row.mimes[0])
        const path = GLib.get_user_config_dir() + "/mimeapps.list"
        const hadFile = exists(path)
        const before = hadFile ? readBytes(path) : null
        try {
            for (const mime of mimes) await execAsync(["xdg-mime", "default", value, mime])
        } catch (error) {
            try {
                if (hadFile) writeBytes(path, before)
                else if (exists(path)) Gio.File.new_for_path(path).delete(null)
            } catch (rollback) {
                error.message += `. Restoring mimeapps.list also failed: ${rollback.message}`
            }
            throw error
        }
        return
    }
    }
}

const readMonitors = async () => JSON.parse(await execAsync(["hyprctl", "monitors", "all", "-j"]))
const displayState = () => displays.parseStateFile(exists(displayStatePath) ? read(displayStatePath) : "")
async function guardArmed() {
    try { await execAsync(["systemctl", "--user", "is-active", "--quiet", `${guardUnit}.timer`]); return true }
    catch (_) { return false }
}
async function displaysSnapshot() {
    const state = displayState()
    return (await readMonitors()).map(monitor => ({
        ...monitor,
        saved: state.outputs[monitor.name] ?? null,
        handEdited: state.handEdited.has(monitor.name) || state.handEdited.has("*"),
        choices: { modes: displays.modeChoices(monitor), positions: displays.positions, transforms: displays.transforms },
    }))
}
function displayConfig(request, monitors) {
    const monitor = monitors.find(m => m.name === request.output)
    if (!monitor) throw new Error("Display is no longer connected")
    if (request.automatic === true) return { ...displays.AUTOMATIC }
    if (request.disabled === true) {
        if (!monitors.some(m => m.name !== monitor.name && !m.disabled)) throw new Error("At least one display must stay on")
        // hyprlock draws its password field on the main display.
        if (readOption("mainmonitor") === monitor.name) throw new Error("This is the main display; choose another main display first")
        return { disabled: true }
    }
    const config = { mode: request.mode, position: request.position, scale: request.scale, transform: request.transform }
    if (!displays.modeChoices(monitor).some(c => c.value === config.mode)) throw new Error("Unknown mode")
    if (!displays.positions.some(c => c.value === config.position)) throw new Error("Unknown position")
    if (!displays.transforms.some(c => c.value === config.transform)) throw new Error("Unknown rotation")
    if (!displays.scaleChoices(...displays.modeSize(config.mode, monitor)).some(c => c.value === config.scale))
        throw new Error("This scale does not divide the mode evenly")
    return config
}
// True if this call disarmed the guard; false if it had already fired or was
// never armed. Any other failure is real and is raised.
async function stopGuard() {
    try { await execAsync(["systemctl", "--user", "stop", `${guardUnit}.timer`]); return true }
    catch (error) {
        if (/not loaded/.test(error.message)) return false
        throw error
    }
}
// Nothing reaches monitors.lua before Keep, so reloading is always a correct
// revert. It reloads while the guard is still armed, so a failed reload or a
// dying process still leaves the guard to revert. Unrelated config errors must
// not block a revert, hence a plain reload rather than persistReload().
async function displayRevert() {
    await checkedHyprctl(["reload"])
    await stopGuard()
    if (exists(pendingPath)) remove(pendingPath)
    return { pending: null }
}
async function displayApply(request) {
    if (request.automatic === true && request.disabled === true) throw new Error("Choose Automatic or Off, not both")
    if (exists(pendingPath)) {
        if (await guardArmed()) throw new Error("A display change is waiting for Keep or Revert")
        remove(pendingPath) // The guard fired while no panel was watching.
    }
    const state = displayState()
    if (state.handEdited.has(request.output) || state.handEdited.has("*"))
        throw new Error(`${displayStatePath} was edited by hand; change ${request.output} there`)
    const line = displays.monitorLine(request.output, displayConfig(request, await readMonitors()))
    // The guard reverts even if the panel dies or its screen goes dark. Without a
    // signature here, the session's own one in the systemd manager is used.
    const signature = GLib.getenv("HYPRLAND_INSTANCE_SIGNATURE")
    await execAsync(["systemd-run", "--user", "--collect", `--unit=${guardUnit}`, "--on-active=20", "--timer-property=AccuracySec=100ms",
        ...(signature ? [`--setenv=HYPRLAND_INSTANCE_SIGNATURE=${signature}`] : []), GLib.find_program_in_path("hyprctl"), "reload"])
    try {
        await checkedHyprctl(["eval", line])
        // The one-shot guard must outlive the change it protects.
        if (!(await guardArmed())) throw new Error("The display change took too long and was reverted")
        // Recorded only now: Keep can only ever persist a line that was applied.
        const pending = { output: request.output, line, remove: request.automatic === true, deadline: Date.now() + 15000 }
        makeParent(pendingPath)
        write(pendingPath, JSON.stringify(pending) + "\n")
        return { pending }
    } catch (error) {
        await displayRevert()
        throw error
    }
}
async function displayKeep() {
    if (!exists(pendingPath)) throw new Error("No display change is waiting")
    const pending = JSON.parse(read(pendingPath))
    if (!(await guardArmed())) { remove(pendingPath); throw new Error("The change was already reverted") }
    // Written while the guard is still armed: whatever fails from here on, the
    // guard's reload reads this file, which is the layout being kept.
    try {
        makeParent(displayStatePath)
        write(displayStatePath, displays.stateFileWith(exists(displayStatePath) ? read(displayStatePath) : "", pending.output, pending.remove ? null : pending.line))
    } catch (error) {
        throw new Error(`${error.message}. The display will revert.`)
    }
    remove(pendingPath)
    await stopGuard()
    // A timer that already fired can still be reloading from the old file, and
    // stop cannot tell; reloading the kept file makes live and saved agree.
    await checkedHyprctl(["reload"])
    return { pending: null }
}

// While a display change awaits Keep or Revert, anything else could reload
// Hyprland (resets, reloading rows, actions) and silently undo it.
const displayOps = new Set(["read", "displayApply", "displayKeep", "displayRevert"])
export async function dispatch(request) {
    if (!displayOps.has(request.op) && exists(pendingPath) && await guardArmed())
        throw new Error("Keep or Revert the display change first")
    if (request.op === "read") {
        if (!Array.isArray(request.ids) || request.ids.length > catalog.rows.length) throw new Error("Invalid settings request")
        return snapshot([...new Set(request.ids)], request.monitors === true, { network: request.network === true, startup: request.startup === true, about: ["summary", "full"].includes(request.about) ? request.about : null })
    }
    if (request.op === "set" || request.op === "reset") {
        await change(request)
        if (overlaySources.has(byId.get(request.id)?.source)) await syncOverlay()
        return {}
    }
    if (request.op === "mainMonitor") {
        const monitors = JSON.parse(await execAsync(["hyprctl", "monitors", "-j"]))
        if (request.value !== "" && !monitors.some(m => m.name === request.value)) throw new Error("Display is no longer connected")
        if (typeof request.value !== "string" || /[\r\n\0$]/.test(request.value)) throw new Error("Invalid display name")
        const before = read(optionPath("mainmonitor"))
        write(optionPath("mainmonitor"), request.value + "\n")
        try { await syncOverlay() }
        catch (error) {
            write(optionPath("mainmonitor"), before)
            try { await syncOverlay() } catch (_) { /* The doctor reports a stale render. */ }
            throw error
        }
        return {}
    }
    if (request.op === "displayApply") return displayApply(request)
    if (request.op === "displayKeep") return displayKeep()
    if (request.op === "displayRevert") return displayRevert()
    if (request.op === "networkScan") { requiredSnapshot(); await requestScan(); return {} }
    if (request.op === "wifiConnect") {
        const plan = network.connectPlan(requiredSnapshot(), request)
        if (plan.kind === "activate") await activate(plan.uuid)
        else {
            await addAndActivate(plan)
            // Only once the new profile works are the old ones for this SSID removed,
            // each best-effort: a removal failure must not read back as a failed connect.
            // One of them being already gone (a race with something else removing it)
            // is not a failure at all.
            if (plan.replace.length) {
                // removeConnections reports an already-gone uuid structurally
                // (never throws for it), so any thrown error here is real.
                let firstError = null
                for (const uuid of plan.replace) {
                    try { await removeConnections([uuid]) }
                    catch (error) { firstError ??= error }
                }
                if (firstError) throw new Error(`Connected, but an old saved profile for this network could not be removed: ${firstError.message}`)
            }
        }
        return {}
    }
    if (request.op === "wifiForget") {
        // Best effort, one at a time: an already-missing profile is removed as
        // far as the user is concerned, and one real failure must not stop the
        // rest of this SSID's saved profiles from being removed.
        let firstError = null
        for (const uuid of network.forgetPlan(requiredSnapshot(), request.ssid)) {
            try { await removeConnections([uuid]) }
            catch (error) { firstError ??= error }
        }
        if (firstError) throw new Error(`Some saved profiles for this network could not be removed: ${firstError.message}`)
        return {}
    }
    if (request.op === "vpn") {
        const plan = network.vpnPlan(requiredSnapshot(), request)
        if (plan.active) await activate(plan.uuid); else await deactivate(plan.uuid)
        return {}
    }
    if (request.op === "autostart") { await autostartChange(request); return {} }
    if (request.op === "autostartAdd") { await autostartAdd(request); return {} }
    if (request.op === "action") {
        if (request.id === "autostart-file") {
            detached([readOption("terminal") || "ghostty", "-e", ...(readOption("editor") || "nvim").split(/\s+/), configDir + "/hypr/config/setup/autostart.lua"])
            return {}
        }
        if (request.id === "reload") { await persistReload(); return {} }
        if (request.id === "displays-file") {
            if (!exists(displayStatePath)) { makeParent(displayStatePath); write(displayStatePath, displays.STATE_HEADER) }
            detached([readOption("terminal") || "ghostty", "-e", ...(readOption("editor") || "nvim").split(/\s+/), displayStatePath])
            return {}
        }
        if (request.id === "protonApp") { detached(["protonvpn-app"]); return {} }
        if (request.id === "networkEditor") { detached(["nm-connection-editor"]); return {} }
        const scripts = { waybar: "/scripts/waybar/waybar.sh", update: "/scripts/settings/update.sh" }
        if (!Object.hasOwn(scripts, request.id)) throw new Error("Unknown action")
        const path = configDir + scripts[request.id]
        detached(request.id === "waybar" ? ["bash", path] : [readOption("terminal") || "ghostty", "-e", path])
        return {}
    }
    if (request.op === "calendarStatus") {
        const runtime = GLib.getenv("CALENDAR_RUNTIME_DIR") || (GLib.getenv("XDG_RUNTIME_DIR") || "/tmp") + "/calendar"
        let status = null
        try { status = JSON.parse(read(runtime + "/status.json")) } catch (error) { status = null }
        // secret-tool exits 1 with no output for an item that is not stored: that is signed out.
        // Any other failure means the keyring could not be read, and the reader must say so.
        let account = ""
        try { account = await execAsync(["secret-tool", "lookup", "service", "calendar-icloud", "field", "username"]) }
        catch (error) { if (error.status !== 1 || error.stderr) throw error }
        let calendars = []
        if (account) {
            // cal.sh prints {"ok":false,"error":…} and exits 1 when it cannot list.
            try { calendars = JSON.parse(await execAsync(["bash", configDir + "/scripts/calendar/cal.sh", "calendars"])) }
            catch (error) { throw new Error(helperFailure(error)) }
            if (!Array.isArray(calendars)) throw new Error("cal.sh did not list the calendars")
        }
        const hidden = exists(optionPath("calendar-hidden")) ? readOption("calendar-hidden").split("\n").map(s => s.trim()).filter(Boolean) : []
        return { calendar: { account, status, line: calendar.statusLine(status, Math.floor(Date.now() / 1000), account),
            calendars: calendars.map(c => ({ ...c, shown: !hidden.includes(c.name) })) } }
    }
    if (request.op === "calendarSignIn") {
        await execInput(calendar.signInCommand(configDir), calendar.signInInput(String(request.appleId || ""), String(request.password || "")))
        return {}
    }
    if (request.op === "calendarSignOut") { await execAsync(["bash", configDir + calendar.SETUP, "--sign-out"]); return {} }
    if (request.op === "calendarSync") { detached(["bash", configDir + "/scripts/calendar/sync.sh"]); return {} }
    if (request.op === "calendarShow") {
        if (typeof request.name !== "string" || /[\r\n]/.test(request.name)) throw new Error("Invalid calendar name")
        // A failed render restores the list (or removes a file that did not exist), as an option save does.
        const path = optionPath("calendar-hidden")
        const before = exists(path) ? readOption("calendar-hidden") : ""
        await saveAndApply(path, calendar.toggleHidden(before, request.name, request.shown === true),
            () => execAsync(["bash", configDir + "/scripts/calendar/sync.sh", "--render"]), true)
        await syncOverlay()
        return {}
    }
    throw new Error("Unknown operation")
}
// The message cal.sh (or any helper that prints {"ok":false,"error"}) gave for a failed run.
function helperFailure(error) {
    try { const reply = JSON.parse(error.stdout); if (reply && reply.error) return String(reply.error) } catch (_) { /* not JSON */ }
    return error.message
}
async function persistReload() {
    await checkedHyprctl(["reload"])
    const errors = JSON.parse(await execAsync(["hyprctl", "configerrors", "-j"]))
    if (!Array.isArray(errors) || errors.some(error => String(error).trim())) throw new Error("Hyprland reports configuration errors")
}
