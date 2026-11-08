import GLib from "gi://GLib"
import Gio from "gi://Gio"
import { luaValue, setKeyword, reloadConfig, animationExpression } from "./hyprctl.js"

// Per-machine state, never a tracked file: changing a setting must not dirty
// the dotfiles repo. hyprland.lua loads this file last, if it exists.
const STATE_HOME = GLib.getenv("XDG_STATE_HOME") || `${GLib.get_home_dir()}/.local/state`
const OVERRIDES_DIR = `${STATE_HOME}/hypr`
const OVERRIDES_PATH = `${OVERRIDES_DIR}/overrides.lua`

const HEADER = `--
-- PANEL-MANAGED OVERRIDES
-- Written by the Super+I settings panel (quickshell/settings-panel/persist.js).
-- Loaded last by ~/.config/hypr/hyprland.lua so these values win over the
-- tracked defaults. Per machine; not part of the dotfiles repo.
-- One hl.config() or hl.animation() call per line. Do not edit by hand; use the
-- panel, or delete a line to fall back to the tracked default.
--
`

function readLines() {
    try {
        const [ok, contents] = Gio.File.new_for_path(OVERRIDES_PATH).load_contents(null)
        if (!ok || !contents) throw new Error("Cannot read saved settings")
        return new TextDecoder().decode(contents).split("\n")
    } catch (e) {
        if (e instanceof GLib.Error && e.matches(Gio.io_error_quark(), Gio.IOErrorEnum.NOT_FOUND)) return []
        throw e
    }
}

function writeLines(lines) {
    const body = lines.filter(l => l.trim() !== "" && !l.startsWith("--")).join("\n")
    const text = HEADER + (body ? body + "\n" : "")
    GLib.mkdir_with_parents(OVERRIDES_DIR, 0o755)
    const [ok] = Gio.File.new_for_path(OVERRIDES_PATH).replace_contents(
        new TextEncoder().encode(text), null, false, Gio.FileCreateFlags.NONE, null)
    if (!ok) throw new Error("Cannot save settings")
}

// Serialize the whole apply/save operation, including rollback. Rapid slider
// changes must not race each other or a reset of another row.
let pending = Promise.resolve()
function enqueue(operation) {
    const result = pending.then(operation)
    pending = result.catch(() => {}) // caller receives the original rejection
    return result
}

async function applyAndSave(apply, save) {
    try {
        await apply()
    } catch (error) {
        console.error("Hyprland rejected a setting:", error)
        throw new Error("The setting could not be applied. Your saved settings are unchanged.")
    }
    try {
        save()
    } catch (error) {
        console.error("Could not save settings:", error)
        try { await reloadConfig() }
        catch (rollbackError) {
            console.error("Could not restore saved settings:", rollbackError)
            throw new Error("The setting could not be saved or restored. Reload Hyprland before trying again.")
        }
        throw new Error("The setting could not be saved. Your saved settings have been restored.")
    }
}

function displayLines() {
    try { return readLines() }
    catch (error) {
        console.error("Could not read saved settings:", error)
        return []
    }
}

export function getOverride(keyword) {
    for (const line of displayLines()) {
        const m = line.match(/-- @override (\S+) (.*)$/)
        if (m && m[1] === keyword) return m[2]
    }
    return null
}

export function hasOverride(keyword) {
    return getOverride(keyword) !== null
}

function configCall(keyword, value) {
    let nested = luaValue(value)
    for (const key of keyword.split(":").reverse()) nested = `{ ${key} = ${nested} }`
    const marker = typeof value === "boolean" ? (value ? "true" : "false") : String(value)
    return `hl.config(${nested}) -- @override ${keyword} ${marker}`
}

function upsert(keyword, value) {
    const lines = readLines().filter(l => !l.includes(`-- @override ${keyword} `))
    lines.push(configCall(keyword, value))
    writeLines(lines)
}

/** Apply now via hyprctl AND persist to overrides.lua. */
export function setPersistent(keyword, value) {
    return enqueue(() => applyAndSave(() => setKeyword(keyword, value), () => upsert(keyword, value)))
}

/** Remove an override, then let Hyprland evaluate the real configuration defaults. */
async function resetMatching(matches) {
    let before
    try { before = readLines() }
    catch (error) {
        console.error("Could not read settings for reset:", error)
        throw new Error("Your saved settings could not be read. Nothing has been reset.")
    }
    try { writeLines(before.filter(line => !matches(line))) }
    catch (error) {
        console.error("Could not save reset:", error)
        throw new Error("The setting could not be reset. Your saved settings are unchanged.")
    }
    try { await reloadConfig() }
    catch (error) {
        console.error("Could not apply reset:", error)
        try {
            writeLines(before)
            await reloadConfig()
        } catch (rollbackError) {
            console.error("Could not restore settings after reset:", rollbackError)
            throw new Error("The reset failed and could not be fully restored. Check your Hyprland configuration before trying again.")
        }
        throw new Error("The setting could not be reset. Your previous settings have been restored.")
    }
}

export function resetSetting(keyword) {
    return enqueue(() => resetMatching(line => line.includes(`-- @override ${keyword} `)))
}

/**
 * Persist a full animation line, e.g. "windows,1,6,default".
 * Stored as an hl.animation() call; matched/replaced by its marker comment.
 */
export function setAnimationPersistent(name, line) {
    return enqueue(() => applyAndSave(() => setKeyword("animation", line), () => {
        const lines = readLines().filter(l => !l.endsWith(`-- @animation ${name}`))
        lines.push(`${animationExpression(line)} -- @animation ${name}`)
        writeLines(lines)
    }))
}

export function hasAnimationOverride(name) {
    return displayLines().some(l => l.endsWith(`-- @animation ${name}`))
}

export function resetAnimation(name) {
    return enqueue(() => resetMatching(line => line.endsWith(`-- @animation ${name}`)))
}
