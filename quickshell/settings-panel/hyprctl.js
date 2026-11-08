import { execAsync } from "./process.js"

export function luaValue(value) {
    if (typeof value === "boolean") return value ? "true" : "false"
    if (typeof value === "number") return String(value)
    if (value === "true" || value === "false") return value
    if (/^-?(?:\d+\.?\d*|\.\d+)$/.test(value)) return value
    return JSON.stringify(value)
}

/** The hl.animation() call for an animation line such as "windows,1,6,default,slide":
 *  evaluated live and written to overrides.lua from this one expression. */
export function animationExpression(line) {
    const [leaf, enabled, speed, bezier, ...styleParts] = String(line).split(",")
    const fields = [
        `leaf = ${JSON.stringify(leaf)}`,
        `enabled = ${enabled !== "0"}`,
        `speed = ${Number(speed)}`,
        `bezier = ${JSON.stringify(bezier)}`,
    ]
    const style = styleParts.join(",")
    if (style) fields.push(`style = ${JSON.stringify(style)}`)
    return `hl.animation({ ${fields.join(", ")} })`
}

export async function setKeyword(keyword, value) {
    let expression

    if (keyword === "animation") {
        expression = animationExpression(value)
    } else {
        let nested = luaValue(value)
        for (const key of keyword.split(":").reverse()) nested = `{ ${key} = ${nested} }`
        expression = `hl.config(${nested})`
    }

    await checkedHyprctl(["eval", expression])
}

/** hyprctl can report a Lua error in stdout even when the process exits zero. */
export async function checkedHyprctl(args) {
    const reply = (await execAsync(["hyprctl", ...args])).trim()
    if (reply !== "ok") throw new Error(reply || "Hyprland returned no confirmation")
}

export async function reloadConfig() {
    await checkedHyprctl(["reload"])
    const errors = JSON.parse(await execAsync(["hyprctl", "configerrors", "-j"]))
    if (!Array.isArray(errors) || errors.some(error => typeof error !== "string" || error.trim() !== "")) {
        throw new Error(`Hyprland configuration errors: ${JSON.stringify(errors)}`)
    }
}
