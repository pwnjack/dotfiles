import Gio from "gi://Gio"
import GLib from "gi://GLib"
import { interactiveErrorMessage } from "./authError.mjs"

// Plain JS in, fully unpacked JS out; `interactive` lets polkit show its dialog.
export function callSystem(name, path, iface, method, signature, args, { interactive = false } = {}) {
    return new Promise((resolve, reject) => {
        Gio.DBus.system.call(name, path, iface, method, signature ? new GLib.Variant(signature, args) : null, null,
            interactive ? Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION : Gio.DBusCallFlags.NONE,
            interactive ? 55000 : 5000, null, (connection, result) => {
                try { resolve(connection.call_finish(result).recursiveUnpack()) }
                catch (error) {
                    const timedOut = interactive && error.matches?.(Gio.io_error_quark(), Gio.IOErrorEnum.TIMED_OUT)
                    const message = interactiveErrorMessage(error.message, timedOut)
                    reject(message ? new Error(message) : error)
                }
            })
    })
}
export async function getProperty(name, path, iface, property) {
    const [value] = await callSystem(name, path, "org.freedesktop.DBus.Properties", "Get", "(ss)", [iface, property])
    return value
}
